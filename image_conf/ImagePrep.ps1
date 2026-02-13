#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prepares a fresh Windows 10 VM as a Proxmox/Terraform template.
    Configures WinRM correctly, applies best-practice cleanup, then
    runs sysprep with the provided unattend.xml.

.DESCRIPTION
    Run this script on a FRESH Windows 10 VM (not a clone) before
    converting to a Proxmox template. It will:

      1.  Configure WinRM in the correct order so it works on Windows 10
      2.  Verify WinRM is reachable before proceeding
      3.  Apply pre-sysprep best-practice cleanup
      4.  Place the unattend.xml and launch sysprep

    The VM will shut down automatically when sysprep completes.
    After shutdown, convert the VM to a template in Proxmox.

.PARAMETER UnattendPath
    Full path to your unattend.xml. Defaults to the script's own directory.

.PARAMETER SkipSysprep
    Run all configuration and cleanup steps but do NOT launch sysprep.
    Useful for testing WinRM connectivity before committing to a sysprep.

.EXAMPLE
    # Full run - configures, cleans up, sysprepped and shuts down
    .\Prepare-Template.ps1

    # Test WinRM works without sysprepping yet
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


# ============================================================
# STEP 1: CONFIGURE WINRM
# Done FIRST so you can test connectivity before sysprep.
# The unattend will reconfigure WinRM on each clone's first
# boot - this step is for validating the base image works.
# ============================================================

Write-Step "Step 1: Configuring WinRM"

# 1a. Force network profile to Private - MUST happen before
#     quickconfig or listener rules get scoped to Public profile
Write-Verbose "Setting network profile to Private..."
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
Write-OK "Network profile set to Private"

# 1b. Set WinRM to Automatic and start it
#     On Windows 10 WinRM is Manual/Stopped by default
Write-Verbose "Starting WinRM service..."
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
Write-OK "WinRM service started (Automatic)"

# 1c. Bootstrap via native winrm.cmd - initialises the WSMan:\
#     PSDrive that all subsequent Set-Item commands require.
#     More reliable than going straight to Enable-PSRemoting on Win10.
#     Wrapped in try/catch because quickconfig throws a WSManFault if
#     WinRM is already configured (e.g. after a -SkipSysprep run),
#     which would halt the script due to $ErrorActionPreference = Stop.
Write-Verbose "Running winrm quickconfig..."
try {
    $quickconfig = cmd /c winrm quickconfig -quiet -force 2>&1
    Write-OK "winrm quickconfig complete"
} catch {
    Write-OK "winrm quickconfig: already configured, continuing"
}

# 1d. Enable-PSRemoting now that the service and WSMan drive are up
Write-Verbose "Enabling PSRemoting..."
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Write-OK "PSRemoting enabled"

# 1e. WSMan settings - using 1 instead of $true
#     $true is not expanded correctly when launched from cmd/XML context
Write-Verbose "Configuring WSMan settings..."
Set-Item WSMan:\localhost\Service\AllowUnencrypted  -Value 1 -Force
Set-Item WSMan:\localhost\Service\Auth\Basic        -Value 1 -Force
Set-Item WSMan:\localhost\Client\Auth\Basic         -Value 1 -Force
Set-Item WSMan:\localhost\Client\TrustedHosts       -Value '*' -Force
Write-OK "WSMan auth settings configured"

# 1f. Create HTTPS listener with a self-signed cert
Write-Verbose "Creating HTTPS listener..."
$cert = New-SelfSignedCertificate `
    -DnsName $env:COMPUTERNAME `
    -CertStoreLocation Cert:\LocalMachine\My `
    -NotAfter (Get-Date).AddYears(5)

# Remove any existing HTTPS listeners before creating new one
Get-ChildItem WSMan:\Localhost\Listener |
    Where-Object { $_.Keys -contains 'Transport=HTTPS' } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

New-Item -Path WSMan:\Localhost\Listener `
    -Transport HTTPS `
    -Address * `
    -CertificateThumbPrint $cert.Thumbprint `
    -Force | Out-Null

Write-OK "HTTPS listener created (cert thumbprint: $($cert.Thumbprint))"

# 1g. Firewall rules - Profile Any ensures they apply regardless
#     of whether the network profile is Public, Private, or Domain
Write-Verbose "Creating firewall rules..."

# Remove any existing WinRM rules first to avoid conflicts
@("WinRM-HTTP", "WinRM-HTTPS",
  "Windows Remote Management (HTTP-In)",
  "Windows Remote Management (HTTPS-In)") | ForEach-Object {
    Remove-NetFirewallRule -Name $_ -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue
}

New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM HTTP" `
    -Enabled True -Direction Inbound -Protocol TCP `
    -Action Allow -LocalPort 5985 -Profile Any | Out-Null

New-NetFirewallRule -Name "WinRM-HTTPS" -DisplayName "WinRM HTTPS" `
    -Enabled True -Direction Inbound -Protocol TCP `
    -Action Allow -LocalPort 5986 -Profile Any | Out-Null

Write-OK "Firewall rules created (Profile: Any)"

# 1h. Restart WinRM to apply everything cleanly
Restart-Service WinRM
Write-OK "WinRM restarted"


# ============================================================
# STEP 2: VERIFY WINRM IS WORKING LOCALLY
# If this fails, sysprep won't help - fix WinRM first.
# ============================================================

Write-Step "Step 2: Verifying WinRM locally"

# Check service
$svc = Get-Service WinRM
if ($svc.Status -eq "Running") {
    Write-OK "WinRM service is Running"
} else {
    Write-FAIL "WinRM service is NOT running - status: $($svc.Status)"
    exit 1
}

# Check listener
$listeners = winrm enumerate winrm/config/listener 2>&1
if ($listeners -match "HTTPS") {
    Write-OK "HTTPS listener is present"
} else {
    Write-FAIL "No HTTPS listener found. Output: $listeners"
    exit 1
}

# Check port is actually listening
$port5986 = Get-NetTCPConnection -LocalPort 5986 -State Listen -ErrorAction SilentlyContinue
if ($port5986) {
    Write-OK "Port 5986 is listening"
} else {
    Write-FAIL "Nothing listening on port 5986"
    exit 1
}

# Check firewall rules
$fwRule = Get-NetFirewallRule -Name "WinRM-HTTPS" -ErrorAction SilentlyContinue
if ($fwRule -and $fwRule.Enabled) {
    Write-OK "WinRM-HTTPS firewall rule is enabled (Profile: $($fwRule.Profile))"
} else {
    Write-FAIL "WinRM-HTTPS firewall rule missing or disabled"
    exit 1
}

Write-Host "`n  WinRM verification passed. Test remote connectivity now." -ForegroundColor Green
Write-Host "  From your Terraform host run:" -ForegroundColor Yellow
Write-Host "    nc -zv $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^127\.' } | Select-Object -First 1).IPAddress) 5986" -ForegroundColor White
Write-Host "`n  If nc succeeds, press Enter to continue with cleanup and sysprep." -ForegroundColor Yellow

if ($SkipSysprep) {
    Write-Host "`n  -SkipSysprep specified. Stopping here." -ForegroundColor Cyan
    Write-Host "  Re-run without -SkipSysprep when ready to proceed." -ForegroundColor Cyan
    exit 0
}

Read-Host "`n  Press Enter to continue with cleanup and sysprep (Ctrl+C to abort)"


# ============================================================
# STEP 3: PRE-SYSPREP CLEANUP
# ============================================================

Write-Step "Step 3: Pre-sysprep cleanup"

$ErrorActionPreference = "SilentlyContinue"

# 3a. Reset sysprep generalization count
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

# 3b. Rearm Windows activation
Write-Verbose "Rearming activation..."
& cscript //nologo C:\Windows\System32\slmgr.vbs /rearm
Write-OK "Activation rearmed"

# 3c. Clear Panther cache - THIS is what caused your unattend to not apply.
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

# 3d. Clear Windows Update cache
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

# 3e. Clear temp files
Write-Verbose "Clearing temp files..."
@($env:TEMP, $env:TMP, "C:\Windows\Temp", "C:\Windows\Prefetch") | ForEach-Object {
    if (Test-Path $_) { Remove-Item "$_\*" -Recurse -Force }
}
Write-OK "Temp files cleared"

# 3f. Remove non-default user profiles
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

# 3g. Clear event logs
Write-Verbose "Clearing event logs..."
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.RecordCount -gt 0 } | ForEach-Object {
        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
        } catch { }
    }
Write-OK "Event logs cleared"

# 3h. Reset CloudBase-Init state if installed
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

# 3i. Clear NIC history to prevent ghost adapters in clones
Write-Verbose "Clearing NIC history..."
$netKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}"
if (Test-Path $netKey) {
    Get-ChildItem $netKey |
        Where-Object { $_.PSChildName -ne "Descriptions" } |
        Remove-Item -Recurse -Force
}
ipconfig /flushdns | Out-Null
Write-OK "NIC history and DNS cache cleared"

# 3j. Disk cleanup
Write-Verbose "Running disk cleanup..."
$cleanupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
Get-ChildItem $cleanupKey | ForEach-Object {
    Set-ItemProperty -Path $_.PSPath -Name "StateFlags0001" -Value 2 -Type DWORD -Force
}
Start-Process cleanmgr.exe -ArgumentList "/sagerun:1" -Wait -NoNewWindow
Write-OK "Disk cleanup complete"

$ErrorActionPreference = "Stop"


# ============================================================
# STEP 4: PLACE UNATTEND AND RUN SYSPREP
# ============================================================

Write-Step "Step 4: Sysprep"

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