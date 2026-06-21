param(
    [Parameter(Mandatory=$true)] [string]$DomainName,
    [Parameter(Mandatory=$true)] [string]$NetBiosName,
    [Parameter(Mandatory=$true)] [string]$SafeModePassword
)

$ErrorActionPreference = "Stop"

$role = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($role -ge 4) { Write-Host "Already a Domain Controller"; exit 0 }

if ((Get-WindowsFeature AD-Domain-Services).InstallState -ne 'Installed') {
    Write-Host "Installing AD DS role..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
    Write-Host "AD DS role installed"
}

$secure = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

Write-Host "Promoting to Domain Controller for forest: $DomainName"
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBiosName `
    -DomainMode WinThreshold `
    -ForestMode WinThreshold `
    -InstallDns:$true `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword $secure `
    -NoRebootOnCompletion:$true `
    -Force:$true

# Schedule a reboot 15 seconds from now so Terraform receives this clean exit
# before the machine goes down. -NoRebootOnCompletion:$true above prevents the
# cmdlet from rebooting immediately, which would drop the WinRM session mid-script
# and cause Terraform to treat the resource as failed.
Write-Host "Promotion complete. Scheduling reboot in 15 seconds..."
& shutdown.exe /r /t 15 /c "DC Promotion Reboot"
exit 0
