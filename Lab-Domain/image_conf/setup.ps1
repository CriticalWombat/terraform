# setup.ps1 — runs once on first boot of every clone via unattend.xml FirstLogonCommands.
# Shared by both the Windows Server (DC) and Windows 10 (client) templates.

$logFile = "C:\Windows\Temp\setup.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
    Write-Host $line
}

trap { Write-Log "FATAL: $_" "ERROR"; exit 1 }

Write-Log "=== First-boot setup starting on $env:COMPUTERNAME ==="

# ----------------------------------------------------------
# 1. Network profile -> Private (required for PSRemoting)
# ----------------------------------------------------------
try {
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop
    Write-Log "Network profile set to Private"
} catch {
    Write-Log "Network profile: $_ (may already be set)" "WARN"
}

# ----------------------------------------------------------
# 2. Proxmox QEMU guest agent
#    Must be pre-installed in the template from the VirtIO ISO.
#    This just ensures the service is running after clone boot.
# ----------------------------------------------------------
$ga = Get-Service "QEMU-GA" -ErrorAction SilentlyContinue
if ($ga) {
    Set-Service "QEMU-GA" -StartupType Automatic
    Start-Service "QEMU-GA" -ErrorAction SilentlyContinue
    Write-Log "QEMU guest agent started"
} else {
    Write-Log "QEMU guest agent not installed — Terraform IP discovery will fail!" "WARN"
}

# ----------------------------------------------------------
# 3. Disable Windows Defender real-time protection
#    Pentesting tools (Mimikatz, BadBlood payloads, etc.) will
#    be blocked or deleted by Defender otherwise.
# ----------------------------------------------------------
try {
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
    Write-Log "Defender real-time protection disabled"
} catch {
    Write-Log "Could not disable Defender (may not be present on Server): $_" "WARN"
}

# ----------------------------------------------------------
# 4. Disable Windows Update automatic restart
#    Prevents unexpected reboots mid-lab-session.
# ----------------------------------------------------------
$auKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
New-Item -Path $auKey -Force | Out-Null
Set-ItemProperty -Path $auKey -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWORD -Force
Set-ItemProperty -Path $auKey -Name "AUOptions"                     -Value 1 -Type DWORD -Force
Write-Log "Windows Update auto-restart disabled"

# ----------------------------------------------------------
# 5. Disable NLA for RDP
#    Allows RDP connections without pre-authentication,
#    needed before domain join and for most pentest tooling.
# ----------------------------------------------------------
$tsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
Set-ItemProperty -Path $tsKey -Name "UserAuthentication" -Value 0 -Type DWORD -Force
Write-Log "NLA for RDP disabled"

# ----------------------------------------------------------
# 6. High-performance power plan + disable sleep/screensaver
#    Prevents VMs from going idle during long pentesting runs.
# ----------------------------------------------------------
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null   # High performance GUID
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "0" -ErrorAction SilentlyContinue
Write-Log "Power plan set to High Performance, sleep disabled"

# ----------------------------------------------------------
# 7. WinRM service
# ----------------------------------------------------------
Set-Service WinRM -StartupType Automatic
Start-Service WinRM -ErrorAction SilentlyContinue

$qc = cmd /c winrm quickconfig -quiet -force 2>&1
Write-Log "winrm quickconfig: $qc"

try {
    Start-Service MpsSvc -ErrorAction SilentlyContinue
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
    Write-Log "PSRemoting enabled"
} catch {
    Write-Log "Enable-PSRemoting: $_ (may already be configured)" "WARN"
}

Set-Item WSMan:\localhost\Service\AllowUnencrypted  -Value 1 -Force
Set-Item WSMan:\localhost\Service\Auth\Basic        -Value 1 -Force
Set-Item WSMan:\localhost\Client\Auth\Basic         -Value 1 -Force
Set-Item WSMan:\localhost\Client\TrustedHosts       -Value '*' -Force
Write-Log "WSMan auth settings configured"

# ----------------------------------------------------------
# 8. Self-signed cert bound to this clone's hostname + HTTPS listener
# ----------------------------------------------------------
Get-ChildItem WSMan:\Localhost\Listener | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$cert = New-SelfSignedCertificate `
    -DnsName $env:COMPUTERNAME `
    -CertStoreLocation Cert:\LocalMachine\My `
    -NotAfter (Get-Date).AddYears(5)

New-Item `
    -Path WSMan:\Localhost\Listener `
    -Transport HTTPS `
    -Address * `
    -CertificateThumbPrint $cert.Thumbprint `
    -Force | Out-Null
Write-Log "WinRM HTTPS listener created (thumbprint: $($cert.Thumbprint))"

# ----------------------------------------------------------
# 9. Firewall rules for WinRM (both HTTP and HTTPS, all profiles)
# ----------------------------------------------------------
@("WinRM-HTTP", "WinRM-HTTPS", "Windows Remote Management (HTTP-In)", "Windows Remote Management (HTTPS-In)") |
    ForEach-Object {
        Remove-NetFirewallRule -Name        $_ -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue
    }

New-NetFirewallRule -Name "WinRM-HTTP"  -DisplayName "WinRM HTTP"  -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5985 -Profile Any | Out-Null
New-NetFirewallRule -Name "WinRM-HTTPS" -DisplayName "WinRM HTTPS" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5986 -Profile Any | Out-Null
Write-Log "WinRM firewall rules created"

# ----------------------------------------------------------
# 10. Restart WinRM to apply all changes
# ----------------------------------------------------------
Restart-Service WinRM
Write-Log "=== Setup complete — WinRM HTTPS ready on port 5986 ==="
