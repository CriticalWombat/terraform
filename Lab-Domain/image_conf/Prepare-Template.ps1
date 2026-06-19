param(
    [Parameter(Mandatory=$true)]
    [string]$Password,

    [string]$WinRMScriptPath = "$PSScriptRoot\setup.ps1",

    # Auto-detected from OS type if not specified
    [string]$UnattendPath = "",

    # Skip the "press Enter to continue" confirmation prompt
    [switch]$Force,

    # Validate files and guest agent, then exit without making changes
    [switch]$Check
)

$ErrorActionPreference = "Stop"

function Write-Step { param([string]$m) Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Write-OK   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green  }
function Write-WARN { param([string]$m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-FAIL { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red    }

$os = Get-CimInstance Win32_OperatingSystem
Write-Host "`nPrepare-Template.ps1" -ForegroundColor White
Write-Host "OS: $($os.Caption)" -ForegroundColor White


# ============================================================
# PRE-FLIGHT
# ============================================================
Write-Step "Pre-flight checks"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-FAIL "Must be run as Administrator"
    exit 1
}
Write-OK "Running as Administrator"

# Password complexity: 8+ chars, 3 of 4 character classes
$hasUpper   = $Password -cmatch '[A-Z]'
$hasLower   = $Password -cmatch '[a-z]'
$hasDigit   = $Password -match '\d'
$hasSpecial = $Password -match '[^A-Za-z0-9]'
$complexity = ($hasUpper,$hasLower,$hasDigit,$hasSpecial | Where-Object { $_ }).Count
if ($Password.Length -lt 8 -or $complexity -lt 3) {
    Write-FAIL "Password does not meet Windows complexity requirements (8+ chars, 3 of: uppercase, lowercase, digit, special)"
    exit 1
}
Write-OK "Password meets complexity requirements"

# Auto-detect unattend if not specified
if ($UnattendPath -eq "") {
    $isServer   = $os.Caption -match "Server"
    $UnattendPath = if ($isServer) {
        "$PSScriptRoot\unattend-server.xml"
    } else {
        "$PSScriptRoot\unattend-win10.xml"
    }
    Write-OK "Detected OS type: $(if ($isServer) { 'Windows Server' } else { 'Windows 10' })"
}

if (-not (Test-Path $UnattendPath)) {
    Write-FAIL "Unattend file not found: $UnattendPath"
    exit 1
}
Write-OK "Unattend: $UnattendPath"

if (-not (Test-Path $WinRMScriptPath)) {
    Write-FAIL "setup.ps1 not found: $WinRMScriptPath"
    exit 1
}
Write-OK "setup.ps1: $WinRMScriptPath"

# Proxmox guest agent check — critical for Terraform IP discovery
$ga = Get-Service "QEMU-GA" -ErrorAction SilentlyContinue
if ($ga) {
    Write-OK "Proxmox guest agent (QEMU-GA) is installed"
} else {
    Write-WARN "Proxmox guest agent NOT found — Terraform cannot discover the VM IP without it."
    Write-WARN "Install qemu-ga-x86_64.msi from the VirtIO ISO before templating."
    Write-WARN "Continuing anyway — install it before converting to template."
}

# VirtIO NIC check (proxy for VirtIO drivers being installed)
$virtioNic = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "VirtIO|Red Hat" }
if ($virtioNic) {
    Write-OK "VirtIO network adapter detected"
} else {
    Write-WARN "No VirtIO NIC found. Install VirtIO drivers from the VirtIO ISO for best performance."
}

if ($Check) {
    Write-Host "`n-Check complete. Re-run without -Check to proceed with cleanup and sysprep." -ForegroundColor Cyan
    exit 0
}


# ============================================================
# CONFIRMATION
# ============================================================
Write-Host "`n  This will clean the VM and run sysprep. The VM will shut down." -ForegroundColor Yellow
Write-Host "  Password '$Password' will be embedded into the template." -ForegroundColor Yellow
Write-Host "  Use this same value for admin_password in terraform.tfvars.`n" -ForegroundColor Yellow

if (-not $Force) {
    Read-Host "  Press Enter to continue (Ctrl+C to abort)"
}


# ============================================================
# STEP 1: PRE-SYSPREP CLEANUP
# ============================================================
Write-Step "Step 1: Pre-sysprep cleanup"

$ErrorActionPreference = "SilentlyContinue"

# Reset sysprep generalization counter (allows re-sysprep)
$sysprepKey = "HKLM:\SYSTEM\Setup\Status\SysprepStatus"
if (Test-Path $sysprepKey) {
    Set-ItemProperty -Path $sysprepKey -Name "GeneralizationState"   -Value 7 -Force
    Set-ItemProperty -Path $sysprepKey -Name "CleanupState"          -Value 2 -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\Setup" -Name "SetupType"               -Value 4 -Force
    Set-ItemProperty -Path "HKLM:\SYSTEM\Setup" -Name "SystemSetupInProgress"   -Value 1 -Force
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" -Name "SkipRearm" -Value 1 -Force
Write-OK "Sysprep state reset"

& cscript //nologo C:\Windows\System32\slmgr.vbs /rearm
Write-OK "Activation rearmed"

# Clear Panther cache and stale unattend copies
@("C:\Windows\Panther", "C:\Windows\System32\Sysprep\Panther") | ForEach-Object {
    if (Test-Path $_) { Remove-Item "$_\*" -Recurse -Force }
}
@("C:\Windows\Panther\unattend.xml", "C:\Windows\unattend.xml", "C:\unattend.xml") | ForEach-Object {
    if (Test-Path $_) { Remove-Item $_ -Force }
}
Write-OK "Panther cache cleared"

# Windows Update cache
Stop-Service wuauserv, bits -Force
@("C:\Windows\SoftwareDistribution\Download", "C:\Windows\SoftwareDistribution\DeliveryOptimization") | ForEach-Object {
    if (Test-Path $_) { Remove-Item "$_\*" -Recurse -Force }
}
Start-Service wuauserv, bits
Write-OK "Windows Update cache cleared"

# Temp files
@($env:TEMP, $env:TMP, "C:\Windows\Temp", "C:\Windows\Prefetch") | ForEach-Object {
    if (Test-Path $_) { Remove-Item "$_\*" -Recurse -Force }
}
Write-OK "Temp files cleared"

# Non-default user profiles (never remove the currently active profile)
$currentSID = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Get-CimInstance Win32_UserProfile |
    Where-Object { -not $_.Special -and $_.SID -ne $currentSID -and $_.LocalPath -notmatch "Administrator|Default|Public|cloudbase-init|systemprofile|NetworkService|LocalService" } |
    ForEach-Object {
        try { Remove-CimInstance -InputObject $_; Write-OK "Removed profile: $($_.LocalPath)" }
        catch { Write-WARN "Could not remove profile: $($_.LocalPath)" }
    }

# Event logs
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.RecordCount -gt 0 } | ForEach-Object {
        try { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName) } catch { }
    }
Write-OK "Event logs cleared"

# WinRM listeners and certs (setup.ps1 re-creates them per-clone with the correct hostname)
# WSMan:\Localhost\Listener requires the service to be up to enumerate correctly
Set-Service WinRM -StartupType Manual -ErrorAction SilentlyContinue
Start-Service WinRM -ErrorAction SilentlyContinue
$winrmSvc = Get-Service WinRM -ErrorAction SilentlyContinue
if ($winrmSvc.Status -ne 'Running') {
    Start-Sleep -Seconds 10
    $winrmSvc.Refresh()
}
if ($winrmSvc.Status -eq 'Running') {
    Write-OK "WinRM service is running"
} else {
    Write-WARN "WinRM service could not be started - listener removal may be incomplete"
}
Get-ChildItem WSMan:\Localhost\Listener -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
$store.Open("ReadWrite")
@($store.Certificates) | ForEach-Object { try { $store.Remove($_) } catch { } }
$store.Close()
Write-OK "WinRM listeners and certs cleared"

# NIC history (prevents ghost adapters in clones)
$netKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}"
if (Test-Path $netKey) {
    Get-ChildItem $netKey | Where-Object { $_.PSChildName -ne "Descriptions" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
ipconfig /flushdns | Out-Null
Write-OK "NIC history and DNS cache cleared"

# Disk cleanup
$cleanupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
Get-ChildItem $cleanupKey | ForEach-Object { Set-ItemProperty -Path $_.PSPath -Name "StateFlags0001" -Value 2 -Type DWORD -Force }
Start-Process cleanmgr.exe -ArgumentList "/sagerun:1" -Wait -NoNewWindow
Write-OK "Disk cleanup complete"

$ErrorActionPreference = "Stop"


# ============================================================
# STEP 2: INJECT PASSWORD INTO UNATTEND AND STAGE setup.ps1
# ============================================================
Write-Step "Step 2: Staging files"

# Inject the provided password in place of the TEMPLATE_PASSWORD placeholder
$unattendContent = Get-Content $UnattendPath -Raw
if ($unattendContent -notmatch 'TEMPLATE_PASSWORD') {
    Write-FAIL "Unattend file does not contain the TEMPLATE_PASSWORD placeholder. Aborting."
    exit 1
}
$unattendContent = $unattendContent -replace 'TEMPLATE_PASSWORD', $Password

$sysprepDir     = "C:\Windows\System32\Sysprep"
$sysprepUnattend = "$sysprepDir\unattend.xml"
Set-Content -Path $sysprepUnattend -Value $unattendContent -Encoding UTF8
Write-OK "Unattend written to $sysprepUnattend (password injected)"

$scriptDest = "C:\Windows\Setup\Scripts"
if (-not (Test-Path $scriptDest)) { New-Item -ItemType Directory -Path $scriptDest -Force | Out-Null }
Copy-Item $WinRMScriptPath "$scriptDest\setup.ps1" -Force
Write-OK "setup.ps1 staged to $scriptDest\setup.ps1"


# ============================================================
# STEP 3: SYSPREP
# ============================================================
Write-Step "Step 3: Sysprep"

Write-Host "  Launching sysprep. The VM will shut down when complete." -ForegroundColor Yellow
Write-Host "  After shutdown: RIGHT-CLICK the VM in Proxmox -> Convert to Template." -ForegroundColor Yellow
Write-Host "  Do NOT boot the VM again before converting.`n" -ForegroundColor Red

Start-Sleep -Seconds 3

& C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:$sysprepUnattend
