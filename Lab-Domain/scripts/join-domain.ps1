param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$true)]
    [string]$DomainUser,

    [Parameter(Mandatory=$true)]
    [string]$DomainPassword
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "JOINING DOMAIN"
Write-Host "Domain: $DomainName"
Write-Host "User:   $DomainUser"
Write-Host "=========================================="

# Check if already domain joined
$computerSystem = Get-WmiObject Win32_ComputerSystem
if ($computerSystem.PartOfDomain) {
    if ($computerSystem.Domain -eq $DomainName) {
        Write-Host "✓ Already joined to domain: $($computerSystem.Domain)"
        exit 0
    } else {
        Write-Host "! Currently joined to different domain: $($computerSystem.Domain)"
        Write-Host "  Attempting to join $DomainName..."
    }
}

# Test DNS resolution to domain
Write-Host ""
Write-Host "Testing DNS resolution to domain..."
try {
    $dnsTest = Resolve-DnsName -Name $DomainName -ErrorAction Stop
    Write-Host "✓ Successfully resolved $DomainName"
    Write-Host "  IP: $($dnsTest[0].IPAddress)"
} catch {
    Write-Error "✗ Cannot resolve domain $DomainName. Check DNS configuration!"
    exit 1
}

# Create credential object
$securePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ("$DomainName\$DomainUser", $securePassword)

Write-Host ""
Write-Host "Attempting to join domain..."
Write-Host "This will take a few minutes and the computer will reboot."

try {
    Add-Computer -DomainName $DomainName `
        -Credential $credential `
        -Force `
        -Restart `
        -ErrorAction Stop

    Write-Host "✓ Domain join initiated successfully!"
    Write-Host "  Computer will reboot shortly."
} catch {
    Write-Error "✗ Failed to join domain: $_"
    Write-Error "Error details: $($_.Exception.Message)"

    # Additional troubleshooting info
    Write-Host ""
    Write-Host "Troubleshooting information:"
    Write-Host "  Computer Name: $env:COMPUTERNAME"
    Write-Host "  Current Domain: $($computerSystem.Domain)"
    Write-Host "  DNS Servers: $((Get-DnsClientServerAddress | Where-Object {$_.AddressFamily -eq 2}).ServerAddresses -join ', ')"

    exit 1
}