#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prepares a fresh Windows 10 VM as a Proxmox/Terraform template.
    Applies best-practice cleanup, then runs sysprep with the provided
    unattend.xml.

.DESCRIPTION
    Run this script on a FRESH Windows 10 VM (not a clone) before
    converting to a Proxmox template. It will:

      1.  Apply pre-sysprep best-practice cleanup
      2.  Place the unattend.xml and launch sysprep

    The VM will shut down automatically when sysprep completes.
    After shutdown, convert the VM to a template in Proxmox.

.PARAMETER UnattendPath
    Full path to your unattend.xml. Defaults to the script's own directory.

.PARAMETER SkipSysprep
    Run all configuration and cleanup steps but do NOT launch sysprep.
    Useful for testing before committing to a sysprep.

.EXAMPLE
    # Full run - cleans up, sysprepped and shuts down
    .\Prepare-Template.ps1

    # Test cleanup steps without sysprepping yet
    .\Prepare-Template.ps1 -SkipSysprep
#>

param(
    [string]$UnattendPath = "$PSScriptRoot\unattend.xml",
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

# Confirm unattend exists before doing anything destructive
if (-not $SkipSysprep) {
    if (-not (Test-Path $UnattendPath)) {
        Write-FAIL "unattend.xml not found at: $UnattendPath"
        Write-Host "  Place your unattend.xml next to this script or pass -UnattendPath" -ForegroundColor Red
        exit 1
    }
    Write-OK "unattend.xml found at: $UnattendPath"
}

# Confirm running as SYSTEM or Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-FAIL "Script must be run as Administrator"
    exit 1
}
Write-OK "Running as Administrator"

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
if (Test-Path $sysprepKey) {
    Set-ItemProperty -Path $sysprepKey -Name "GeneralizationState" -Value 7 -Force
    Set-ItemProperty -Path $sysprepKey -Name "CleanupState"        -Value 2 -Force
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" `
    -Name "SkipRearm" -Value 1 -Force
Write-OK "Sysprep state reset"

# 1b. Rearm Windows activation
Write-Verbose "Rearming activation..."
& cscript //nologo C:\Windows\System32\slmgr.vbs /rearm
Write-OK "Activation rearmed"

# 1c. Clear Panther cache - THIS is what caused your unattend to not apply.
#     Windows caches the unattend here and uses it instead of the Sysprep copy.
Write-Verbose "Clearing Panther cache..."
@(
    "C:\Windows\Panther",
    "C:\Windows\Panther\UnattendGC",
    "C:\Windows\System32\Sysprep\Panther"
) | ForEach-Object {
    if (Test-Path $_) { Get-ChildItem $_ -File | Remove-Item -Force -Recurse }
}

# Remove any stale unattend copies that Windows might pick up
@(
    "C:\Windows\Panther\unattend.xml",
    "C:\Windows\unattend.xml",
    "C:\unattend.xml"
) | ForEach-Object {
    if (Test-Path $_) { Remove-Item $_ -Force }
}
Write-OK "Panther cache cleared"

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

# 1h. Reset CloudBase-Init state if installed
$cbLog = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log"
$cbKey = "HKLM:\SOFTWARE\Cloudbase Solutions\cloudbase-init"
if (Test-Path $cbLog) {
    Remove-Item "$cbLog\*" -Recurse -Force
    Write-OK "CloudBase-Init logs cleared"
}
if (Test-Path $cbKey) {
    Remove-Item $cbKey -Recurse -Force
    Write-OK "CloudBase-Init registry state cleared"
}

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

# 1j. Disk cleanup
Write-Verbose "Running disk cleanup..."
$cleanupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
Get-ChildItem $cleanupKey | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "StateFlags0001" -Value 2 -Type DWORD -Force
}
Start-Process cleanmgr.exe -ArgumentList "/sagerun:1" -Wait -NoNewWindow
Write-OK "Disk cleanup complete"

$ErrorActionPreference = "Stop"


# ============================================================
# STEP 2: PLACE UNATTEND AND RUN SYSPREP
# ============================================================

Write-Step "Step 2: Sysprep"

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