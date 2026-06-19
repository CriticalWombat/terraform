# setup.ps1 — runs once on first boot of every clone via SetupComplete.cmd (SYSTEM context).
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
# 3. Disable Windows Update automatic restart
#    Prevents unexpected reboots mid-lab-session.
# ----------------------------------------------------------
$auKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
New-Item -Path $auKey -Force | Out-Null
Set-ItemProperty -Path $auKey -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWORD -Force
Set-ItemProperty -Path $auKey -Name "AUOptions"                     -Value 1 -Type DWORD -Force
Write-Log "Windows Update auto-restart disabled"

# ----------------------------------------------------------
# 4. High-performance power plan + disable sleep/screensaver
#    Prevents VMs from going idle during long pentesting runs.
# ----------------------------------------------------------
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null   # High performance GUID
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
Write-Log "Power plan set to High Performance, sleep disabled"

# ----------------------------------------------------------
# 5. Enable RDP + disable Server Manager auto-open (Server SKUs only)
# ----------------------------------------------------------
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWORD -Force
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
Write-Log "RDP enabled"

if ((Get-CimInstance Win32_OperatingSystem).Caption -match 'Server') {
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1 -PropertyType DWORD -Force | Out-Null
    Write-Log "Server Manager auto-open disabled"
}

# ----------------------------------------------------------
# 6. WinRM service
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
# 7. Firewall rule for WinRM HTTP
# ----------------------------------------------------------
@("WinRM-HTTP", "Windows Remote Management (HTTP-In)") |
    ForEach-Object {
        Remove-NetFirewallRule -Name        $_ -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue
    }

New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5985 -Profile Any | Out-Null
Write-Log "WinRM firewall rule created (port 5985)"

# ----------------------------------------------------------
# 8. Restart WinRM to apply all changes
# ----------------------------------------------------------
Restart-Service WinRM
Write-Log "=== Setup complete — WinRM HTTP ready on port 5985 ==="
