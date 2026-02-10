# Configure WinRM for Terraform remote-exec
$ErrorActionPreference = "SilentlyContinue"

Write-Host "Configuring WinRM..."

# Enable PSRemoting
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Configure WinRM service
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true -Force
Set-Item WSMan:\localhost\Client\Auth\Basic -Value $true -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# Create self-signed certificate for HTTPS
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME `
    -CertStoreLocation Cert:\LocalMachine\My `
    -FriendlyName "WinRM Certificate"

# Create HTTPS listener (remove existing first)
Get-ChildItem WSMan:\Localhost\Listener | Where-Object {$_.Keys -contains "Transport=HTTPS"} | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$null = New-Item -Path WSMan:\Localhost\Listener `
    -Transport HTTPS `
    -Address * `
    -CertificateThumbPrint $cert.Thumbprint `
    -Force

# Configure firewall
New-NetFirewallRule -Name "WinRM-HTTP" `
    -DisplayName "WinRM HTTP" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -Action Allow `
    -LocalPort 5985 `
    -ErrorAction SilentlyContinue

New-NetFirewallRule -Name "WinRM-HTTPS" `
    -DisplayName "WinRM HTTPS" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -Action Allow `
    -LocalPort 5986 `
    -ErrorAction SilentlyContinue

# Restart WinRM
Restart-Service WinRM

Write-Host "✓ WinRM configuration complete!"