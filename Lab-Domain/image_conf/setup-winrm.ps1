# setup-winrm.ps1 - runs once on first clone boot via the FirstBootWinRM scheduled task.
# The task is registered by Prepare-Template.ps1 before sysprep and survives
# generalization because it runs as SYSTEM (a well-known SID that is not remapped).
# By the time this task fires all Windows services are fully started, so WinRM,
# the Windows Firewall (MpsSvc), and the guest agent can all be configured reliably.
# Deletes the FirstBootWinRM task when done - it is a one-shot operation.
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

Write-Log "=== WinRM first-boot setup starting on $env:COMPUTERNAME ==="

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
# 2. QEMU guest agent - start service (startup type was set during specialize)
# ----------------------------------------------------------
$ga = Get-Service "QEMU-GA" -ErrorAction SilentlyContinue
if ($ga) {
    Start-Service "QEMU-GA" -ErrorAction SilentlyContinue
    Write-Log "QEMU guest agent started"
} else {
    Write-Log "QEMU guest agent not installed - Terraform IP discovery will fail!" "WARN"
}

# ----------------------------------------------------------
# 3. RDP firewall rule (MpsSvc is running by the time this task fires)
# ----------------------------------------------------------
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
Write-Log "RDP firewall rule enabled"

# ----------------------------------------------------------
# 4. WinRM service
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
# 5. Firewall rule for WinRM HTTP
# ----------------------------------------------------------
@("WinRM-HTTP", "Windows Remote Management (HTTP-In)") |
    ForEach-Object {
        Remove-NetFirewallRule -Name        $_ -ErrorAction SilentlyContinue
        Remove-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue
    }

New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5985 -Profile Any | Out-Null
Write-Log "WinRM firewall rule created (port 5985)"

# ----------------------------------------------------------
# 6. Restart WinRM to apply all changes
# ----------------------------------------------------------
Restart-Service WinRM
Write-Log "=== WinRM setup complete - HTTP ready on port 5985 ==="

# ----------------------------------------------------------
# 7. Remove this scheduled task - one-shot, never needs to run again
# ----------------------------------------------------------
Unregister-ScheduledTask -TaskName 'FirstBootWinRM' -Confirm:$false -ErrorAction SilentlyContinue
Write-Log "FirstBootWinRM scheduled task removed"
