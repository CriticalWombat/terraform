param(
    [Parameter(Mandatory=$true)] [string]$DomainName,
    [Parameter(Mandatory=$true)] [string]$DomainUser,
    [Parameter(Mandatory=$true)] [string]$DomainPassword
)

$ErrorActionPreference = "Stop"

$cs = Get-WmiObject Win32_ComputerSystem
if ($cs.PartOfDomain -and $cs.Domain -eq $DomainName) {
    Write-Host "Already joined to $DomainName"
    exit 0
}

# Remove local autologin before joining
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "0"
Remove-ItemProperty -Path $regPath -Name "DefaultUserName" -ErrorAction SilentlyContinue

$secure = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
$cred   = New-Object System.Management.Automation.PSCredential($DomainUser, $secure)

# Retry the domain join — the DC may still be finishing AD service startup.
$maxAttempts = 6
$joined      = $false

for ($i = 1; $i -le $maxAttempts; $i++) {
    try {
        Write-Host "Domain join attempt $i of $maxAttempts..."
        Add-Computer -DomainName $DomainName -Credential $cred -Force -ErrorAction Stop
        $joined = $true
        Write-Host "Joined $DomainName successfully"
        break
    } catch {
        Write-Host "Attempt $i failed: $_"
        if ($i -lt $maxAttempts) {
            Write-Host "Retrying in 30 seconds..."
            Start-Sleep 30
        }
    }
}

if (-not $joined) {
    Write-Host "ERROR: Could not join $DomainName after $maxAttempts attempts"
    exit 1
}

# Schedule a reboot 15 seconds from now so Terraform receives this clean exit
# before the machine goes down. Using -Restart on Add-Computer causes an immediate
# reboot that drops the WinRM session before PowerShell can return exit 0.
Write-Host "Scheduling reboot in 15 seconds..."
& shutdown.exe /r /t 15 /c "Domain Join Reboot"
exit 0
