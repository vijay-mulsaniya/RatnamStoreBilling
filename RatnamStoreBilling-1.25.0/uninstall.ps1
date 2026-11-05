<#
  Removes Ratnam Store Billing from this computer (store 1.25.0): the service, the firewall opening and the shortcuts.
  The DATA STAYS: the database in SQL Server and the backups in C:\RatnamStore\backup. Install again to use it again.
  PowerShell "as Administrator":   powershell -ExecutionPolicy Bypass -File .\uninstall.ps1  [-RemoveProgramFiles]
#>
param(
    [string]$InstallDir = "C:\RatnamStore",
    # Also delete the program folder (the settings file with it). The backup folder is never deleted.
    [switch]$RemoveProgramFiles
)
$ErrorActionPreference = "Stop"
$ServiceName = "RatnamStoreBilling"
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Host "Open PowerShell 'as administrator'." -ForegroundColor Red; exit 1 }

if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName | Out-Null
    Write-Host "Service removed."
}
Get-NetFirewallRule -DisplayName "Ratnam Store Billing" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
$desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
Remove-Item (Join-Path $desktop "Store Billing.url"), (Join-Path $desktop "Store Billing (quick print).lnk") -ErrorAction SilentlyContinue
if ($RemoveProgramFiles) {
    Remove-Item (Join-Path $InstallDir "app") -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Program files removed."
}
Write-Host "Done. The database and the backups in $InstallDir\backup are kept." -ForegroundColor Green
