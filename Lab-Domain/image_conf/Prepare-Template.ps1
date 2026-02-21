param(
    [string]$UnattendPath   = "$PSScriptRoot\unattend.xml",
    [string]$WinRMScriptPath = "$PSScriptRoot\setup.ps1",
    [switch]$SkipSysprep
)

$ErrorActionPreference = "Stop"
$VerbosePreference     = "Continue"

function Write-Step {
    param([string]$Message)
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-OK   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green  }
function Write-SKIP { param([string]$m) Write-Host "  [SKIP] $m" -ForegroundColor Yellow }
function Write-FAIL { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red    }

Write-Host "`n  Windows 10 Template Preparation Script" -ForegroundColor White
Write-Host "  OS: $((Get-CimInstance Win32_OperatingSystem).Caption)" -ForegroundColor White


# ============================================================
# PRE-FLIGHT CHECKS
# ============================================================

Write-Step "Pre-flight checks"

# Confirm this is Windows 10 (not Server)
$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
if ($osCaption -notmatch "Windows 10") {
    Write-Warning "This script targets Windows 10. Detected: $osCaption. Continuing anyway..."
}

# Confirm running as Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-FAIL "Script must be run as Administrator"
    exit 1
}
Write-OK "Running as Administrator"

if (-not $SkipSysprep) {
    # Confirm unattend exists before doing anything destructive
    if (-not (Test-Path $UnattendPath)) {
        Write-FAIL "unattend.xml not found at: $UnattendPath"
        Write-Host "  Place your unattend.xml next to this script or pass -UnattendPath" -ForegroundColor Red
        exit 1
    }
    Write-OK "unattend.xml found at: $UnattendPath"

    # Confirm setup.ps1 exists - it must be staged into the image
    if (-not (Test-Path $WinRMScriptPath)) {
        Write-FAIL "setup.ps1 not found at: $WinRMScriptPath"
        Write-Host "  Place setup.ps1 next to this script or pass -WinRMScriptPath" -ForegroundColor Red
        exit 1
    }
    Write-OK "setup.ps1 found at: $WinRMScriptPath"
}

if ($SkipSysprep) {
    Write-Host "`n  -SkipSysprep specified. Stopping here." -ForegroundColor Cyan
    Write-Host "  Re-run without -SkipSysprep when ready to proceed." -ForegroundColor Cyan
    exit 0
}

Read-Host "`n  Press Enter to continue with cleanup and sysprep (Ctrl+C to abort)"


# ============================================================
# STEP 1: PRE-SYSPREP CLEANUP
# ============================================================

Write-Step "Step 1: Pre-sysprep cleanup"

$ErrorActionPreference = "SilentlyContinue"

# 1a. Reset sysprep generalization count
#     Windows blocks sysprep after 3 runs - this resets the counter
Write-Verbose "Resetting sysprep state..."
$sysprepKey = "HKLM:\SYSTEM\Setup\Status\SysprepStatus"
$setupKey   = "HKLM:\SYSTEM\Setup"
if (Test-Path $sysprepKey) {
    Set-ItemProperty -Path $sysprepKey -Name "GeneralizationState"      -Value 7 -Force
    Set-ItemProperty -Path $sysprepKey -Name "CleanupState"             -Value 2 -Force
    Set-ItemProperty -Path $setupKey   -Name "SetupType"                -Value 4 -Force
    Set-ItemProperty -Path $setupKey   -Name "SystemSetupInProgress"    -Value 1 -Force
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" `
    -Name "SkipRearm" -Value 1 -Force
Write-OK "Sysprep state reset"

# 1b. Rearm Windows activation
Write-Verbose "Rearming activation..."
& cscript //nologo C:\Windows\System32\slmgr.vbs /rearm
Write-OK "Activation rearmed"

# 1c. Clear Panther cache - Windows caches the unattend here and uses
Write-Verbose "Clearing Panther cache..."
@(
    "C:\Windows\Panther",
    "C:\Windows\System32\Sysprep\Panther"
) | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item "$_\*" -Recurse -Force
        Write-Verbose "  Cleared: $_"
    }
}

# Remove any stale unattend copies from locations Windows searches
@(
    "C:\Windows\Panther\unattend.xml",
    "C:\Windows\unattend.xml",
    "C:\unattend.xml"
) | ForEach-Object {
    if (Test-Path $_) { Remove-Item $_ -Force }
}
Write-OK "Panther cache cleared (all subdirectories and files)"

# 1d. Clear Windows Update cache
Write-Verbose "Clearing Windows Update cache..."
Stop-Service wuauserv, bits -Force
@(
    "C:\Windows\SoftwareDistribution\Download",
    "C:\Windows\SoftwareDistribution\DeliveryOptimization"
) | ForEach-Object {
    if (Test-Path $_) { Remove-Item "$_\*" -Recurse -Force }
}
Start-Service wuauserv, bits
Write-OK "Windows Update cache cleared"

# 1e. Clear temp files
Write-Verbose "Clearing temp files..."
@($env:TEMP, $env:TMP, "C:\Windows\Temp", "C:\Windows\Prefetch") | ForEach-Object {
    if (Test-Path $_) { Remove-Item "$_\*" -Recurse -Force }
}
Write-OK "Temp files cleared"

# 1f. Remove non-default user profiles
Write-Verbose "Removing non-default user profiles..."
Get-CimInstance Win32_UserProfile |
    Where-Object {
        -not $_.Special -and
        $_.LocalPath -notmatch "Administrator|Default|Public|cloudbase-init|systemprofile|NetworkService|LocalService"
    } | ForEach-Object {
        try {
            Remove-CimInstance -InputObject $_
            Write-OK "Removed profile: $($_.LocalPath)"
        } catch {
            Write-SKIP "Could not remove profile: $($_.LocalPath)"
        }
    }

# 1g. Clear event logs
Write-Verbose "Clearing event logs..."
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.RecordCount -gt 0 } | ForEach-Object {
        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
        } catch { }
    }
Write-OK "Event logs cleared"
Write-Verbose "Wiping WinRM listeners and cert store..."

Get-ChildItem WSMan:\Localhost\Listener -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
$store.Open("ReadWrite")
@($store.Certificates) | ForEach-Object {
    try {
        $store.Remove($_)
        Write-Verbose "  [OK] Removed cert: $($_.Subject) ($($_.Thumbprint))"
    } catch {
        Write-Verbose "  [SKIP] Could not remove cert: $($_.Thumbprint)"
    }
}
$store.Close()
Write-OK "WinRM listeners and all LocalMachine\My certs wiped"

# 1i. Clear NIC history to prevent ghost adapters in clones
Write-Verbose "Clearing NIC history..."
$netKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}"
if (Test-Path $netKey) {
    Get-ChildItem $netKey |
        Where-Object { $_.PSChildName -ne "Descriptions" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
ipconfig /flushdns | Out-Null
Write-OK "NIC history and DNS cache cleared"

# 1k. Disk cleanup
Write-Verbose "Running disk cleanup..."
$cleanupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
Get-ChildItem $cleanupKey | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "StateFlags0001" -Value 2 -Type DWORD -Force
}
Start-Process cleanmgr.exe -ArgumentList "/sagerun:1" -Wait -NoNewWindow
Write-OK "Disk cleanup complete"

$ErrorActionPreference = "Stop"


# ============================================================
# STEP 2: STAGE setup.ps1 INTO THE IMAGE
#
# FirstLogonCommands in unattend.xml calls this script by path
# on each clone's first boot. It must exist in the image before
# sysprep runs - we copy it here rather than relying on the
# unattend to write it, keeping the unattend simple and avoiding
# any inline script quoting issues.
# ============================================================

Write-Step "Step 2: Staging setup.ps1"

$scriptDest = "C:\Windows\Setup\Scripts"
if (-not (Test-Path $scriptDest)) {
    New-Item -ItemType Directory -Path $scriptDest -Force | Out-Null
}

Copy-Item $WinRMScriptPath "$scriptDest\setup.ps1" -Force
Write-OK "setup.ps1 staged to $scriptDest\setup.ps1"


# ============================================================
# STEP 3: PLACE UNATTEND AND RUN SYSPREP
# ============================================================

Write-Step "Step 3: Sysprep"

$sysprepUnattend = "C:\Windows\System32\Sysprep\unattend.xml"

Write-Verbose "Copying unattend.xml to Sysprep folder..."
Copy-Item $UnattendPath $sysprepUnattend -Force
Write-OK "unattend.xml placed at $sysprepUnattend"

Write-Host "`n  Launching sysprep. The VM will shut down when complete." -ForegroundColor Yellow
Write-Host "  After shutdown: convert to template in Proxmox." -ForegroundColor Yellow
Write-Host "  DO NOT boot the VM again before templating.`n" -ForegroundColor Red

Start-Sleep -Seconds 3

& C:\Windows\System32\Sysprep\sysprep.exe `
    /generalize `
    /oobe `
    /shutdown `
    /unattend:$sysprepUnattend
