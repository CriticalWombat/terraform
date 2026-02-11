# Configure WinRM for Terraform connectivity
param()

$ErrorActionPreference = "Continue"

Write-Host "Configuring WinRM..."

# Enable PSRemoting
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Configure WinRM service
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true -Force
Set-Item WSMan:\localhost\Client\Auth\Basic -Value $true -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# Create self-signed certificate and HTTPS listener
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
Get-ChildItem WSMan:\Localhost\Listener | Where-Object {$_.Keys -contains "Transport=HTTPS"} | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path WSMan:\Localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force

# Configure firewall
New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5985 -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "WinRM-HTTPS" -DisplayName "WinRM HTTPS" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5986 -ErrorAction SilentlyContinue

# Set service to auto-start
Set-Service WinRM -StartupType Automatic

# Restart WinRM
Restart-Service WinRM

Write-Host "WinRM configuration complete!"