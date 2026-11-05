<#
  Puts a new version of Ratnam Store Billing over the old one (store 1.25.0). The data and the settings stay.
  In the folder of the NEW package, in PowerShell opened "as Administrator":

      powershell -ExecutionPolicy Bypass -File .\update.ps1

  It: makes a backup of the database first, stops the program, copies the new files (keeps appsettings.Production.json),
  starts it again. The database is brought up to the new version by the program itself when it starts.
#>
param(
    [string]$InstallDir = "C:\RatnamStore"
)
$ErrorActionPreference = "Stop"
$ServiceName = "RatnamStoreBilling"
function Say($text, $color = "White") { Write-Host $text -ForegroundColor $color }
function Stop-With($text) { Say ""; Say "STOP: $text" Red; exit 1 }

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Stop-With "Open PowerShell with right-click -> 'Run as administrator'." }

$package = Join-Path $PSScriptRoot "app"
$appDir = Join-Path $InstallDir "app"
$settingsFile = Join-Path $appDir "appsettings.Production.json"
if (-not (Test-Path (Join-Path $package "AccountingApi.exe"))) { Stop-With "The 'app' folder is not next to this script. Unzip the whole new package first." }
if (-not (Test-Path $settingsFile)) { Stop-With "No installation found in $InstallDir (appsettings.Production.json is missing). Use install.ps1 for a first install." }
$version = if (Test-Path (Join-Path $PSScriptRoot "VERSION.txt")) { (Get-Content (Join-Path $PSScriptRoot "VERSION.txt")).Trim() } else { "?" }
$settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
$cs = $settings.ConnectionStrings.DefaultConnection
$port = if ($settings.Urls -match ':(\d+)\s*$') { $Matches[1] } else { "5000" }
try { $old = (Invoke-RestMethod "http://localhost:$port/api/system/ping" -TimeoutSec 5).version } catch { $old = "(not running)" }
Say "Updating Ratnam Store Billing $old -> $version" Cyan

# ---- 1. a backup of the whole database before anything changes
Add-Type -AssemblyName System.Data
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $cs
$db = $builder.InitialCatalog
$builder.InitialCatalog = "master"
$folder = $settings.Backup.SqlFolder
if (-not $folder) { Stop-With "Backup:SqlFolder is empty in $settingsFile." }
$file = Join-Path $folder ("{0}_before-update_{1}.bak" -f $db, (Get-Date -Format "yyyyMMdd_HHmmss"))
$con = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
try {
    $con.Open()
    $cmd = $con.CreateCommand()
    $cmd.CommandTimeout = 0
    $cmd.CommandText = "BACKUP DATABASE [" + $db.Replace("]", "]]") + "] TO DISK = @f WITH COPY_ONLY, INIT, CHECKSUM"
    [void]$cmd.Parameters.AddWithValue("@f", $file)
    [void]$cmd.ExecuteNonQuery()
} catch {
    Stop-With "The backup before the update did not work: $($_.Exception.Message). Nothing was changed."
} finally { $con.Close() }
Say "  Backup made: $file" Green

# ---- 2. stop, copy, start
Stop-Service -Name $ServiceName -Force
for ($i = 0; $i -lt 30 -and (Get-Process -Name "AccountingApi" -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
$keep = Get-Content $settingsFile -Raw
robocopy $package $appDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
$code = $LASTEXITCODE
Set-Content -Path $settingsFile -Value $keep -Encoding UTF8
icacls $settingsFile /inheritance:r /grant:r "Administrators:F" "SYSTEM:F" | Out-Null
if ($code -ge 8) {
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    Stop-With "Copying the new files did not work (robocopy code $code). Try again; the backup is $file."
}
Start-Service -Name $ServiceName

# ---- 3. it answers with the new version (the database update runs at the first start)
$now = $null
for ($i = 0; $i -lt 90; $i++) {
    try { $now = (Invoke-RestMethod "http://localhost:$port/api/system/ping" -TimeoutSec 3).version; if ($now) { break } } catch { }
    Start-Sleep -Seconds 2
}
if (-not $now) { Stop-With "The program did not start again. See Event Viewer -> Windows Logs -> Application (source: AccountingApi). The backup before the update is $file." }
Say ""
Say "Updated to $now. The data is kept; the backup made before the update is $file." Green
Say "On every computer, press Ctrl+F5 once in the browser to load the new screens."
