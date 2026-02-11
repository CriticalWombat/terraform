# Join computer to Active Directory domain
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [string]$DomainUser,

    [Parameter(Mandatory=$true)]
    [string]$DomainPassword
)

$ErrorActionPreference = "Stop"

Write-Host "Attempting to join domain: $DomainName"

# Check if already domain-joined
$computerSystem = Get-WmiObject Win32_ComputerSystem
if ($computerSystem.PartOfDomain -eq $true) {
    if ($computerSystem.Domain -eq $DomainName) {
        Write-Host "Computer is already joined to $DomainName"
        exit 0
    }
    else {
        Write-Host "Computer is joined to $($computerSystem.Domain), but expected $DomainName"
    }
}

# Create credential object
$SecurePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($DomainUser, $SecurePassword)

try {
    # Join domain
    Write-Host "Joining domain $DomainName..."
    Add-Computer -DomainName $DomainName -Credential $Credential -Restart -Force

    Write-Host "Domain join initiated successfully. Computer will reboot."
    exit 0
}
catch {
    Write-Host "ERROR: Failed to join domain - $_"
    exit 1
}