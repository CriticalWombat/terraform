param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [string]$NetBiosName,

    [Parameter(Mandatory=$true)]
    [string]$SafeModePassword
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "DC PROMOTION SCRIPT"
Write-Host "Domain: $DomainName"
Write-Host "NetBIOS: $NetBiosName"
Write-Host "=========================================="

# Check if already a DC
try {
    $computerSystem = Get-WmiObject Win32_ComputerSystem
    $domainRole = $computerSystem.DomainRole

    if ($domainRole -ge 4) {
        Write-Host "✓ This server is already a Domain Controller"
        Write-Host "  Domain: $($computerSystem.Domain)"
        exit 0
    }
} catch {
    Write-Host "Server is not yet a DC. Proceeding with promotion..."
}

# Convert password to secure string
$securePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

Write-Host ""
Write-Host "Promoting to Domain Controller..."
Write-Host "This will take 10-20 minutes and the server will reboot."
Write-Host ""

try {
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetBiosName `
        -SafeModeAdministratorPassword $securePassword `
        -InstallDns:$true `
        -CreateDnsDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -LogPath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -DomainMode "WinThreshold" `
        -ForestMode "WinThreshold" `
        -Force:$true `
        -NoRebootOnCompletion:$false

    Write-Host "✓ DC promotion initiated. Server will reboot."
} catch {
    Write-Error "✗ Failed to promote DC: $_"
    Write-Error "Error details: $($_.Exception.Message)"
    exit 1
}