#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures WinRM on a cloned Windows 10 VM on first boot.

.DESCRIPTION
    This script is staged into the template image at
    C:\Windows\Setup\Scripts\winrm-setup.ps1 by Prepare-Template.ps1
    before sysprep. It is called by FirstLogonCommands in unattend.xml
    on each clone's first boot.

    By the time this runs:
      - Sysprep has already assigned the clone its unique hostname
      - The template cert has been wiped from the image before sysprep
      - $env:COMPUTERNAME is correct for THIS clone

    This script:
      1.  Sets the network profile to Private (required for WinRM)
      2.  Starts and configures the WinRM service
      3.  Wipes any stale listeners/certs (defensive, in case anything
          survived from a prior run or unexpected state)
      4.  Generates a fresh self-signed cert bound to this clone's hostname
      5.  Creates an HTTPS listener using that cert
      6.  Configures auth settings
      7.  Creates firewall rules for ports 5985 and 5986
      8.  Restarts WinRM
      9.  Logs all activity to C:\Windows\Temp\winrm-setup.log
#>

$logFile = "C:\Windows\Temp\winrm-setup.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

# Trap all terminating errors, log them, then exit non-zero
trap {
    Write-Log "FATAL: $_" "ERROR"
    exit 1
}

Write-Log "======================================================"
Write-Log "winrm-setup.ps1 starting"
Write-Log "Hostname: $env:COMPUTERNAME"
Write-Log "======================================================"


# --------------------------------------------------------------
# 1. Network profile -> Private
#    WinRM quickconfig and Enable-PSRemoting both check the
#    network profile. If it is Public they create rules scoped
#    to Public only, or refuse to run at all on Windows 10.
# --------------------------------------------------------------
Write-Log "Setting network profile to Private..."
try {
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop
    Write-Log "Network profile set to Private"
} catch {
    # Non-fatal - log and continue. SkipNetworkProfileCheck below handles it.
    Write-Log "Could not set network profile (may have no connected adapters yet): $_" "WARN"
}


# --------------------------------------------------------------
# 2. Start WinRM service
# --------------------------------------------------------------
Write-Log "Setting WinRM to Automatic and starting..."
Set-Service WinRM -StartupType Automatic
Start-Service WinRM -ErrorAction SilentlyContinue
Write-Log "WinRM service started"


# --------------------------------------------------------------
# 3. Wipe any stale listeners and certs (defensive)
#    The template image should already be clean after
#    Prepare-Template.ps1, but this guard handles edge cases
#    such as a clone that was booted before templating.
# --------------------------------------------------------------
Write-Log "Wiping any stale WinRM listeners and LocalMachine\My certs..."

Get-ChildItem WSMan:\Localhost\Listener -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
$store.Open("ReadWrite")
@($store.Certificates) | ForEach-Object {
    $store.Remove($_)
    Write-Log "  Removed cert: $($_.Subject) [$($_.Thumbprint)]"
}
$store.Close()
Write-Log "Stale listeners and certs cleared"


# --------------------------------------------------------------
# 4. Bootstrap WinRM via quickconfig then Enable-PSRemoting
#    quickconfig initialises the WSMan:\ PSDrive.
#    Enable-PSRemoting ensures all remoting settings are applied.
# --------------------------------------------------------------
Write-Log "Running winrm quickconfig..."
$qc = cmd /c winrm quickconfig -quiet -force 2>&1
Write-Log "quickconfig output: $qc"

Write-Log "Running Enable-PSRemoting..."
try {
    Start-Service MpsSvc -ErrorAction SilentlyContinue  # firewall svc must be up
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
    Write-Log "PSRemoting enabled"
} catch {
    Write-Log "Enable-PSRemoting threw (may already be configured): $_" "WARN"
}


# --------------------------------------------------------------
# 5. WSMan auth and transport settings
# --------------------------------------------------------------
Write-Log "Configuring WSMan settings..."
Set-Item WSMan:\localhost\Service\AllowUnencrypted  -Value 1 -Force
Set-Item WSMan:\localhost\Service\Auth\Basic        -Value 1 -Force
Set-Item WSMan:\localhost\Client\Auth\Basic         -Value 1 -Force
Set-Item WSMan:\localhost\Client\TrustedHosts       -Value '*' -Force
Write-Log "WSMan settings configured"


# --------------------------------------------------------------
# 6. Generate a fresh self-signed cert for THIS clone's hostname
#    and create an HTTPS listener bound to it.
#
#    $env:COMPUTERNAME at this point is the clone's actual hostname
#    assigned by sysprep, NOT the template hostname.
# --------------------------------------------------------------
Write-Log "Generating self-signed certificate for: $env:COMPUTERNAME"

$cert = New-SelfSignedCertificate `
    -DnsName $env:COMPUTERNAME `
    -CertStoreLocation Cert:\LocalMachine\My `
    -NotAfter (Get-Date).AddYears(5)

Write-Log "Certificate created - Thumbprint: $($cert.Thumbprint), CN: $($cert.Subject)"

Write-Log "Creating HTTPS listener..."
New-Item `
    -Path WSMan:\Localhost\Listener `
    -Transport HTTPS `
    -Address * `
    -CertificateThumbPrint $cert.Thumbprint `
    -Force | Out-Null

Write-Log "HTTPS listener created"


# --------------------------------------------------------------
# 7. Firewall rules for WinRM HTTP (5985) and HTTPS (5986)
#    Profile Any ensures rules apply regardless of how Windows
#    classifies the network on this particular clone.
# --------------------------------------------------------------
Write-Log "Creating firewall rules..."

@("WinRM-HTTP", "WinRM-HTTPS",
  "Windows Remote Management (HTTP-In)",
  "Windows Remote Management (HTTPS-In)") | ForEach-Object {
    Remove-NetFirewallRule -Name        $_ -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue
}

New-NetFirewallRule `
    -Name        "WinRM-HTTP" `
    -DisplayName "WinRM HTTP" `
    -Enabled     True `
    -Direction   Inbound `
    -Protocol    TCP `
    -Action      Allow `
    -LocalPort   5985 `
    -Profile     Any | Out-Null

New-NetFirewallRule `
    -Name        "WinRM-HTTPS" `
    -DisplayName "WinRM HTTPS" `
    -Enabled     True `
    -Direction   Inbound `
    -Protocol    TCP `
    -Action      Allow `
    -LocalPort   5986 `
    -Profile     Any | Out-Null

Write-Log "Firewall rules created (Profile: Any)"


# --------------------------------------------------------------
# 8. Restart WinRM to apply everything
# --------------------------------------------------------------
Write-Log "Restarting WinRM..."
Restart-Service WinRM
Write-Log "WinRM restarted"


# --------------------------------------------------------------
# 9. Quick local sanity check
# --------------------------------------------------------------
Write-Log "Running sanity checks..."

$svc = Get-Service WinRM
Write-Log "WinRM service status: $($svc.Status)"

$httpsListener = winrm enumerate winrm/config/listener 2>&1
if ($httpsListener -match "HTTPS") {
    Write-Log "HTTPS listener confirmed present"
} else {
    Write-Log "WARNING: HTTPS listener not found in winrm enumerate output" "WARN"
}

$port5986 = Get-NetTCPConnection -LocalPort 5986 -State Listen -ErrorAction SilentlyContinue
if ($port5986) {
    Write-Log "Port 5986 confirmed listening"
} else {
    Write-Log "WARNING: Nothing listening on port 5986" "WARN"
}

Write-Log "======================================================"
Write-Log "winrm-setup.ps1 complete"
Write-Log "Log: $logFile"
Write-Log "======================================================"
