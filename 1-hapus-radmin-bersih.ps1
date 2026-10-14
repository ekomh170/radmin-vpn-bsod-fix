#Requires -RunAsAdministrator
# LANGKAH 1: Hapus Radmin VPN 2.1.4951.1 secara bersih.
# Identitas Radmin (IP 26.x, alias, network) di-backup dulu dan TIDAK dihapus.
# Setelah selesai: RESTART laptop, lalu jalankan 2-pasang-radmin-2.0.ps1

$ErrorActionPreference = 'Continue'
$base    = Split-Path -Parent $MyInvocation.MyCommand.Path
$backup  = Join-Path $base 'backup-radmin'
$hklmReg = Join-Path $backup 'RadminVPN-HKLM.reg'
$hkcuReg = Join-Path $backup 'RadminVPN-HKCU.reg'
$cfgKey  = 'HKLM:\SOFTWARE\WOW6432Node\Famatech\RadminVPN\1.0'
$product = '{5560C73C-AE48-49C9-842C-8341D592F231}'

New-Item -ItemType Directory -Force $backup | Out-Null
Start-Transcript -Path (Join-Path $base 'log-1-hapus-radmin.txt') -Force | Out-Null

function Step($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }

Step '1. Backup identitas Radmin'
reg export 'HKLM\SOFTWARE\WOW6432Node\Famatech\RadminVPN' $hklmReg /y | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $hklmReg)) {
    Write-Host 'Backup identitas GAGAL. Proses dihentikan, tidak ada yang dihapus.' -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}
reg export 'HKCU\SOFTWARE\Famatech\Radmin VPN' $hkcuReg /y | Out-Null
$rid = (Get-ItemProperty $cfgKey -ErrorAction SilentlyContinue).RID
$alias = (Get-ItemProperty $cfgKey -ErrorAction SilentlyContinue).Alias
Set-Content -Path (Join-Path $backup 'identitas.txt') -Value "RID=$rid`r`nAlias=$alias" -Encoding ASCII
Write-Host "OK  -> $hklmReg  (RID=$rid, Alias=$alias)"

Step '2. Hentikan aplikasi dan service Radmin'
Get-Process RvRvpnGui, RvGuiStarter, RvFwHelper -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-Service RvControlSvc -Force -ErrorAction SilentlyContinue
Write-Host 'OK'

Step '3. Uninstall Radmin VPN 2.1 (MSI)'
$msiLog = Join-Path $backup 'msi-uninstall.log'
$p = Start-Process msiexec.exe -ArgumentList "/x $product /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru
Write-Host "msiexec exit code: $($p.ExitCode)  (0 / 3010 = sukses, 1605 = sudah tidak terpasang)"

Step '4. Hapus adapter jaringan Radmin yang tersisa'
Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Radmin' -or $_.Manufacturer -match 'Famatech' } |
    ForEach-Object { Write-Host "remove-device $($_.InstanceId)"; pnputil /remove-device $_.InstanceId }

Step '5. Hapus paket driver Famatech dari Driver Store'
Get-WindowsDriver -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'Famatech' } |
    ForEach-Object { Write-Host "delete-driver $($_.Driver) ($($_.OriginalFileName))"; pnputil /delete-driver $_.Driver /uninstall /force }

Step '6. Hapus service yang tersisa'
foreach ($s in 'RvControlSvc', 'RvNetMP60') {
    if (Get-Service $s -ErrorAction SilentlyContinue) {
        sc.exe stop $s | Out-Null
        sc.exe delete $s
    }
}
$sys = "$env:windir\System32\drivers\RvNetMP60.sys"
if (Test-Path $sys) { Remove-Item $sys -Force -ErrorAction SilentlyContinue }
if (Test-Path $sys) { Write-Host 'RvNetMP60.sys masih terkunci, akan dibersihkan di langkah 2 setelah restart.' -ForegroundColor Yellow }

Step '7. Hapus firewall rule Radmin'
Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue |
    Where-Object { $_.Program -match 'Radmin VPN' } |
    Get-NetFirewallRule -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "hapus rule: $($_.DisplayName)"; $_ | Remove-NetFirewallRule }

Step '8. Hapus folder program dan log'
'C:\Program Files (x86)\Radmin VPN',
'C:\ProgramData\Famatech\Radmin VPN',
"$env:LOCALAPPDATA\Famatech\Radmin VPN" | ForEach-Object {
    if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "hapus: $_" }
}

Step '9. Reset status auto-update (identitas tetap disimpan)'
if (Test-Path $cfgKey) {
    Remove-Item "$cfgKey\update" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Identitas masih ada di registry, subkey update dihapus.'
} else {
    Write-Host 'Identitas ikut terhapus oleh uninstaller, akan dikembalikan dari backup di langkah 2.' -ForegroundColor Yellow
}

Step 'HASIL PEMERIKSAAN'
$left = @()
if (Get-WindowsDriver -Online -ErrorAction SilentlyContinue | Where-Object ProviderName -match 'Famatech') { $left += 'paket driver Famatech' }
if (Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object FriendlyName -match 'Radmin') { $left += 'adapter Radmin' }
if (Get-Service RvControlSvc, RvNetMP60 -ErrorAction SilentlyContinue) { $left += 'service Radmin' }
if (Test-Path 'C:\Program Files (x86)\Radmin VPN') { $left += 'folder program' }
if (Test-Path $sys) { $left += 'file RvNetMP60.sys' }
if ($left.Count -eq 0) { Write-Host 'BERSIH: tidak ada sisa Radmin.' -ForegroundColor Green }
else { Write-Host ("Masih tersisa: " + ($left -join ', ') + "  (biasanya hilang setelah restart)") -ForegroundColor Yellow }

Write-Host "`nSilakan RESTART laptop, lalu jalankan 2-pasang-radmin-2.0.ps1" -ForegroundColor Green
Stop-Transcript | Out-Null
