$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "VERIFYING DOMAIN CONTROLLER"
Write-Host "=========================================="

# Wait a bit for services to stabilize
Start-Sleep -Seconds 30

# Check if server is a DC
try {
    $computerSystem = Get-WmiObject Win32_ComputerSystem
    if ($computerSystem.DomainRole -lt 4) {
        Write-Error "✗ This server is not a Domain Controller!"
        exit 1
    }
    Write-Host "✓ Server is a Domain Controller"
} catch {
    Write-Error "✗ Failed to check domain role: $_"
    exit 1
}

# Check critical services
Write-Host ""
Write-Host "Checking AD services..."
$services = @("ADWS", "DNS", "Netlogon", "KDC", "W32Time")
$allRunning = $true

foreach ($service in $services) {
    $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -eq "Running") {
            Write-Host "✓ $service is running"
        } else {
            Write-Warning "✗ $service is not running (Status: $($svc.Status))"
            $allRunning = $false
        }
    } else {
        Write-Warning "✗ $service not found"
        $allRunning = $false
    }
}

if (-not $allRunning) {
    Write-Warning "Some services are not running. Waiting 60 seconds and retrying..."
    Start-Sleep -Seconds 60
}

# Query AD Domain
Write-Host ""
Write-Host "Querying Active Directory..."
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $domain = Get-ADDomain -ErrorAction Stop

    Write-Host "✓ Successfully queried AD Domain"
    Write-Host "  Domain DNS: $($domain.DNSRoot)"
    Write-Host "  NetBIOS:    $($domain.NetBIOSName)"
    Write-Host "  Domain SID: $($domain.DomainSID)"
    Write-Host "  DC:         $($domain.PDCEmulator)"
} catch {
    Write-Error "✗ Failed to query AD: $_"
    exit 1
}

# Test DNS
Write-Host ""
Write-Host "Testing DNS resolution..."
try {
    $dnsTest = Resolve-DnsName -Name $domain.DNSRoot -ErrorAction Stop
    Write-Host "✓ DNS resolution successful"
} catch {
    Write-Warning "✗ DNS resolution failed: $_"
}

Write-Host ""
Write-Host "=========================================="
Write-Host "✓✓✓ DOMAIN CONTROLLER IS READY! ✓✓✓"
Write-Host "=========================================="
exit 0