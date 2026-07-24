import AppKit
import Foundation

// ZapretToggle — menu bar controller for bol-van/zapret on macOS
// Calls: sudo /usr/local/bin/zapret-ctl <whitelist-cmd>
// Portable paths only (no user home directories).

private let ctlPath = "/usr/local/bin/zapret-ctl"
private let fallbackCtl = "/opt/zapret/local-tools/zapret-ctl"
private let fixDnsScript = "/opt/zapret/local-tools/fix-dns-turkey.sh"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isBusy = false
    private var isOn = false
    private var updateAvailable: String? // remote version if any

    private var statusMenuItem: NSMenuItem!
    private var openItem: NSMenuItem!
    private var closeItem: NSMenuItem!
    private var refreshItem: NSMenuItem!
    private var listsItem: NSMenuItem!
    private var dnsItem: NSMenuItem!
    private var netStatusItem: NSMenuItem!
    private var netProbeItem: NSMenuItem!
    private var netApplyItem: NSMenuItem!
    private var discordDiagItem: NSMenuItem!
    private var checkUpdateItem: NSMenuItem!
    private var selfUpdateItem: NSMenuItem!
    private var engineItem: NSMenuItem!
    private var rollbackItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "Z"
            button.toolTip = "Zapret"
            button.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        }

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Durum: …", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        openItem = NSMenuItem(title: "Aç", action: #selector(startZapret), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        closeItem = NSMenuItem(title: "Kapat", action: #selector(stopZapret), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        refreshItem = NSMenuItem(title: "Durumu yenile", action: #selector(refreshStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        listsItem = NSMenuItem(title: "Listeleri güncelle", action: #selector(updateLists), keyEquivalent: "")
        listsItem.target = self
        menu.addItem(listsItem)

        dnsItem = NSMenuItem(title: "DNS düzelt (bu ağ)", action: #selector(fixDns), keyEquivalent: "")
        dnsItem.target = self
        menu.addItem(dnsItem)

        menu.addItem(NSMenuItem.separator())

        netStatusItem = NSMenuItem(title: "Ağ: …", action: nil, keyEquivalent: "")
        netStatusItem.isEnabled = false
        menu.addItem(netStatusItem)

        netProbeItem = NSMenuItem(title: "Bu ağı yeniden ayarla", action: #selector(netProbe), keyEquivalent: "")
        netProbeItem.target = self
        menu.addItem(netProbeItem)

        netApplyItem = NSMenuItem(title: "Bu ağ profilini uygula", action: #selector(netApply), keyEquivalent: "")
        netApplyItem.target = self
        menu.addItem(netApplyItem)

        discordDiagItem = NSMenuItem(title: "Discord/Vencord teşhis…", action: #selector(discordDiag), keyEquivalent: "")
        discordDiagItem.target = self
        menu.addItem(discordDiagItem)

        menu.addItem(NSMenuItem.separator())

        checkUpdateItem = NSMenuItem(title: "Güncellemeleri kontrol et", action: #selector(checkUpdate), keyEquivalent: "")
        checkUpdateItem.target = self
        menu.addItem(checkUpdateItem)

        selfUpdateItem = NSMenuItem(title: "Uygulamayı güncelle…", action: #selector(selfUpdate), keyEquivalent: "")
        selfUpdateItem.target = self
        menu.addItem(selfUpdateItem)

        engineItem = NSMenuItem(title: "Motoru güncelle (bol-van)…", action: #selector(updateEngine), keyEquivalent: "")
        engineItem.target = self
        menu.addItem(engineItem)

        rollbackItem = NSMenuItem(title: "Son motora geri dön", action: #selector(rollbackEngine), keyEquivalent: "")
        rollbackItem.target = self
        menu.addItem(rollbackItem)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Çıkış", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshStatus()

        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }

        // Background update check shortly after launch, then daily
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.backgroundCheckUpdate(showAlertIfNone: false)
        }
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.backgroundCheckUpdate(showAlertIfNone: false)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func startZapret() {
        runCtl("start", busyTitle: "Açılıyor…")
    }

    @objc private func stopZapret() {
        runCtl("stop", busyTitle: "Kapatılıyor…")
    }

    @objc private func updateLists() {
        runCtl("update-lists", busyTitle: "Listeler güncelleniyor…")
    }


    @objc private func netProbe() {
        let alert = NSAlert()
        alert.messageText = "Bu ağı yeniden ayarla?"
        alert.informativeText = """
        Mevcut Wi‑Fi için DNS zehiri ve DPI stratejisi test edilir (~30 sn).
        Sonuç bu ağa kaydedilir; sonraki bağlantılarda otomatik uygulanır.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Başla")
        alert.addButton(withTitle: "İptal")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runCtl("net-probe", busyTitle: "Ağ ayarlanıyor…", longRunning: true)
    }


    @objc private func discordDiag() {
        guard !isBusy else { return }
        setBusy(true, title: "Discord teşhis…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runProcess(args: ["discord-diag"], useSudo: true)
                ?? self?.runProcess(args: ["discord-diag"], useSudo: false)
                ?? (1, "ctl yok")
            DispatchQueue.main.async {
                self?.setBusy(false, title: nil)
                let out = result.1
                let alert = NSAlert()
                alert.messageText = "Discord.app + Vencord teşhis"
                var hint = ""
                var cause = ""
                for line in out.split(separator: "\n").map(String.init) {
                    if line.hasPrefix("ROOT_CAUSE=") { cause = String(line.dropFirst(11)) }
                    if line.hasPrefix("HINT=") { hint = String(line.dropFirst(5)) }
                }
                var body = ""
                if !cause.isEmpty { body += "Sonuç: \(cause)\n\n" }
                if !hint.isEmpty { body += "\(hint)\n\n" }
                body += "Ayrı client (Vesktop vb.) gerekmez — resmi Discord.app + Vencord.\n\n"
                body += String(out.suffix(900))
                alert.informativeText = body
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Tamam")
                if cause.contains("VENCORD") || cause.contains("OK_OR_UNKNOWN") {
                    alert.addButton(withTitle: "Vencord Repair sayfası")
                }
                if cause.contains("GITHUB") {
                    alert.addButton(withTitle: "Bu ağı yeniden ayarla")
                }
                let r = alert.runModal()
                if r == .alertSecondButtonReturn {
                    if cause.contains("GITHUB") {
                        self?.netProbe()
                    } else {
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        p.arguments = ["https://vencord.dev/download/"]
                        try? p.run()
                    }
                } else if r == .alertThirdButtonReturn {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    p.arguments = ["https://vencord.dev/download/"]
                    try? p.run()
                }
            }
        }
    }

    @objc private func netApply() {
        runCtl("net-apply", busyTitle: "Profil uygulanıyor…", longRunning: true)
    }

    @objc private func fixDns() {
        guard !isBusy else { return }
        setBusy(true, title: "DNS düzeltiliyor…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var result = self?.runShellScript(fixDnsScript) ?? (1, "script yok")
            if result.0 != 0 {
                result = self?.runProcess(args: ["fix-dns"], useSudo: false) ?? result
                if result.0 != 0 {
                    result = self?.runProcess(args: ["fix-dns"], useSudo: true) ?? result
                }
            }
            DispatchQueue.main.async {
                self?.setBusy(false, title: nil)
                self?.refreshStatus()
                let alert = NSAlert()
                if result.0 == 0 {
                    alert.messageText = "DNS düzeltildi"
                    alert.informativeText = """
                    Wi‑Fi DNS: 1.1.1.1 / 1.0.0.1 / 8.8.8.8

                    Discord yine açılmazsa tarayıcıyı ve Discord app’i tamamen kapatıp aç.

                    \(String(result.1.suffix(500)))
                    """
                    alert.alertStyle = .informational
                } else {
                    alert.messageText = "DNS düzeltilemedi"
                    let body = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
                    alert.informativeText = body.isEmpty
                        ? "Terminalde dene:\n\(fixDnsScript)"
                        : String(body.prefix(800))
                    alert.alertStyle = .warning
                }
                alert.runModal()
            }
        }
    }

    private func runShellScript(_ path: String) -> (Int32, String) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return (127, "Script bulunamadı: \(path)")
        }
        let proc = Process()
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = []
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (proc.terminationStatus, text)
        } catch {
            return (1, "Çalıştırılamadı: \(error.localizedDescription)")
        }
    }

    @objc private func checkUpdate() {
        guard !isBusy else { return }
        setBusy(true, title: "Güncelleme kontrol…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runProcess(args: ["check-update"], useSudo: true)
                ?? self?.runProcess(args: ["check-update"], useSudo: false)
                ?? (1, "ctl yok")
            DispatchQueue.main.async {
                self?.setBusy(false, title: nil)
                self?.handleCheckUpdateResult(result.1, showAlertIfNone: true)
                self?.refreshStatus()
            }
        }
    }

    private func backgroundCheckUpdate(showAlertIfNone: Bool) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = self?.runProcess(args: ["check-update"], useSudo: true)
                ?? self?.runProcess(args: ["check-update"], useSudo: false)
                ?? (1, "")
            DispatchQueue.main.async {
                self?.handleCheckUpdateResult(result.1, showAlertIfNone: showAlertIfNone)
            }
        }
    }

    private func handleCheckUpdateResult(_ out: String, showAlertIfNone: Bool) {
        let line = out.split(separator: "\n").map(String.init).first ?? out
        if line.hasPrefix("UPDATE_AVAILABLE") {
            let parts = line.split(separator: " ").map(String.init)
            let remote = parts.count >= 3 ? parts[2] : "?"
            updateAvailable = remote
            selfUpdateItem.title = "Uygulamayı güncelle… (v\(remote))"
            if showAlertIfNone {
                let alert = NSAlert()
                alert.messageText = "Güncelleme var: v\(remote)"
                alert.informativeText = "Menüden «Uygulamayı güncelle…» ile yükleyebilirsiniz.\nEski kurulum silinir, yenisi kurulur (hostlist korunur)."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Tamam")
                alert.runModal()
            }
        } else if line.hasPrefix("UP_TO_DATE") {
            updateAvailable = nil
            selfUpdateItem.title = "Uygulamayı güncelle…"
            if showAlertIfNone {
                let local = line.split(separator: " ").map(String.init).dropFirst().first ?? "?"
                let alert = NSAlert()
                alert.messageText = "Güncelsiniz"
                alert.informativeText = "Kurulu sürüm: v\(local)"
                alert.alertStyle = .informational
                alert.runModal()
            }
        } else if showAlertIfNone {
            let alert = NSAlert()
            alert.messageText = "Kontrol başarısız"
            alert.informativeText = line.isEmpty ? "Ağ veya GitHub API erişilemedi." : String(line.prefix(400))
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func selfUpdate() {
        let alert = NSAlert()
        alert.messageText = "Uygulamayı güncelle?"
        alert.informativeText = """
        GitHub Releases’ten son ZapretMenu paketi indirilir:
        • Eski /opt/zapret yedeklenir, sonra temiz kurulur
        • Motor, launchd (KeepAlive), scriptler ve menü yenilenir
        • Hostlist’iniz korunur
        • SHA256 doğrulaması zorunludur

        Devam edilsin mi?
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Güncelle")
        alert.addButton(withTitle: "İptal")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard !isBusy else { return }
        setBusy(true, title: "Güncelleniyor…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runProcess(args: ["self-update"], useSudo: true) ?? (1, "ctl yok")
            DispatchQueue.main.async {
                self?.setBusy(false, title: nil)
                self?.refreshStatus()
                let alert = NSAlert()
                let body = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.0 == 0, body.contains("UPDATED") || body.contains("UP_TO_DATE") {
                    alert.messageText = body.contains("UP_TO_DATE") ? "Zaten güncel" : "Güncelleme tamam"
                    alert.informativeText = """
                    \(String(body.suffix(500)))

                    Menü uygulaması yenilendiyse bir kez kapatıp tekrar açın:
                    open -a ZapretToggle
                    """
                    alert.alertStyle = .informational
                    self?.updateAvailable = nil
                    self?.selfUpdateItem.title = "Uygulamayı güncelle…"
                    // Relaunch menubar if possible
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        p.arguments = ["-a", "ZapretToggle"]
                        try? p.run()
                    }
                } else {
                    alert.messageText = "Güncelleme başarısız"
                    alert.informativeText = body.isEmpty
                        ? "Terminal: sudo \(ctlPath) self-update"
                        : String(body.prefix(800))
                    alert.alertStyle = .warning
                }
                alert.runModal()
            }
        }
    }

    @objc private func updateEngine() {
        let alert = NSAlert()
        alert.messageText = "Motoru güncelle (bol-van)?"
        alert.informativeText = """
        Sadece bol-van/zapret motor kaynağını günceller.
        Paket / menü / launchd için «Uygulamayı güncelle…» kullanın.

        Devam?
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Güncelle")
        alert.addButton(withTitle: "İptal")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        runCtl("update-engine", busyTitle: "Motor güncelleniyor…", longRunning: true)
    }

    @objc private func rollbackEngine() {
        let alert = NSAlert()
        alert.messageText = "Son motora geri dön?"
        alert.informativeText = "Son yedeklenen motor sürümüne dönülecek."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Geri dön")
        alert.addButton(withTitle: "İptal")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runCtl("rollback-engine", busyTitle: "Geri alınıyor…")
    }

    @objc private func refreshStatus() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runProcess(args: ["status"], useSudo: true) ?? (1, "ctl yok")
            let net = self?.runProcess(args: ["net-status"], useSudo: true) ?? (1, "")
            let out = result.1
            let netOut = net.1
            DispatchQueue.main.async {
                self?.updateNetMenu(netOut)
            }
            let on: Bool
            if out.contains("Zapret: Acik") || out.contains("Zapret: Açık") {
                on = true
            } else if out.contains("Zapret: Kapali") || out.contains("Zapret: Kapalı") {
                on = false
            } else {
                on = out.contains("tpws: calisiyor")
            }
            let desiredOn = out.contains("desired: on") || out.contains("desired:on")
            DispatchQueue.main.async {
                self?.applyStatus(on: on, desiredOn: desiredOn, detail: out)
            }
        }
    }


    private func updateNetMenu(_ out: String) {
        guard netStatusItem != nil else { return }
        var display = "Ağ"
        var strategy = ""
        for line in out.split(separator: "\n").map(String.init) {
            if line.hasPrefix("display=") { display = String(line.dropFirst(8)) }
            if line.hasPrefix("ssid="), display == "Ağ" || display.isEmpty {
                let s = String(line.dropFirst(5))
                if !s.isEmpty { display = s }
            }
            if line.hasPrefix("strategy=") { strategy = String(line.dropFirst(9)) }
            if line.hasPrefix("profile=no") { strategy = "kayıt yok" }
        }
        if strategy.isEmpty {
            netStatusItem.title = "Ağ: \(display)"
        } else {
            netStatusItem.title = "Ağ: \(display) · \(strategy)"
        }
    }

    private func applyStatus(on: Bool, desiredOn: Bool = true, detail: String = "") {
        isOn = on
        var title: String
        if on {
            title = "Durum: Açık"
            statusItem.button?.title = "Z●"
            statusItem.button?.toolTip = "Zapret: Açık"
        } else if desiredOn {
            title = "Durum: Kapalı (yeniden başlıyor…)"
            statusItem.button?.title = "Z○"
            statusItem.button?.toolTip = "İstenen: açık — KeepAlive anında yeniden başlatır"
        } else {
            title = "Durum: Kapalı"
            statusItem.button?.title = "Z○"
            statusItem.button?.toolTip = "Zapret: Kapalı"
        }
        if let v = updateAvailable {
            title += " · Güncelleme: v\(v)"
        }
        statusMenuItem.title = title
        openItem.isEnabled = !isBusy && !on
        closeItem.isEnabled = !isBusy && on
        if !isBusy {
            listsItem.isEnabled = true
            dnsItem.isEnabled = true
            if netProbeItem != nil { netProbeItem.isEnabled = true }
            if netApplyItem != nil { netApplyItem.isEnabled = true }
            if discordDiagItem != nil { discordDiagItem.isEnabled = true }
            checkUpdateItem.isEnabled = true
            selfUpdateItem.isEnabled = true
            engineItem.isEnabled = true
            rollbackItem.isEnabled = true
            refreshItem.isEnabled = true
        }
        _ = detail
    }

    private func setBusy(_ busy: Bool, title: String?) {
        isBusy = busy
        openItem.isEnabled = !busy
        closeItem.isEnabled = !busy
        listsItem.isEnabled = !busy
        dnsItem.isEnabled = !busy
        if netProbeItem != nil { netProbeItem.isEnabled = !busy }
        if netApplyItem != nil { netApplyItem.isEnabled = !busy }
        if discordDiagItem != nil { discordDiagItem.isEnabled = !busy }
        checkUpdateItem.isEnabled = !busy
        selfUpdateItem.isEnabled = !busy
        engineItem.isEnabled = !busy
        rollbackItem.isEnabled = !busy
        refreshItem.isEnabled = !busy
        if busy, let title {
            statusMenuItem.title = title
            statusItem.button?.title = "Z…"
        }
    }

    private func runCtl(_ cmd: String, busyTitle: String, longRunning: Bool = false) {
        guard !isBusy else { return }
        setBusy(true, title: busyTitle)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runProcess(args: [cmd], useSudo: true) ?? (1, "ctl yok")
            DispatchQueue.main.async {
                self?.setBusy(false, title: nil)
                self?.refreshStatus()
                if result.0 != 0 {
                    let alert = NSAlert()
                    alert.messageText = "İşlem başarısız: \(cmd)"
                    let body = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
                    alert.informativeText = body.isEmpty
                        ? "Çıkış kodu: \(result.0). Terminalde: sudo \(ctlPath) \(cmd)"
                        : String(body.prefix(800))
                    alert.alertStyle = .warning
                    alert.runModal()
                } else if longRunning {
                    let alert = NSAlert()
                    alert.messageText = "Motor güncelleme tamam"
                    alert.informativeText = String(result.1.suffix(400))
                    alert.runModal()
                }
            }
        }
    }

    private func resolveCtl() -> String? {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: ctlPath) { return ctlPath }
        if fm.isExecutableFile(atPath: fallbackCtl) { return fallbackCtl }
        return nil
    }

    private func runProcess(args: [String], useSudo: Bool) -> (Int32, String) {
        guard let ctl = resolveCtl() else {
            return (127, "zapret-ctl bulunamadı. Önce Zapret Kurulum uygulamasını çalıştırın.")
        }
        let proc = Process()
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        if useSudo {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            proc.arguments = ["-n", ctl] + args
        } else {
            proc.executableURL = URL(fileURLWithPath: ctl)
            proc.arguments = args
        }
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            if proc.terminationStatus == 1, text.lowercased().contains("password") {
                return (1, "sudo şifresi gerekli. Kurulumu tekrar çalıştırın (Zapret Kurulum.app).")
            }
            return (proc.terminationStatus, text)
        } catch {
            return (1, "Çalıştırılamadı: \(error.localizedDescription)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
