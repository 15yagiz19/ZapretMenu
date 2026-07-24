# Zapret (Mac) — kısa kullanım

Bu klasör, **resmi** [bol-van/zapret](https://github.com/bol-van/zapret) motorunu Mac’te **hostlist** modunda çalıştırmak ve menü çubuğundan Aç/Kapat yapmak içindir.

> Zapret VPN değildir. Trafiğini şifrelemez. Sadece bazı engelli sitelerin DPI engelini aşmaya çalışır.

## Arkadaşa göndermek (DMG) / Release

```bash
./scripts/package-dmg.sh
```

Çıktı:

| Dosya | Ne işe yarar |
|-------|----------------|
| `dist/Zapret-macOS.dmg` | İlk kurulum (çift tık) |
| `dist/ZapretMenu-update.tar.gz` | Menü **self-update** (GitHub asset) |
| `dist/SHA256SUMS` | Self-update doğrulama (zorunlu) |

```bash
gh release create v1.1.0 \
  dist/Zapret-macOS.dmg \
  dist/ZapretMenu-update.tar.gz \
  dist/SHA256SUMS
```

Alıcı (ilk kurulum): DMG aç → **Zapret Kurulum** → şifre → menüde **Z**.

## Geliştirici / bu makine (kaynak ağaçtan)

```bash
sudo ./scripts/system-install.sh
./scripts/install-menubar.sh
```

Menü çubuğunda **Z** ikonu görünür.

Kurulum sonrası taşınabilir yollar:

| Ne | Nerede |
|----|--------|
| Motor | `/opt/zapret` |
| Scriptler | `/opt/zapret/local-tools/` |
| Config kopyası | `/Library/Application Support/Zapret/` |
| ctl | `/usr/local/bin/zapret-ctl` |
| Menü | `/Applications/ZapretToggle.app` |

### Girişte otomatik açılsın (isteğe bağlı)

**Sistem Ayarları → Genel → Login Items → +** → `ZapretToggle` ekleyin.  
(Motor zaten sistem servisi olarak ayrı çalışır; menü sadece kontrol panelidir.)

---

## Günlük kullanım

| Menü | Ne yapar |
|------|----------|
| **Durum** | Açık / Kapalı |
| **Aç** | Zapret’i başlatır |
| **Kapat** | Zapret’i durdurur (acil çıkış) |
| **Durumu yenile** | Durumu tekrar okur |
| **Listeleri güncelle** | Domain listesini tazeler (hızlı) |
| **DNS düzelt (Wi‑Fi)** | Wi‑Fi DNS → 1.1.1.1 / 1.0.0.1 / 8.8.8.8 |
| **Güncellemeleri kontrol et** | GitHub Releases son sürüm |
| **Uygulamayı güncelle…** | Paketi indirir; eskiyi siler, yenisini kurar (hostlist korunur) |
| **Motoru güncelle (bol-van)…** | Sadece bol-van motor kaynağı (ikincil) |
| **Son motora geri dön** | Son motor yedeğine döner |
| **Çıkış** | Sadece menü uygulamasını kapatır (motor açık kalabilir) |

### Güncelleme (kullanıcı)

Sen GitHub’a yeni release attıktan sonra kullanıcı:

1. Menü → **Güncellemeleri kontrol et** veya otomatik uyarı  
2. **Uygulamayı güncelle…** → Onay  

veya Terminal:

```bash
sudo zapret-ctl check-update
sudo zapret-ctl self-update
```

Üzerine kurulum **temiz replace**: eski `/opt/zapret` yedeklenir, yenisi kurulur; hostlist Application Support’ta korunur.

- **Z●** = açık · **Z○** = kapalı  
- Her tıklamada şifre **sormaması** için `system-install.sh` içindeki dar `sudoers` kuralı gerekir (hedef kullanıcıya özel).

---


## Neden "kendi kendine kapanıyor"du?

Eski model: launchd boot’ta bir kez `start` → `tpws --daemon` → script çıkıyordu.  
`tpws` ölünce kimse tutmuyordu. v1.0.6’daki 30 sn watchdog da boşluk bırakıyordu.

**v1.0.7+:** launchd **KeepAlive** ile `tpws` **ön planda** çalışır:

- Menü **Açık** (`desired=on`) → ölse bile **saniyeler içinde** yeniden açılır  
- Menü **Kapat** (`desired=off`) → job unload → **kalıcı kapalı**  
- 30 sn bekleme yok

Test:

```bash
sudo kill $(pgrep -x tpws)
sleep 3
sudo zapret-ctl status   # yine Acik olmali
```

## Bozulursa ne yapmalı?

1. Menüden **Kapat**  
2. Hâlâ sorun varsa Terminal:

```bash
sudo /usr/local/bin/zapret-ctl stop
```

3. Motor güncellemesi bozduysa: menüden **Son motora geri dön** veya:

```bash
sudo /usr/local/bin/zapret-ctl rollback-engine
```

4. Tam kaldırma:

```bash
sudo /opt/zapret/local-tools/zapret-uninstall.sh --yes
# veya workspace'ten:
sudo ./scripts/zapret-uninstall.sh --yes
```

PF yedeği: `/Library/Application Support/Zapret/backups/`

---

## Tailscale

- **Tailscale açık kalsın** (VDS / MagicDNS bozulmaz diye hostlist’e eklenmedi).  
- Zapret yalnızca listedeki domainlere (Discord, YouTube, Instagram, X, …) dokunur.  
- Bir şey bozulursa önce menüden **Kapat**.
- MagicDNS açık kalsın; Wi‑Fi DNS’i **router (192.168.x.1) olmasın** — bazı Türk ISP’ler Discord’u DNS’te zehirler (`195.175.254.2`).  
  Önerilen Wi‑Fi DNS: `1.1.1.1`, `1.0.0.1`, `8.8.8.8`  
  **Wi‑Fi yeniden bağlanınca Discord ölürse:** menüden **DNS düzelt (Wi‑Fi)**

## WARP

Cloudflare WARP **kapalı** olmalı (çakışma riski).

## QUIC / HTTP3

macOS’ta motor yalnızca **TCP** (tpws) bozar. Zapret açıkken **UDP 443 (QUIC)** PF ile düşürülür; tarayıcı TCP’ye düşer. Tailscale UDP 41641’e dokunulmaz.

---

## Hostlist (hangi siteler)

Dosya (canlı): `/opt/zapret/ipset/zapret-hosts-user.txt`  
Kaynak (workspace): `config/zapret-hosts-user.txt`

Düzenledikten sonra:

- menüden **Listeleri güncelle**, veya  
- `sudo /usr/local/bin/zapret-ctl update-lists`

---

## Terminal kısayolları

```bash
sudo zapret-ctl status
sudo zapret-ctl start
sudo zapret-ctl stop
sudo zapret-ctl update-lists
sudo zapret-ctl update-engine
sudo zapret-ctl rollback-engine
sudo zapret-ctl fix-dns
```
