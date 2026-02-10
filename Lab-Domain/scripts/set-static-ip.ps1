param(
    [Parameter(Mandatory=$true)]
    [string]$IPAddress,

    [Parameter(Mandatory=$true)]
    [int]$PrefixLength,

    [Parameter(Mandatory=$true)]
    [string]$DefaultGateway,

    [Parameter(Mandatory=$true)]
    [string[]]$DnsServers
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "CONFIGURING STATIC IP ADDRESS"
Write-Host "IP:      $IPAddress/$PrefixLength"
Write-Host "Gateway: $DefaultGateway"
Write-Host "DNS:     $($DnsServers -join ', ')"
Write-Host "=========================================="

# Get the active network adapter
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1

if (-not $adapter) {
    Write-Error "No active network adapter found!"
    exit 1
}

Write-Host "Using adapter: $($adapter.Name)"

try {
    # Check if this IP is already configured
    $existingIP = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object {$_.IPAddress -eq $IPAddress}

    if ($existingIP) {
        Write-Host "✓ IP $IPAddress is already configured on this adapter"
    } else {
        Write-Host "Removing existing IP configuration..."

        # Remove all existing IPv4 addresses
        Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

        # Remove existing default gateway
        Get-NetRoute -InterfaceAlias $adapter.Name -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        Write-Host "Setting new IP address..."

        # Set new IP address
        New-NetIPAddress -InterfaceAlias $adapter.Name `
                        -IPAddress $IPAddress `
                        -PrefixLength $PrefixLength `
                        -DefaultGateway $DefaultGateway `
                        -ErrorAction Stop

        Write-Host "✓ IP address set successfully"
    }

    # Set DNS servers
    Write-Host "Setting DNS servers..."
    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $DnsServers

    # Verify configuration
    $newIP = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4
    $newDNS = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4
    $newGW = Get-NetRoute -InterfaceAlias $adapter.Name -DestinationPrefix "0.0.0.0/0"

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "✓ CONFIGURATION COMPLETE"
    Write-Host "=========================================="
    Write-Host "IP Address: $($newIP.IPAddress)/$($newIP.PrefixLength)"
    Write-Host "Gateway:    $($newGW.NextHop)"
    Write-Host "DNS:        $($newDNS.ServerAddresses -join ', ')"
    Write-Host "=========================================="

    # Clear DNS cache
    Clear-DnsClientCache

    exit 0

} catch {
    Write-Error "Failed to configure network: $_"
    Write-Error "Error details: $($_.Exception.Message)"
    exit 1
}