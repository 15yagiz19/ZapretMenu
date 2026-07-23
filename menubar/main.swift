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

    private var statusMenuItem: NSMenuItem!
    private var openItem: NSMenuItem!
    private var closeItem: NSMenuItem!
    private var refreshItem: NSMenuItem!
    private var listsItem: NSMenuItem!
    private var dnsItem: NSMenuItem!
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

        dnsItem = NSMenuItem(title: "DNS düzelt (Wi‑Fi)", action: #selector(fixDns), keyEquivalent: "")
        dnsItem.target = self
        menu.addItem(dnsItem)

        engineItem = NSMenuItem(title: "Motoru güncelle…", action: #selector(updateEngine), keyEquivalent: "")
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

    @objc private func updateEngine() {
        let alert = NSAlert()
        alert.messageText = "Motoru güncelle?"
        alert.informativeText = """
        Bu işlem birkaç dakika sürebilir:
        • Mevcut motor yedeklenir
        • Sadece resmi bol-van/zapret kaynağından güncellenir
        • Hostlist ve ayarlarınız korunur
        • Başarısız olursa otomatik geri alınır

        Devam edilsin mi?
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
            let out = result.1
            // Prefer explicit "Zapret: Acik/Kapali" line over substring matches
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

    private func applyStatus(on: Bool, desiredOn: Bool = true, detail: String = "") {
        isOn = on
        if on {
            statusMenuItem.title = "Durum: Açık"
            statusItem.button?.title = "Z●"
            statusItem.button?.toolTip = "Zapret: Açık"
        } else if desiredOn {
            statusMenuItem.title = "Durum: Kapalı (yeniden başlatılıyor…)"
            statusItem.button?.title = "Z○"
            statusItem.button?.toolTip = "İstenen: açık, tpws yok — watchdog ~30 sn içinde başlatır"
        } else {
            statusMenuItem.title = "Durum: Kapalı"
            statusItem.button?.title = "Z○"
            statusItem.button?.toolTip = "Zapret: Kapalı"
        }
        openItem.isEnabled = !isBusy && !on
        closeItem.isEnabled = !isBusy && on
        if !isBusy {
            listsItem.isEnabled = true
            dnsItem.isEnabled = true
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
