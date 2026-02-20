#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Two-phase WinRM setup for cloned Windows 10 VMs.

.DESCRIPTION
    This script is staged into the template image at
    C:\Windows\Setup\Scripts\winrm-setup.ps1 by Prepare-Template.ps1
    before sysprep, and is called by FirstLogonCommands in unattend.xml
    on each clone's first boot.

    PHASE 1 (FirstLogonCommands - first boot):
      - Generates a unique hostname and renames the computer
      - Registers itself as a RunOnce entry to resume after reboot
      - Reboots

    PHASE 2 (RunOnce - second boot, post-rename):
      - $env:COMPUTERNAME is now the correct unique hostname
      - Configures WinRM fully
      - Generates a self-signed cert bound to the correct hostname
      - Creates HTTPS listener, firewall rules, restarts WinRM

    Why two phases?
      FirstLogonCommands fires before the sysprep-assigned hostname is
      reliably reflected in $env:COMPUTERNAME in the current session.
      By explicitly renaming and rebooting, Phase 2 is guaranteed to
      run with the correct hostname in both $env:COMPUTERNAME and the
      Windows session environment - which is required for the WinRM
      cert CN to match the actual hostname Terraform will connect to.

.PARAMETER Phase
    Internal parameter. Do not pass manually.
    "1" = first boot rename phase (default, called by FirstLogonCommands)
    "2" = post-reboot WinRM configuration phase (called by RunOnce)
#>

param(
    [string]$Phase = "1"
)

$logFile     = "C:\Windows\Temp\winrm-setup.log"
$scriptPath  = "C:\Windows\Setup\Scripts\winrm-setup.ps1"
$runOnceKey  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
$runOnceName = "WinRM-Setup-Phase2"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] [Phase $Phase] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

trap {
    Write-Log "FATAL: $_" "ERROR"
    exit 1
}


# ==============================================================
# PHASE 1 - Rename computer and reboot
# Called directly by FirstLogonCommands on first boot.
# ==============================================================

if ($Phase -eq "1") {

    Write-Log "======================================================"
    Write-Log "winrm-setup.ps1 PHASE 1 starting"
    Write-Log "Current hostname (pre-rename): $env:COMPUTERNAME"
    Write-Log "======================================================"

    # ----------------------------------------------------------
    # Generate a unique hostname.
    #
    # We do NOT rely on $env:COMPUTERNAME here because sysprep's
    # specialize pass may not have committed its generated name
    # into the live session environment yet. Instead we generate
    # our own name and set it explicitly, guaranteeing uniqueness.
    #
    # Format: WIN-<8 random hex chars>  (e.g. WIN-3F9A1C2B)
    # Total length: 12 chars - well within the 15-char NetBIOS limit.
    # ----------------------------------------------------------
    $randomSuffix = ([System.Guid]::NewGuid().ToString().Replace('-', '').Substring(0, 8)).ToUpper()
    $newHostname  = "WIN-$randomSuffix"

    Write-Log "Generated unique hostname: $newHostname"

    # Rename the computer (takes effect after reboot)
    try {
        Rename-Computer -NewName $newHostname -Force -ErrorAction Stop
        Write-Log "Computer rename to '$newHostname' queued successfully"
    } catch {
        Write-Log "Rename-Computer failed: $_" "ERROR"
        exit 1
    }

    # ----------------------------------------------------------
    # Register Phase 2 as a RunOnce entry.
    # RunOnce fires once at next logon (Administrator via AutoLogon)
    # then self-deletes. $env:COMPUTERNAME will be correct by then.
    # ----------------------------------------------------------
    $phase2Command = "powershell -ExecutionPolicy Bypass -File `"$scriptPath`" -Phase 2"

    try {
        Set-ItemProperty -Path $runOnceKey -Name $runOnceName -Value $phase2Command -Force
        Write-Log "Phase 2 registered in RunOnce: $phase2Command"
    } catch {
        Write-Log "Failed to register RunOnce entry: $_" "ERROR"
        exit 1
    }

    Write-Log "Phase 1 complete. Rebooting to apply hostname change..."
    Write-Log "======================================================"

    Start-Sleep -Seconds 3
    Restart-Computer -Force
    exit 0
}


# ==============================================================
# PHASE 2 - Full WinRM configuration after hostname rename
# Called automatically by RunOnce on the second boot.
# $env:COMPUTERNAME is now the unique name set in Phase 1.
# ==============================================================

if ($Phase -eq "2") {

    Write-Log "======================================================"
    Write-Log "winrm-setup.ps1 PHASE 2 starting"
    Write-Log "Hostname (post-rename): $env:COMPUTERNAME"
    Write-Log "======================================================"

    # ----------------------------------------------------------
    # 1. Network profile -> Private
    # ----------------------------------------------------------
    Write-Log "Setting network profile to Private..."
    try {
        Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop
        Write-Log "Network profile set to Private"
    } catch {
        Write-Log "Could not set network profile: $_" "WARN"
    }

    # ----------------------------------------------------------
    # 2. Start WinRM service
    # ----------------------------------------------------------
    Write-Log "Setting WinRM to Automatic and starting..."
    Set-Service WinRM -StartupType Automatic
    Start-Service WinRM -ErrorAction SilentlyContinue
    Write-Log "WinRM service started"

    # ----------------------------------------------------------
    # 3. Wipe any stale listeners and certs (defensive)
    # ----------------------------------------------------------
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

    # ----------------------------------------------------------
    # 4. Bootstrap WinRM
    # ----------------------------------------------------------
    Write-Log "Running winrm quickconfig..."
    $qc = cmd /c winrm quickconfig -quiet -force 2>&1
    Write-Log "quickconfig output: $qc"

    Write-Log "Running Enable-PSRemoting..."
    try {
        Start-Service MpsSvc -ErrorAction SilentlyContinue
        Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
        Write-Log "PSRemoting enabled"
    } catch {
        Write-Log "Enable-PSRemoting threw (may already be configured): $_" "WARN"
    }

    # ----------------------------------------------------------
    # 5. WSMan auth and transport settings
    # ----------------------------------------------------------
    Write-Log "Configuring WSMan settings..."
    Set-Item WSMan:\localhost\Service\AllowUnencrypted  -Value 1 -Force
    Set-Item WSMan:\localhost\Service\Auth\Basic        -Value 1 -Force
    Set-Item WSMan:\localhost\Client\Auth\Basic         -Value 1 -Force
    Set-Item WSMan:\localhost\Client\TrustedHosts       -Value '*' -Force
    Write-Log "WSMan settings configured"

    # ----------------------------------------------------------
    # 6. Generate self-signed cert and create HTTPS listener
    #
    #    $env:COMPUTERNAME is now the final unique hostname.
    #    The cert CN will match the hostname Terraform connects to.
    # ----------------------------------------------------------
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

    # ----------------------------------------------------------
    # 7. Firewall rules - Profile Any
    # ----------------------------------------------------------
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

    # ----------------------------------------------------------
    # 8. Restart WinRM
    # ----------------------------------------------------------
    Write-Log "Restarting WinRM..."
    Restart-Service WinRM
    Write-Log "WinRM restarted"

    # ----------------------------------------------------------
    # 9. Sanity checks
    # ----------------------------------------------------------
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
    Write-Log "winrm-setup.ps1 PHASE 2 complete"
    Write-Log "Final hostname: $env:COMPUTERNAME"
    Write-Log "Log: $logFile"
    Write-Log "======================================================"

    exit 0
}

# Should never reach here
Write-Log "Unknown phase: '$Phase'. Must be '1' or '2'." "ERROR"
exit 1
