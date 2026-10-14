#Requires -RunAsAdministrator
# LANGKAH 2 (setelah restart): pasang Radmin VPN 2.0.4899.9, blokir auto-update,
# dan pastikan identitas lama (IP 26.x, alias, network) kembali.
# CATATAN: blokir hosts di langkah 2 terbukti TIDAK mencegah auto-update
# (Radmin tetap naik ke 2.1 sehari kemudian). Lihat README bagian "Status".

$ErrorActionPreference = 'Continue'
$base     = Split-Path -Parent $MyInvocation.MyCommand.Path
$backup   = Join-Path $base 'backup-radmin'
$hklmReg  = Join-Path $backup 'RadminVPN-HKLM.reg'
$exe      = Join-Path $base 'installer-radmin-2.0\Radmin_VPN_2.0.4899.9.exe'
$exeHash  = '87C1BE4F631796C635797B789CC82064AC7BBFCE34CDBE1E0003178BF93E81E2'
$cfgKey   = 'HKLM:\SOFTWARE\WOW6432Node\Famatech\RadminVPN\1.0'
$hosts    = "$env:windir\System32\drivers\etc\hosts"
$marker   = '# Radmin VPN: blokir auto-update (hapus 4 baris ini untuk mengizinkan update)'

Start-Transcript -Path (Join-Path $base 'log-2-pasang-radmin.txt') -Force | Out-Null
function Step($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }
function Restore-Identity {
    reg import $hklmReg 2>&1 | Out-Null
    Remove-Item "$cfgKey\update" -Recurse -Force -ErrorAction SilentlyContinue
}

$oldRid = $null
$idFile = Join-Path $backup 'identitas.txt'
if (Test-Path $idFile) { $oldRid = ((Get-Content $idFile) -match '^RID=') -replace '^RID=', '' }
if (-not (Test-Path $hklmReg) -or -not $oldRid) {
    Write-Host 'Backup identitas tidak ditemukan. Jalankan langkah 1 dulu.' -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}

Step '1. Pastikan sisa driver lama sudah hilang'
Get-WindowsDriver -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'Famatech' } |
    ForEach-Object { Write-Host "delete-driver $($_.Driver)"; pnputil /delete-driver $_.Driver /uninstall /force }
$sys = "$env:windir\System32\drivers\RvNetMP60.sys"
if (Test-Path $sys) { Remove-Item $sys -Force -ErrorAction SilentlyContinue }
Write-Host ('RvNetMP60.sys lama: ' + $(if (Test-Path $sys) { 'MASIH ADA' } else { 'sudah hilang' }))

Step '2. Blokir auto-update Radmin lewat file hosts'
if (-not (Select-String -Path $hosts -SimpleMatch $marker -Quiet)) {
    Add-Content -Path $hosts -Encoding ASCII -Value "`r`n$marker`r`n0.0.0.0 radmin-vpn.com`r`n0.0.0.0 www.radmin-vpn.com`r`n0.0.0.0 download.radmin-vpn.com"
    ipconfig /flushdns | Out-Null
    Write-Host 'OK: radmin-vpn.com diblokir (koneksi VPN pakai radminte.com, tidak terpengaruh).'
} else { Write-Host 'Sudah diblokir sebelumnya.' }

Step '3. Kembalikan identitas sebelum install'
if (-not (Test-Path $cfgKey)) { Restore-Identity; Write-Host 'Identitas dipulihkan dari backup.' }
else { Remove-Item "$cfgKey\update" -Recurse -Force -ErrorAction SilentlyContinue; Write-Host 'Identitas masih ada.' }

Step '4. Verifikasi installer'
$sig = Get-AuthenticodeSignature $exe
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Famatech' -or $hash -ne $exeHash) {
    Write-Host "Installer tidak valid (signature=$($sig.Status), hash cocok=$($hash -eq $exeHash)). Dihentikan." -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}
Write-Host "OK: ditandatangani Famatech Corp., hash cocok."

Step '5. Install Radmin VPN 2.0.4899.9'
$p = Start-Process $exe -ArgumentList '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
Write-Host "Installer exit code: $($p.ExitCode)"
Start-Sleep -Seconds 10

Step '6. Cek identitas setelah install'
$nowRid = (Get-ItemProperty $cfgKey -ErrorAction SilentlyContinue).RID
if ("$nowRid" -ne "$oldRid") {
    Write-Host "RID berubah ($nowRid), mengembalikan identitas lama ($oldRid)..." -ForegroundColor Yellow
    Stop-Service RvControlSvc -Force -ErrorAction SilentlyContinue
    Restore-Identity
    Start-Service RvControlSvc -ErrorAction SilentlyContinue
    $nowRid = (Get-ItemProperty $cfgKey -ErrorAction SilentlyContinue).RID
}

Step 'HASIL'
$app = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object DisplayName -match 'Radmin VPN' | Select-Object -First 1
$drv = Get-Item $sys -ErrorAction SilentlyContinue
$svc = Get-Service RvControlSvc -ErrorAction SilentlyContinue
$cfg = Get-ItemProperty $cfgKey -ErrorAction SilentlyContinue
Write-Host "Versi aplikasi : $($app.DisplayVersion)"
Write-Host "Versi driver   : $($drv.VersionInfo.FileVersion)"
Write-Host "Service        : $($svc.Status)"
Write-Host "Alias / RID    : $($cfg.Alias) / $nowRid  (lama: $oldRid)"
if ($app.DisplayVersion -eq '2.0.4899.9' -and "$nowRid" -eq "$oldRid" -and $svc.Status -eq 'Running') {
    Write-Host "`nSELESAI: Radmin VPN 2.0 terpasang dengan identitas lama." -ForegroundColor Green
} else {
    Write-Host "`nAda yang belum sesuai, kirim isi log-2-pasang-radmin.txt untuk dicek." -ForegroundColor Yellow
}
Stop-Transcript | Out-Null
