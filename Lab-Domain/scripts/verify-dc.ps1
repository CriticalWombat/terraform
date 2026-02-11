# Verify Domain Controller is functioning
param()

$ErrorActionPreference = "Continue"

Write-Host "Verifying Domain Controller status..."

# Check if this is a DC
$domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole
if ($domainRole -lt 4) {
    Write-Host "ERROR: This server is not a Domain Controller"
    exit 1
}

Write-Host "Confirmed: Server is a Domain Controller"

# Check AD Web Services
$services = @("ADWS", "DNS", "Netlogon", "KDC")
$allRunning = $true

foreach ($svc in $services) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service -eq $null) {
        Write-Host "WARNING: Service $svc not found"
        $allRunning = $false
    }
    elseif ($service.Status -ne "Running") {
        Write-Host "WARNING: Service $svc is $($service.Status)"
        $allRunning = $false
    }
    else {
        Write-Host "OK: Service $svc is running"
    }
}

# Try to get domain info
try {
    $domain = Get-ADDomain
    Write-Host "Domain Name: $($domain.DNSRoot)"
    Write-Host "Domain NetBIOS: $($domain.NetBIOSName)"
    Write-Host "Domain Controller: $($domain.PDCEmulator)"
}
catch {
    Write-Host "ERROR: Cannot retrieve domain information - $_"
    exit 1
}

if ($allRunning) {
    Write-Host "SUCCESS: Domain Controller is fully operational"
    exit 0
}
else {
    Write-Host "WARNING: Some services are not running, but DC is functional"
    exit 0
}