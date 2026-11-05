<#
  Ratnam Store Billing - first install on the shop's main computer (store 1.25.0).
  Before: install SQL Server Express (SETUP-GUIDE.md, step 1). Run this in PowerShell opened as Administrator,
  in this folder (the full line is in SETUP-GUIDE.md, step 2).

  What it does, step by step (each step prints a line):
    1. checks SQL Server
    2. copies the program to C:\Program Files\RatnamStoreBilling
    3. writes the settings file (only the first time; later it is kept)
    4. adds the Windows service "Ratnam Store Billing" (runs with its own service account)
    5. lets that service account use the database (Windows login, no password)
    6. makes the backup folder C:\RatnamStore\backup
    7. opens the port for the other computers of the shop (private network only)
    8. starts the service and adds a desktop shortcut
  Safe to run again.
#>
param(
    [string]$ShopName = "My Shop",
    [string]$ProgramDir = (Join-Path $env:ProgramFiles "RatnamStoreBilling"),
    [string]$BackupDir = "C:\RatnamStore\backup",
    [int]$Port = 5000,
    [string]$SqlInstance = ".\SQLEXPRESS",
    [string]$Database = "StoreBilling",
    [string]$AdminPassword = "Admin@123",
    [string]$VendorName = "Ratnam Software",
    [string]$VendorPhone = ""
)
$ErrorActionPreference = "Stop"
$ServiceName = "RatnamStoreBilling"
$ServiceAccount = "NT SERVICE\$ServiceName"

function Say($text, $color = "White") { Write-Host $text -ForegroundColor $color }
function Stop-With($text) { Say ""; Say "STOP: $text" Red; exit 1 }

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-With "Open PowerShell with right-click -> 'Run as administrator', then run this again."
}
$package = Join-Path $PSScriptRoot "app"
if (-not (Test-Path (Join-Path $package "AccountingApi.exe"))) { Stop-With "The 'app' folder is not next to this script. Unzip the whole package first." }
$versionFile = Join-Path $PSScriptRoot "VERSION.txt"
$version = if (Test-Path $versionFile) { (Get-Content $versionFile).Trim() } else { "?" }
Say "Installing Ratnam Store Billing $version for '$ShopName'" Cyan

# ---- 1. SQL Server, reached as this Windows user (the user who installed SQL Server Express)
Add-Type -AssemblyName System.Data
function Invoke-Sql([string]$sql) {
    $con = New-Object System.Data.SqlClient.SqlConnection "Server=$SqlInstance;Database=master;Integrated Security=True;Connect Timeout=15"
    $con.Open()
    try {
        $cmd = $con.CreateCommand()
        $cmd.CommandText = $sql
        return $cmd.ExecuteScalar()
    } finally { $con.Close() }
}
try {
    $sqlVersion = Invoke-Sql "SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(50))"
    Say "1. SQL Server found: $SqlInstance (version $sqlVersion)" Green
} catch {
    Stop-With "SQL Server '$SqlInstance' could not be reached: $($_.Exception.Message)`n      Install SQL Server Express first (SETUP-GUIDE.md, step 1), or add -SqlInstance (e.g. -SqlInstance '.' for a full SQL Server)."
}
if ((Invoke-Sql "SELECT IS_SRVROLEMEMBER('sysadmin')") -ne 1) {
    Stop-With "This Windows user is not an administrator of SQL Server. Run this as the Windows user who installed SQL Server."
}

# ---- 2. the program files (an old copy is stopped first; its settings file is kept)
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -ne "Stopped") { Stop-Service -Name $ServiceName -Force; Start-Sleep -Seconds 3 }
$settingsFile = Join-Path $ProgramDir "appsettings.Production.json"
$keep = if (Test-Path $settingsFile) { Get-Content $settingsFile -Raw } else { $null }
New-Item -ItemType Directory -Force -Path $ProgramDir | Out-Null
robocopy $package $ProgramDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Stop-With "Copying the program to $ProgramDir did not work (robocopy code $LASTEXITCODE)." }
Say "2. Program copied to $ProgramDir" Green

# ---- 3. the settings file. No database password in it: the program logs in to SQL Server with its own
#         Windows service account (step 5).
if ($keep) {
    Set-Content -Path $settingsFile -Value $keep -Encoding UTF8
    Say "3. Settings file kept as it was" Green
} else {
    $jwtKey = [guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
    $settings = [ordered]@{
        ConnectionStrings = @{ DefaultConnection = "Server=$SqlInstance;Database=$Database;Integrated Security=True;TrustServerCertificate=True;" }
        Urls = "http://0.0.0.0:$Port"
        Jwt = @{ Key = $jwtKey; Issuer = "AccountingApi"; Audience = "AccountingApiClients"; ExpiryMinutes = 720 }
        Backup = @{ SqlFolder = $BackupDir; LocalFolder = $BackupDir }
        Seed = @{ CompanyName = $ShopName; AdminUserName = "admin"; AdminPassword = $AdminPassword }
        License = @{ VendorName = $VendorName; VendorPhone = $VendorPhone }
        Logging = @{ LogLevel = @{ Default = "Information"; "Microsoft.AspNetCore" = "Warning"; "Microsoft.EntityFrameworkCore" = "Warning" } }
    }
    $settings | ConvertTo-Json -Depth 5 | Set-Content -Path $settingsFile -Encoding UTF8
    Say "3. Settings file made: $settingsFile" Green
}

# ---- 4. the Windows service: starts with Windows, starts again after a crash, runs with its own account
$exe = Join-Path $ProgramDir "AccountingApi.exe"
if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
    New-Service -Name $ServiceName -BinaryPathName "`"$exe`"" -DisplayName "Ratnam Store Billing" -StartupType Automatic `
        -Description "Ratnam Store Billing - billing, stock and accounts for the shop. Open http://localhost:$Port in the browser." | Out-Null
}
sc.exe config $ServiceName obj= $ServiceAccount start= delayed-auto | Out-Null
sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
# The program writes its errors to Windows Event Viewer (Application, source "AccountingApi")
if (-not [System.Diagnostics.EventLog]::SourceExists("AccountingApi")) {
    [System.Diagnostics.EventLog]::CreateEventSource("AccountingApi", "Application")
}
Say "4. Service '$ServiceName' ready (account $ServiceAccount)" Green

# ---- 5. the service account may use SQL Server. It makes the database at the first start and takes
#         backups and restores, so it is a SQL Server administrator. It is used only by this program.
$login = $ServiceAccount.Replace("]", "]]")
if ((Invoke-Sql "SELECT COUNT(*) FROM sys.server_principals WHERE name = N'$($ServiceAccount.Replace("'", "''"))'") -eq 0) {
    Invoke-Sql "CREATE LOGIN [$login] FROM WINDOWS" | Out-Null
}
Invoke-Sql "ALTER SERVER ROLE [sysadmin] ADD MEMBER [$login]" | Out-Null
Say "5. SQL Server login for $ServiceAccount ready" Green

# ---- 6. the backup folder: SQL Server writes the backups there, the program reads, copies and deletes old ones
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$sqlAccount = if ($SqlInstance -match '\\(.+)$') { "NT SERVICE\MSSQL`$" + $Matches[1] } else { "NT SERVICE\MSSQLSERVER" }
foreach ($account in @($sqlAccount, $ServiceAccount)) {
    try {
        $acl = Get-Acl $BackupDir
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($account, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")))
        Set-Acl -Path $BackupDir -AclObject $acl
    } catch {
        Say "   Could not give '$account' the backup folder: $($_.Exception.Message). Backups may fail; see SETUP-GUIDE.md -> Problems." Yellow
    }
}
Say "6. Backup folder: $BackupDir" Green

# ---- 7. the other computers of the shop open it through the network (private networks only)
if (-not (Get-NetFirewallRule -DisplayName "Ratnam Store Billing" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Ratnam Store Billing" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private, Domain | Out-Null
}
Say "7. Port $Port open for the shop's network" Green

# ---- 8. start, wait until it answers (the first start makes the database: up to a minute or two)
Start-Service -Name $ServiceName
$url = "http://localhost:$Port"
$ok = $false
for ($i = 0; $i -lt 90 -and -not $ok; $i++) {
    try { $ok = (Invoke-RestMethod "$url/api/system/ping" -TimeoutSec 3).ok -eq $true } catch { }
    if (-not $ok) { Start-Sleep -Seconds 2 }
}
if (-not $ok) { Stop-With "The program did not answer at $url. See Event Viewer -> Windows Logs -> Application (source: AccountingApi), and SETUP-GUIDE.md -> Problems." }
$desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
Set-Content -Path (Join-Path $desktop "Store Billing.url") -Value "[InternetShortcut]`r`nURL=$url/`r`n" -Encoding ASCII
Say "8. Started; shortcut 'Store Billing' on the desktop" Green

$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -ExpandProperty IPAddress
Say ""
Say "Ratnam Store Billing $version is installed." Green
Say "  On this computer:  $url"
foreach ($ip in $ips) { Say "  Other computers:   http://${ip}:$Port" }
Say "  First login:       admin / $AdminPassword   -> change the password at once (top right -> Change password)"
Say "  Data:              database '$Database' on $SqlInstance; backups in $BackupDir (every day at 21:00)"
Say "  Free trial 30 days. For the licence key: Settings -> Licence -> Copy licence request, and send it to $VendorName $VendorPhone."
