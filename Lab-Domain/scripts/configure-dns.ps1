param(
    [Parameter(Mandatory=$true)]
    [string]$DnsServerIP
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "CONFIGURING DNS"
Write-Host "DNS Server: $DnsServerIP"
Write-Host "=========================================="

# Get all network adapters that are up
$adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}

if ($adapters.Count -eq 0) {
    Write-Error "No active network adapters found!"
    exit 1
}

foreach ($adapter in $adapters) {
    Write-Host "Configuring adapter: $($adapter.Name)"

    try {
       # Set DNS server address
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $DnsServerIP

        # Verify
        $dns = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4
        Write-Host "  ✓ DNS configured: $($dns.ServerAddresses -join ', ')"
    } catch {
        Write-Warning "  ✗ Failed to configure DNS on $($adapter.Name): $_"
    }
}

# Clear DNS cache
Write-Host ""
Write-Host "Clearing DNS cache..."
Clear-DnsClientCache
Write-Host "✓ DNS cache cleared"

# Test DNS connectivity to DC
Write-Host ""
Write-Host "Testing connectivity to DNS server..."
try {
    $ping = Test-Connection -ComputerName $DnsServerIP -Count 2 -Quiet
    if ($ping) {
        Write-Host "✓ Can reach DNS server at $DnsServerIP"
    } else {
        Write-Warning "✗ Cannot reach DNS server at $DnsServerIP"
    }
} catch {
    Write-Warning "✗ Connectivity test failed: $_"
}

Write-Host ""
Write-Host "✓ DNS configuration complete!"
exit 0
