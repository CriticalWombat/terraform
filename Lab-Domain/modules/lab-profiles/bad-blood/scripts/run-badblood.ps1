#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ----------------------------------------------------------
# 1. Wait for AD services
#    The DC may still be finishing startup after the promotion
#    reboot. Poll each critical service with a 10-minute deadline,
#    then verify AD is actually queryable before proceeding.
# ----------------------------------------------------------
Write-Host "Waiting for AD services to be ready..."

$services = "ADWS", "DNS", "Netlogon", "KDC"
foreach ($svc in $services) {
    $deadline = (Get-Date).AddMinutes(10)
    $ready    = $false
    while ((Get-Date) -lt $deadline) {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq "Running") { $ready = $true; break }
        Write-Host "  [$svc] not ready, waiting 15s..."
        Start-Sleep 15
    }
    if (-not $ready) {
        Write-Host "ERROR: Service '$svc' did not reach Running state within 10 minutes"
        exit 1
    }
    Write-Host "  [$svc] Running"
}

# Verify AD is actually queryable (services running != AD fully initialised)
Write-Host "Verifying AD is queryable..."
$adReady  = $false
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    try {
        $null = Get-ADDomain -ErrorAction Stop
        $adReady = $true
        break
    } catch {
        Write-Host "  AD not yet queryable, waiting 15s..."
        Start-Sleep 15
    }
}
if (-not $adReady) {
    Write-Host "ERROR: AD did not become queryable within 5 minutes of services starting"
    exit 1
}
Write-Host "AD is queryable - proceeding with BadBlood"

# ----------------------------------------------------------
# 2. Download BadBlood
# ----------------------------------------------------------
$dest = "C:\setup\BadBlood"

if (-not (Test-Path "$dest\Invoke-BadBlood.ps1")) {
    Write-Host "Downloading BadBlood..."
    $zip = "C:\setup\badblood.zip"

    # Suppress progress bar - rendering it over a WinRM session stalls the download
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest `
        -Uri "https://github.com/davidprowe/BadBlood/archive/refs/heads/master.zip" `
        -OutFile $zip `
        -UseBasicParsing
    $ProgressPreference = 'Continue'

    if (-not (Test-Path $zip) -or (Get-Item $zip).Length -eq 0) {
        Write-Host "ERROR: BadBlood zip was not downloaded or is empty"
        exit 1
    }
    Write-Host "Downloaded $([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB"

    Write-Host "Extracting..."
    Expand-Archive -Path $zip -DestinationPath "C:\setup" -Force
    if (Test-Path "C:\setup\BadBlood-master") {
        Rename-Item "C:\setup\BadBlood-master" $dest
    }
    Remove-Item $zip -ErrorAction SilentlyContinue

    if (-not (Test-Path "$dest\Invoke-BadBlood.ps1")) {
        Write-Host "ERROR: Extraction did not produce expected file at $dest\Invoke-BadBlood.ps1"
        exit 1
    }
}

# ----------------------------------------------------------
# 3. Run BadBlood
# ----------------------------------------------------------
Write-Host "Running BadBlood - this may take 10-20 minutes..."
Push-Location $dest
.\Invoke-BadBlood.ps1 -UserCount 1000 -GroupCount 200 -ComputerCount 50 -NonInteractive
Pop-Location

Write-Host "BadBlood complete. AD is now populated with vulnerable objects."
