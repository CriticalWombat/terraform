# Promote server to Domain Controller
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [string]$NetBiosName,

    [Parameter(Mandatory=$true)]
    [string]$SafeModePassword
)

$ErrorActionPreference = "Stop"

Write-Host "Starting DC promotion for domain: $DomainName"

# Check if already a DC
$domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($domainRole -ge 4) {
    Write-Host "This server is already a Domain Controller"
    exit 0
}

# Convert safe mode password to secure string
$SecureSafeModePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

try {
    # Install AD DS Forest
    Write-Host "Installing AD DS Forest..."
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetBiosName `
        -DomainMode "WinThreshold" `
        -ForestMode "WinThreshold" `
        -InstallDns:$true `
        -CreateDnsDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -LogPath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -SafeModeAdministratorPassword $SecureSafeModePassword `
        -NoRebootOnCompletion:$false `
        -Force:$true

    Write-Host "DC promotion initiated successfully. Server will reboot."
    exit 0
}
catch {
    Write-Host "ERROR: DC promotion failed - $_"
    exit 1
}