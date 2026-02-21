$logFile     = "C:\Windows\Temp\setup.log"
$scriptPath  = "C:\Windows\Setup\Scripts\setup.ps1"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] [Phase $Phase] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

trap {
    Write-Log "FATAL: $_" "ERROR"
    exit 1
}

# ----------------------------------------------------------
# 1. Network profile -> Private
# ----------------------------------------------------------
Write-Log "Setting network profile to Private..."
try {
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop
    Write-Log "Network profile set to Private"
} catch {
    Write-Log "Could not set network profile: $_" "WARN"
}

# ----------------------------------------------------------
# 2. Start WinRM service
# ----------------------------------------------------------
Write-Log "Setting WinRM to Automatic and starting..."
Set-Service WinRM -StartupType Automatic
Start-Service WinRM -ErrorAction SilentlyContinue
Write-Log "WinRM service started"

# ----------------------------------------------------------
# 3. Bootstrap WinRM
# ----------------------------------------------------------
Write-Log "Running winrm quickconfig..."
$qc = cmd /c winrm quickconfig -quiet -force 2>&1
Write-Log "quickconfig output: $qc"

Write-Log "Running Enable-PSRemoting..."
try {
    Start-Service MpsSvc -ErrorAction SilentlyContinue
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop
    Write-Log "PSRemoting enabled"
} catch {
    Write-Log "Enable-PSRemoting threw (may already be configured): $_" "WARN"
}

# ----------------------------------------------------------
# 4. WSMan auth and transport settings
# ----------------------------------------------------------
Write-Log "Configuring WSMan settings..."
Set-Item WSMan:\localhost\Service\AllowUnencrypted  -Value 1 -Force
Set-Item WSMan:\localhost\Service\Auth\Basic        -Value 1 -Force
Set-Item WSMan:\localhost\Client\Auth\Basic         -Value 1 -Force
Set-Item WSMan:\localhost\Client\TrustedHosts       -Value '*' -Force
Write-Log "WSMan settings configured"

# ----------------------------------------------------------
# 5. Generate self-signed cert and create HTTPS listener
# ----------------------------------------------------------
Write-Log "Generating self-signed certificate for: $env:COMPUTERNAME"

$cert = New-SelfSignedCertificate `
    -DnsName $env:COMPUTERNAME `
    -CertStoreLocation Cert:\LocalMachine\My `
    -NotAfter (Get-Date).AddYears(5)

Write-Log "Certificate created - Thumbprint: $($cert.Thumbprint), CN: $($cert.Subject)"

Write-Log "Creating HTTPS listener..."
New-Item `
    -Path WSMan:\Localhost\Listener `
    -Transport HTTPS `
    -Address * `
    -CertificateThumbPrint $cert.Thumbprint `
    -Force | Out-Null
Write-Log "HTTPS listener created"

# ----------------------------------------------------------
# 6. Firewall rules - Profile Any
# ----------------------------------------------------------
Write-Log "Creating firewall rules..."

@("WinRM-HTTP", "WinRM-HTTPS",
  "Windows Remote Management (HTTP-In)",
  "Windows Remote Management (HTTPS-In)") | ForEach-Object {
    Remove-NetFirewallRule -Name        $_ -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue
}

New-NetFirewallRule `
    -Name        "WinRM-HTTP" `
    -DisplayName "WinRM HTTP" `
    -Enabled     True `
    -Direction   Inbound `
    -Protocol    TCP `
    -Action      Allow `
    -LocalPort   5985 `
    -Profile     Any | Out-Null

New-NetFirewallRule `
    -Name        "WinRM-HTTPS" `
    -DisplayName "WinRM HTTPS" `
    -Enabled     True `
    -Direction   Inbound `
    -Protocol    TCP `
    -Action      Allow `
    -LocalPort   5986 `
    -Profile     Any | Out-Null

Write-Log "Firewall rules created (Profile: Any)"

# ----------------------------------------------------------
# 7. Restart WinRM
# ----------------------------------------------------------
Write-Log "Restarting WinRM..."
Restart-Service WinRM
Write-Log "WinRM restarted"

exit 0
