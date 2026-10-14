# radmin-vpn-bsod-fix

Catatan analisa dan perbaikan BSOD **`0x139 KERNEL_SECURITY_CHECK_FAILURE`** di laptop Windows 10 (build 19045) yang dipicu driver **Radmin VPN** (`RvNetMP60.sys`), beserta dua script PowerShell untuk menghapus Radmin VPN 2.1 secara bersih lalu memasang ulang versi 2.0 **tanpa kehilangan identitas** (IP 26.x, alias, daftar network).

> Semua data pribadi (username, nama PC, RID, alias, nama network, IP) sudah disamarkan. File crash dump, backup registry, dan installer **tidak** disertakan. Lihat [Privasi](#privasi).

## Gejala

- 6x BSOD dengan kode yang sama dalam 10 hari: 2x tanggal 29 Sep 2026, 1x 8 Okt, 3x 9 Okt.
- Semuanya `0x139` dengan **parameter 1 = `3`**: sebuah `LIST_ENTRY` (daftar berantai di kernel) ditemukan rusak, lalu Windows sengaja menghentikan sistem (_fail-fast_).
- Parameter 2 dan 3 di keenam crash selalu berakhiran **`...410`** dan **`...368`**. Artinya crash selalu lewat jalur kode yang sama, bukan kerusakan acak.
- Sebagian besar file dump terhapus otomatis karena sisa ruang C: di bawah 25 GB.

## Hasil analisa minidump

Satu minidump yang tersisa (crash 9 Okt 2026) dibaca langsung tanpa WinDbg:

| Data         | Isi                                                                                                   |
| ------------ | ----------------------------------------------------------------------------------------------------- |
| Bugcheck     | `0x139` KERNEL_SECURITY_CHECK_FAILURE, parameter 1 = `3`                                              |
| Titik crash  | **`RvNetMP60.sys+0x2572`**, driver _Radmin VPN Virtual Adapter_ (Famatech), versi driver `1.1.3529.0` |
| Proses aktif | `RvControlSvc.exe`, service Radmin VPN                                                                |
| Alur         | `RvControlSvc` mengirim paket → tcpip / NDIS → `RvNetMP60.sys` → driver menemukan list rusak → BSOD   |

Tersangka lain yang sempat dicek dan prioritasnya turun: RAM dari dua merek berbeda, driver Wi-Fi Realtek versi lama, dan beberapa driver VPN/filter jaringan pihak ketiga lain. BSOD `0x116 VIDEO_TDR_FAILURE` (GPU NVIDIA) di pertengahan September adalah masalah terpisah dan tidak dibahas di sini.

## Timeline

| Tanggal        | Kejadian                                                                                         |
| -------------- | ------------------------------------------------------------------------------------------------ |
| Mei 2026       | Radmin VPN 2.0 terpasang, berjalan sekitar 5 bulan tanpa BSOD 0x139                              |
| 24 Sep 2026    | Radmin **meng-update dirinya sendiri** ke 2.1.4951.1 tanpa konfirmasi                            |
| 29 Sep – 9 Okt | 6x BSOD 0x139                                                                                    |
| 9 Okt          | Minidump dianalisa. Script 1 dan 2 dijalankan, Radmin 2.0.4899.9 terpasang, identitas tetap sama |
| 10 Okt 05:21   | Radmin **auto-update lagi** ke 2.1.4951.1, walaupun domain update sudah diblokir di file hosts   |
| s.d. 14 Okt    | Belum ada BSOD baru (dicek dari event log)                                                       |

## Kenapa downgrade, bukan langsung ganti VPN

File driver `RvNetMP60.sys` di versi 2.0 dan 2.1 sama (`1.1.3529.0`). Yang berubah hanya aplikasi dan service-nya. Karena versi 2.0 berjalan 5 bulan tanpa masalah, dugaan awalnya adalah service 2.1 memakai driver dengan cara yang memicu bug. Downgrade dipilih supaya Radmin tetap bisa dipakai dengan identitas yang sama.

## Status

**Belum tuntas.** Dua hal yang perlu diketahui:

1. **Blokir auto-update lewat file hosts tidak berhasil.** URL update tidak tertanam di aplikasi. Kemungkinan besar perintah dan alamat unduhan dikirim server lewat koneksi kontrol `radminte.com`, yang juga dipakai untuk koneksi VPN, sehingga tidak bisa diblokir tanpa mematikan VPN. Radmin tidak punya opsi resmi untuk mematikan auto-update.
2. **Sudah 4 hari berjalan di versi 2.1 lagi tanpa BSOD.** Ini melemahkan dugaan bahwa service 2.1 adalah pemicunya. Kemungkinan lain: pembersihan total (adapter, paket driver lama di Driver Store, service, sisa file) yang memperbaiki kondisi driver. Atau memang belum cukup lama, karena sebelumnya juga ada jeda 9 hari tanpa crash (29 Sep → 8 Okt).

Rekomendasi: pantau minimal 2 minggu. Kalau BSOD 0x139 muncul lagi, ganti Radmin VPN dengan VPN lain (misalnya Tailscale atau ZeroTier). Mode _Small memory dump_ sudah aktif, jadi crash berikutnya pasti meninggalkan file dump untuk dianalisa.

## Isi repo

```
radmin-vpn-bsod-fix/
├── 1-hapus-radmin-bersih.ps1    langkah 1: backup identitas + hapus bersih Radmin 2.1
├── 2-pasang-radmin-2.0.ps1      langkah 2: pasang Radmin 2.0 + pulihkan identitas
├── installer-radmin-2.0/        taruh installer resmi di sini (tidak ikut di-commit)
└── contoh-log/                  log hasil eksekusi asli, sudah disamarkan
```

## Cara pakai

**Prasyarat:** Windows 10/11 dan PowerShell yang dibuka **as Administrator**.

1. Unduh installer resmi `Radmin_VPN_2.0.4899.9.exe` dari `https://download.radmin-vpn.com/download/files/Radmin_VPN_2.0.4899.9.exe`, lalu taruh di folder `installer-radmin-2.0/`. Script 2 akan menolak installer yang tanda tangan digitalnya bukan Famatech atau hash SHA-256-nya tidak cocok.
2. Jalankan langkah 1:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\1-hapus-radmin-bersih.ps1
   ```
3. **Restart** laptop.
4. Jalankan langkah 2:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\2-pasang-radmin-2.0.ps1
   ```
5. Cek `log-1-hapus-radmin.txt` dan `log-2-pasang-radmin.txt` yang dibuat di folder repo. Contoh hasil yang benar ada di [contoh-log/](contoh-log/).

Radmin VPN putus dari langkah 1 sampai langkah 2 selesai, jadi jangan dijalankan saat koneksi sedang dibutuhkan.

### Yang dilakukan script 1

1. Export registry Radmin (identitas + network) ke `backup-radmin/`. **Kalau backup gagal, script berhenti tanpa menghapus apa pun.**
2. Menghentikan aplikasi dan service Radmin.
3. Uninstall MSI Radmin 2.1.4951.1.
4. Menghapus adapter jaringan Radmin yang tersisa.
5. Menghapus paket driver Famatech dari Driver Store.
6. Menghapus service `RvControlSvc` / `RvNetMP60` dan file `RvNetMP60.sys`.
7. Menghapus firewall rule Radmin.
8. Menghapus folder program, data, dan log Radmin.
9. Menghapus status auto-update di registry (identitas tetap disimpan).

Product code MSI di script (`{5560C73C-...}`) khusus untuk versi 2.1.4951.1. Untuk versi lain, cari product code-nya di `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\`.

### Yang dilakukan script 2

1. Memastikan tidak ada sisa driver lama.
2. Menambahkan blokir `radmin-vpn.com` ke file hosts (**terbukti tidak mencegah auto-update**, lihat [Status](#status)).
3. Memulihkan identitas dari backup kalau ikut terhapus.
4. Memverifikasi tanda tangan digital dan hash installer.
5. Memasang Radmin VPN 2.0.4899.9 secara silent.
6. Membandingkan RID sebelum dan sesudah. Kalau berubah, identitas lama dipulihkan otomatis.

Untuk membuka blokir hosts, hapus 4 baris berlabel `# Radmin VPN: blokir auto-update` di `C:\Windows\System32\drivers\etc\hosts`.

## Supaya BSOD berikutnya bisa dianalisa

Jalankan di PowerShell Administrator:

```powershell
# Simpan minidump kecil yang tidak ikut terhapus walau disk hampir penuh
reg add HKLM\SYSTEM\CurrentControlSet\Control\CrashControl /v CrashDumpEnabled /t REG_DWORD /d 3 /f

# Daftar BSOD dari event log
Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001} |
    Where-Object ProviderName -match 'WER-SystemErrorReporting' |
    Select-Object TimeCreated, Message

# Salin minidump untuk dianalisa
Copy-Item C:\Windows\Minidump\*.dmp "$env:USERPROFILE\Desktop\" -Force
```

Usahakan sisa ruang C: di atas 25 GB. Di bawah itu, Windows menghapus `MEMORY.DMP` secara otomatis.

## Privasi

Sengaja **tidak** disertakan di repo ini:

| File                                | Alasan                                                                           |
| ----------------------------------- | -------------------------------------------------------------------------------- |
| `*.dmp` (crash dump)                | Berisi potongan isi memori sistem                                                |
| `backup-radmin/`                    | Registry Radmin: RID, alias, daftar network, dan data koneksinya. Anggap rahasia |
| `installer-radmin-2.0/*.exe`        | Software pihak ketiga, unduh dari situs resmi                                    |
| Log MSI, driver, dan service Radmin | Berisi path user, hardware ID, nama network, dan nama perangkat lain             |

Log di `contoh-log/` sudah disamarkan: `<USER>`, `<PC-NAME>`, `<RID>`, `<ALIAS>`. File `.gitignore` mencegah backup, dump, installer, dan log hasil eksekusi baru ikut ter-commit.
