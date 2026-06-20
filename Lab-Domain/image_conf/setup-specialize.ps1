# setup-specialize.ps1 - runs during the unattend specialize pass via RunSynchronous.
# Only performs registry writes and executable calls - no Windows services required.
# Service-dependent setup (WinRM, firewall, guest agent) is deferred to setup-winrm.ps1
# which runs via the FirstBootWinRM scheduled task after the system fully boots.
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

Write-Log "=== Specialize setup starting on $env:COMPUTERNAME ==="

# ----------------------------------------------------------
# 1. QEMU guest agent - set startup type only (Start-Service
#    deferred to setup-winrm.ps1 when services are available)
# ----------------------------------------------------------
$ga = Get-Service "QEMU-GA" -ErrorAction SilentlyContinue
if ($ga) {
    Set-Service "QEMU-GA" -StartupType Automatic
    Write-Log "QEMU guest agent startup type set to Automatic"
} else {
    Write-Log "QEMU guest agent not installed - Terraform IP discovery will fail!" "WARN"
}

# ----------------------------------------------------------
# 2. Disable Windows Update automatic restart
# ----------------------------------------------------------
$auKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
New-Item -Path $auKey -Force | Out-Null
Set-ItemProperty -Path $auKey -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWORD -Force
Set-ItemProperty -Path $auKey -Name "AUOptions"                     -Value 1 -Type DWORD -Force
Write-Log "Windows Update auto-restart disabled"

# ----------------------------------------------------------
# 3. High-performance power plan + disable sleep
# ----------------------------------------------------------
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
Write-Log "Power plan set to High Performance, sleep disabled"

# ----------------------------------------------------------
# 4. Enable RDP (registry only - firewall rule added by setup-winrm.ps1)
# ----------------------------------------------------------
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWORD -Force
Write-Log "RDP enabled (firewall rule will be applied by setup-winrm.ps1)"

# ----------------------------------------------------------
# 5. Disable Server Manager auto-open (Server SKUs only)
# ----------------------------------------------------------
if ((Get-CimInstance Win32_OperatingSystem).Caption -match 'Server') {
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1 -PropertyType DWORD -Force | Out-Null
    Write-Log "Server Manager auto-open disabled"
}

Write-Log "=== Specialize setup complete ==="
