# Windows 10 VM Template for Proxmox 9 with Terraform

Complete guide for creating a production-ready Windows 10 template on Proxmox 9 that fully automates OOBE, includes VirtIO drivers, supports Cloudbase-Init for post-deployment configuration, and integrates seamlessly with Terraform for infrastructure-as-code deployments.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Phase 1: Create Initial VM](#phase-1-create-initial-vm)
- [Phase 2: Install Windows](#phase-2-install-windows)
- [Phase 3: Install VirtIO Drivers](#phase-3-install-virtio-drivers)
- [Phase 4: Install Cloudbase-Init](#phase-4-install-cloudbase-init)
- [Phase 5: Prepare Windows for Sysprep](#phase-5-prepare-windows-for-sysprep)
- [Phase 6: Create Sysprep Answer File](#phase-6-create-sysprep-answer-file)
- [Phase 7: Run Sysprep](#phase-7-run-sysprep)
- [Phase 8: Convert to Template](#phase-8-convert-to-template)
- [Phase 9: Test the Template](#phase-9-test-the-template)
- [Using Template with Terraform](#using-template-with-terraform)
- [Performance Optimization](#performance-optimization)
- [Exporting Templates](#exporting-templates)
- [Windows 11 Differences](#windows-11-differences)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide creates a fully automated Windows 10 VM template that:
- ✅ Skips all OOBE (Out-of-Box Experience) prompts
- ✅ Uses VirtIO drivers for optimal performance
- ✅ Includes QEMU Guest Agent for Proxmox integration
- ✅ Supports Cloudbase-Init for cloud-like automation
- ✅ Generates unique SIDs for each clone
- ✅ Enables RDP by default
- ✅ Works seamlessly with Terraform

**Time to complete:** 45-60 minutes  

---

## Prerequisites

### Required Downloads

1. **Windows 10 ISO**
   - Download from [Microsoft](https://www.microsoft.com/software-download/windows10)
   - Use evaluation version or your licensed copy

2. **VirtIO Drivers ISO**
   - Download from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
   - Latest stable version recommended

3. **Cloudbase-Init**
   - Download from: https://cloudbase.it/cloudbase-init/
   - Get the latest MSI installer

### Proxmox Requirements

- Proxmox VE 9.x
- Sufficient storage for template (minimum 32GB recommended)
- Network connectivity to download required files
- SSH access to Proxmox host

### Upload ISOs to Proxmox

```bash
# Option 1: Via web UI
# Navigate to: Datacenter → Storage → local → ISO Images → Upload

# Option 2: Via command line
# SSH into Proxmox node
cd /var/lib/vz/template/iso/

# Upload ISOs here via SCP from your workstation:
# scp Win10_*.iso root@proxmox-ip:/var/lib/vz/template/iso/
# scp virtio-win.iso root@proxmox-ip:/var/lib/vz/template/iso/
```

---

## Phase 1: Create Initial VM

Create the base VM with VirtIO devices for optimal performance.

```bash
# SSH into Proxmox node

# Create VM (use high VM ID for templates, e.g., 9000+)
qm create 9000 \
  --name win10-template \
  --memory 4096 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0

# Configure VirtIO SCSI storage controller
qm set 9000 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:32,cache=writeback,discard=on,ssd=1

# Attach Windows ISO as primary boot device
qm set 9000 \
  --ide2 local:iso/Win10_EnglishInternational_x64.iso,media=cdrom

# Attach VirtIO drivers ISO
qm set 9000 \
  --ide0 local:iso/virtio-win.iso,media=cdrom

# Set boot order
qm set 9000 --boot order=scsi0;ide2

# Set OS type
qm set 9000 --ostype win10

# Enable QEMU Guest Agent
qm set 9000 --agent enabled=1

# Start the VM
qm start 9000
```

**Notes:**
- Adjust `local-lvm` to match your storage name (`pvesm status` to list)
- Adjust `vmbr0` to match your network bridge
- ISO filenames may differ based on your downloads

---

## Phase 2: Install Windows
1. **Disconnect vNIC from VM**
   - This ensures you can create a local account during setup.
1. **Connect to VM Console**
   - Open Proxmox web UI
   - Navigate to VM 9000 → Console

2. **Boot from Windows ISO**
   - Press any key when prompted

3. **Load VirtIO SCSI Driver**
   - Proceed through initial setup screens
   - When prompted **"Where do you want to install Windows?"**
   - **No drives will be visible initially**
   - Click **"Load driver"**
   - Click **"Browse"**
   - Navigate to: **CD Drive (virtio-win)** → **amd64** → **w10**
   - Select **"Red Hat VirtIO SCSI controller"**
   - Click **OK** and **Next**
   - Disk should now appear

4. **Complete Installation**
   - Select the disk and click **Next**
   - Windows will install (15-20 minutes)
   - System will reboot automatically

5. **Initial Windows Setup**
   - Choose your region/keyboard layout
   - **Select "I don't have internet"** or skip network setup
   - **Use local account** (do not use Microsoft account for templates)
   - Create a temporary username (e.g., "TempUser")
   - Set a temporary password
   - Decline/skip all privacy options
   - Let Windows complete first-run setup

---

## Phase 3: Install VirtIO Drivers

After Windows boots, install the complete VirtIO driver package.

### Install Full Driver Package

1. **Open File Explorer**
2. **Navigate to CD Drive (virtio-win)**
3. **Run installers:**
   - `virtio-win-gt-x64.exe`
   - `virtio-win-guest-tools.exe`
4. **Install with default options**
5. **Reboot when prompted**

**Drivers installed:**
- VirtIO Network Driver (NetKVM)
- VirtIO Balloon Driver (memory management)
- VirtIO SCSI Driver (storage)
- QEMU Guest Agent
- VirtIO Serial Driver
- Display adapter

### Verify Installation

```powershell
# Open PowerShell as Administrator

# Verify QEMU Guest Agent is running
Get-Service QEMU-GA

# Check Device Manager for unknown devices
devmgmt.msc
# Should show no yellow exclamation marks
```

---

## Phase 4: Install Cloudbase-Init

Cloudbase-Init provides cloud-init-like functionality for Windows, enabling automated configuration on first boot.

### Installation Steps

1. **Download installer** (if not already downloaded)
   - https://cloudbase.it/cloudbase-init/

2. **Run MSI installer**
   - Right-click → Run as Administrator

3. **Configure during installation:**
   - **Username:** `Administrator`
   - **Serial port for logging:** Leave default
   - **IMPORTANT:** **UNCHECK** "Run Sysprep"
   - **IMPORTANT:** **UNCHECK** "Shutdown when Sysprep finishes"
   - **Optional:** Check "Use metadata password" for password injection
   - Click **Install**

4. **Complete installation**
   - Click **Finish**
   - Do NOT let it run sysprep yet

### Configure Cloudbase-Init

Edit the configuration file:

**File location:** `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf`

```ini
[DEFAULT]
username=Admin
groups=Administrators
inject_user_password=true
first_logon_behaviour=no

bsdtar_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\bsdtar.exe
mtools_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\

log-dir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
log-file=cloudbase-init.log
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN

local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\

metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService

plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,
        cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,
        cloudbaseinit.plugins.windows.createuser.CreateUserPlugin,
        cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,
        cloudbaseinit.plugins.common.userdata.UserDataPlugin,
        cloudbaseinit.plugins.common.localscripts.LocalScriptsPlugin

verbose=true
debug=true
```

**Key settings explained:**
- `username=Administrator` - Account to manage
- `inject_user_password=true` - Allow password injection from metadata
- `first_logon_behaviour=no` - Don't modify logon behavior

---

## Phase 5: Prepare Windows for Sysprep
### Set Execution Policy
```powershell
# Run Powershell as Administrator
Set-ExecutionPolicy Bypass -Scope LocalMachine -Force

# Verify
Get-ExecutionPolicy -List

# LocalMachine should show: Bypass
```
Optimize and clean the system before running sysprep.

### Install Windows Updates (Recommended)

```powershell
# Open Settings → Update & Security → Windows Update
# Install all available updates
# Reboot as necessary
# Check for updates again after every reboot until up to date
```

### System Optimization

```powershell
# Run PowerShell as Administrator

# Disable hibernation (saves disk space)
powercfg /hibernate off

# Clear temporary files
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Clear user temp files
Remove-Item -Path "C:\Users\*\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Run Disk Cleanup
cleanmgr /sagerun:1

# Optional: Remove Store apps that can block sysprep
Get-AppxPackage -AllUsers | Where-Object {$_.IsFramework -eq $false} | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
```

### Additional Cleanup (Optional)

```powershell
# Clear Windows Update cache
Stop-Service wuauserv
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service wuauserv

# Clear event logs
wevtutil el | Foreach-Object {wevtutil cl "$_"}

# Defragment (for HDD, skip for SSD)
Optimize-Volume -DriveLetter C -Defrag -Verbose

# Zero out free space (helps with compression, takes time)
# Download SDelete from Sysinternals first
# sdelete -z C:
```

---

## Phase 6: Create Sysprep Answer File

The unattend.xml file automates OOBE and configures the system on first boot.

### Create Answer File

**File location:** `C:\Windows\System32\Sysprep\unattend.xml`

Open Notepad as Administrator and create this file:

```xml
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend"
         xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">

    <!-- Settings for the generalize pass -->
    <settings pass="generalize">
        <component name="Microsoft-Windows-PnpSysprep" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <PersistAllDeviceInstalls>true</PersistAllDeviceInstalls>
        </component>
        <component name="Microsoft-Windows-Security-SPP" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SkipRearm>1</SkipRearm>
        </component>
    </settings>

    <!-- Settings for the specialize pass -->
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <ComputerName>*</ComputerName>
            <TimeZone>Eastern Standard Time</TimeZone>
        </component>
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>net user Administrator /active:yes</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>

    <!-- Settings for the OOBE pass - Skips all OOBE questions -->
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">

            <!-- Auto logon configuration (optional) -->
            <AutoLogon>
                <Password>
                    <Value>ChangeMe123!</Value>
                    <PlainText>true</PlainText>
                </Password>
                <Enabled>true</Enabled>
                <Username>Administrator</Username>
            </AutoLogon>

            <!-- Administrator account password -->
            <UserAccounts>
                <AdministratorPassword>
                    <Value>ChangeMe123!</Value>
                    <PlainText>true</PlainText>
                </AdministratorPassword>
            </UserAccounts>

            <!-- Skip OOBE screens -->
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>3</ProtectYourPC>
                <SkipUserOOBE>true</SkipUserOOBE>
                <SkipMachineOOBE>true</SkipMachineOOBE>
            </OOBE>

            <!-- First logon commands -->
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0"</CommandLine>
                    <Description>Enable RDP</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'"</CommandLine>
                    <Description>Enable RDP Firewall Rule</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <CommandLine>cmd /c "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\Scripts\cloudbase-init.exe" --config-file "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf"</CommandLine>
                    <Description>Run Cloudbase-Init</Description>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>

        <!-- International settings -->
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
    </settings>
</unattend>
```

### Customization Options

**CRITICAL:** Change these values:
- `<Value>ChangeMe123!</Value>` - Replace with your desired Administrator password (appears twice)

**Optional customizations:**
- `<TimeZone>UTC</TimeZone>` - Change to your timezone
  - Examples: `Eastern Standard Time`, `Pacific Standard Time`, `Central Europe Standard Time`
- `<InputLocale>en-US</InputLocale>` - Change locale if not US English
- `<AutoLogon><Enabled>true</Enabled>` - Set to `false` to disable auto-logon
- Remove FirstLogonCommands if you don't want RDP enabled by default

**Timezone reference:**
```powershell
# List all available timezones in Windows
tzutil /l
```

---

## Phase 7: Run Sysprep

### Prepare for Sysprep (If Re-running)

If you're running sysprep again after a previous attempt:

```powershell
# Run PowerShell as Administrator

# Remove sysprep success tag
Remove-Item "C:\Windows\System32\Sysprep\Panther\*" -Recurse -Force -ErrorAction SilentlyContinue

# Reset sysprep state
Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7 -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "CleanupState" -Value 2 -Force -ErrorAction SilentlyContinue

# Reset rearm counter (allows more sysprep runs)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" -Name "SkipRearm" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
```

### Execute Sysprep

```powershell
# Run PowerShell as Administrator

# Verify unattend.xml exists
Test-Path "C:\Windows\System32\Sysprep\unattend.xml"
# Should return: True

# Run sysprep with unattend file
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:C:\Windows\System32\Sysprep\unattend.xml
```

**What happens:**
1. Sysprep window opens
2. System generalizes (removes machine-specific data)
3. VM automatically shuts down (takes 5-10 minutes)
4. **Do NOT interact with the VM during this process**

### If Sysprep Fails

Check the logs:

```powershell
# View error log
Get-Content "C:\Windows\System32\Sysprep\Panther\setuperr.log" -Tail 50

# View action log
Get-Content "C:\Windows\System32\Sysprep\Panther\setupact.log" -Tail 50
```

Common issues:
- Windows Store apps blocking sysprep (run the removal command from Phase 5)
- Previous sysprep run didn't complete (run cleanup commands above)
- Pending Windows updates (install all updates first)

---

## Phase 8: Convert to Template

Once the VM has shut down after sysprep:

```bash
# SSH into Proxmox node

# Verify VM is stopped
qm status 9000
# Should show: status: stopped

# Convert VM to template
qm template 9000

# Verify template was created
qm list | grep 9000
# Should show template in the list
```

**Important notes:**
- Once converted to template, VM cannot be started directly
- Template must be cloned to create new VMs
- Template disk becomes read-only (base disk)

---

## Phase 9: Test the Template

Always test your template before production use.

### Clone and Start Test VM

```bash
# Clone the template (full clone for testing)
qm clone 9000 1000 --name test-win10 --full

# Start the test VM
qm start 1000

# Watch console (via Proxmox web UI)
# VM 1000 → Console
```

### Expected Behavior

✅ **Correct behavior:**
1. VM boots
2. Brief "Getting devices ready" screen
3. Boots directly to Windows login screen
4. **No OOBE questions asked**
5. Administrator account available
6. Login with password from unattend.xml

❌ **If OOBE appears:**
- Unattend.xml was not properly applied
- Sysprep may have failed
- Check logs in the template before it was sysprepped

### Clean Up Test VM

```bash
# Once verified, remove test VM
qm stop 1000
qm destroy 1000
```

---

## Using Template with Terraform

### Setup Terraform with Proxmox

#### Install Terraform

```bash
# On your workstation (not Proxmox)
# Download from: https://www.terraform.io/downloads

# Verify installation
terraform version
```

#### Create Proxmox API Token

```bash
# SSH into Proxmox node

# Create Terraform role with necessary permissions
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

# Create Terraform user
pveum user add terraform@pve

# Assign role to user
pveum aclmod / -user terraform@pve -role TerraformProv

# Create API token (save the secret shown - it's only displayed once!)
pveum user token add terraform@pve provider --privsep=0
```

### Example Terraform Configurations

#### Single VM Deployment

Create `main.tf`:

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.45"
    }
  }
}

provider "proxmox" {
  endpoint = "https://your-proxmox-ip:8006"
  username = "terraform@pve"
  password = "your-token-secret-here"
  insecure = true  # Set to false with valid SSL cert
  
  ssh {
    agent    = true
    username = "root"
  }
}

resource "proxmox_virtual_environment_vm" "windows_vm" {
  name      = "my-windows-vm"
  node_name = "pve"
  
  clone {
    vm_id = 9000  # Your template ID
    full  = true  # Full clone (independent of template)
  }
  
  cpu {
    cores = 2
    type  = "host"
  }
  
  memory {
    dedicated = 4096
  }
  
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }
  
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 40
    cache        = "writeback"
    discard      = "on"
    ssd          = true
  }
  
  agent {
    enabled = true
  }
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.windows_vm.id
}
```

#### Multiple VMs with Count

```hcl
resource "proxmox_virtual_environment_vm" "windows_vm" {
  count = 4  # Create 4 VMs
  
  name      = "win10-vm-${count.index + 1}"
  node_name = "pve"
  
  clone {
    vm_id = 9000
    full  = false  # Linked clone (much faster!)
  }
  
  cpu {
    cores = 2
  }
  
  memory {
    dedicated = 4096
  }
  
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }
  
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 40
  }
  
  agent {
    enabled = true
  }
}

output "vm_ids" {
  value = {
    for idx, vm in proxmox_virtual_environment_vm.windows_vm : 
    vm.name => vm.id
  }
}
```

#### Multiple VMs with Different Configurations

```hcl
locals {
  vms = {
    web-server = {
      cores  = 4
      memory = 8192
      disk   = 60
    }
    app-server = {
      cores  = 2
      memory = 4096
      disk   = 40
    }
    db-server = {
      cores  = 4
      memory = 16384
      disk   = 100
    }
  }
}

resource "proxmox_virtual_environment_vm" "windows_vm" {
  for_each = local.vms
  
  name      = each.key
  node_name = "pve"
  
  clone {
    vm_id = 9000
    full  = false  # Linked clone
  }
  
  cpu {
    cores = each.value.cores
  }
  
  memory {
    dedicated = each.value.memory
  }
  
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }
  
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk
  }
  
  agent {
    enabled = true
  }
}
```

### Deploy with Terraform

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy VMs
terraform apply

# For faster parallel deployment
terraform apply -parallelism=20

# Destroy all VMs
terraform destroy
```

---

## Exporting Templates

### Method 1: Backup and Restore (Recommended)

**On source Proxmox:**

```bash
# Create backup
vzdump 9000 --dumpdir /var/lib/vz/dump --compress zstd --mode snapshot

# List backup
ls -lh /var/lib/vz/dump/vzdump-qemu-9000-*

# Transfer to destination
rsync -avP /var/lib/vz/dump/vzdump-qemu-9000-*.vma.zst root@dest-ip:/var/lib/vz/dump/
```

**On destination Proxmox:**

```bash
# Restore backup
qmrestore /var/lib/vz/dump/vzdump-qemu-9000-*.vma.zst 9000 --storage local-lvm

# Convert to template
qm template 9000

# Clean up
rm /var/lib/vz/dump/vzdump-qemu-9000-*.vma.zst
```

### Method 2: Manual Disk Export

**On source:**

```bash
# Export VM config
qm config 9000 > /tmp/vm-9000.conf

# Export disk
qm disk export 9000 scsi0 /tmp/win10-template.qcow2 --format qcow2

# Transfer files
scp /tmp/vm-9000.conf root@dest-ip:/tmp/
scp /tmp/win10-template.qcow2 root@dest-ip:/tmp/
```

**On destination:**

```bash
# Create VM
qm create 9000 --name win10-template --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0
qm set 9000 --scsihw virtio-scsi-pci --ostype win10 --agent enabled=1

# Import disk
qm disk import 9000 /tmp/win10-template.qcow2 local-lvm

# Attach disk
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0

# Set boot order
qm set 9000 --boot order=scsi0

# Convert to template
qm template 9000
```

---

## Windows 11 Differences

Windows 11 requires UEFI, TPM 2.0, and Secure Boot configuration.

### VM Creation for Windows 11

```bash
qm create 9001 --name win11-template --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0

# CRITICAL: Set machine type to q35
qm set 9001 --machine q35

# Use UEFI BIOS
qm set 9001 --bios ovmf

# Add EFI disk
qm set 9001 --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=0

# Add TPM 2.0 (required for Windows 11)
qm set 9001 --tpmstate0 local-lvm:1,version=v2.0

# Configure storage
qm set 9001 --scsihw virtio-scsi-pci --scsi0 local-lvm:40,cache=writeback,discard=on,ssd=1

# Attach ISOs
qm set 9001 --ide2 local:iso/Win11_EnglishInternational_x64.iso,media=cdrom
qm set 9001 --ide0 local:iso/virtio-win.iso,media=cdrom

# Set boot order
qm set 9001 --boot order=scsi0;ide2

# Set OS type
qm set 9001 --ostype win11

# Enable agent
qm set 9001 --agent enabled=1
```

### Windows 11 Unattend.xml Additions

Add to the `<OOBE>` section:

```xml
<OOBE>
    <HideEULAPage>true</HideEULAPage>
    <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
    <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
    <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
    <HideLocalAccountScreen>true</HideLocalAccountScreen>
    <ProtectYourPC>3</ProtectYourPC>
    <SkipUserOOBE>true</SkipUserOOBE>
    <SkipMachineOOBE>true</SkipMachineOOBE>
</OOBE>
```

### Terraform for Windows 11

```hcl
resource "proxmox_virtual_environment_vm" "windows11_vm" {
  name      = "win11-vm"
  node_name = "pve"
  
  machine = "q35"  # Required for Windows 11
  
  bios = "ovmf"    # UEFI
  
  efi_disk {
    datastore_id = "local-lvm"
    type         = "4m"
  }
  
  tpm_state {
    datastore_id = "local-lvm"
    version      = "v2.0"
  }
  
  clone {
    vm_id = 9001
    full  = false
  }
  
  # ... rest of configuration
}
```

---

## Troubleshooting

### Template Won't Start - Permission Denied

**Issue:**
```
The device is not writable: Permission denied
```

**Solution:**
Templates cannot be started directly. You must clone first:

```bash
qm clone 9000 1000 --name test --full
qm start 1000
```

### OOBE Still Appears After Cloning

**Causes:**
- Unattend.xml missing or incorrect
- Sysprep didn't complete successfully
- Wrong file location

**Solution:**

1. Check unattend.xml exists in template (before converting to template):
```powershell
Test-Path "C:\Windows\System32\Sysprep\unattend.xml"
```

2. Verify XML syntax (missing `xmlns:wcm` namespace is common):
```xml
<unattend xmlns="urn:schemas-microsoft-com:unattend"
         xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
```

3. Check sysprep logs:
```powershell
Get-Content "C:\Windows\System32\Sysprep\Panther\setuperr.log"
```

### Network Not Working

**Causes:**
- VirtIO network driver not installed
- QEMU Guest Agent not running
- Wrong bridge configuration

**Solution:**

```powershell
# Check network adapter
Get-NetAdapter

# Verify QEMU Guest Agent
Get-Service QEMU-GA
# If stopped:
Start-Service QEMU-GA
Set-Service QEMU-GA -StartupType Automatic

# Reinstall VirtIO network driver if needed
# Mount virtio-win ISO and run installer
```

### Cloudbase-Init Not Running

**Check service:**
```powershell
Get-Service cloudbase-init
```

**Check logs:**
```powershell
Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log" -Tail 50
```

**Common issues:**
- Service not set to automatic
- Configuration file syntax errors
- FirstLogonCommands not configured in unattend.xml

**Solution:**
```powershell
# Set service to automatic
Set-Service cloudbase-init -StartupType Automatic

# Manually run to test
& "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\Scripts\cloudbase-init.exe" --config-file "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf"
```

### Duplicate SIDs After Cloning

**Cause:**
Sysprep was not run or didn't complete.

**Verification:**
```powershell
whoami /user
# Compare SID between VMs - should be different
```

**Solution:**
Must recreate template following all sysprep steps.

### Sysprep Failed

**Check logs:**
```powershell
Get-Content "C:\Windows\System32\Sysprep\Panther\setuperr.log" -Tail 50
```

**Common causes:**

1. **Windows Store apps blocking:**
```powershell
Get-AppxPackage -AllUsers | Where-Object {$_.IsFramework -eq $false} | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
```

2. **Previous sysprep didn't complete:**
```powershell
Remove-Item "C:\Windows\System32\Sysprep\Panther\*" -Recurse -Force
```

3. **Hit sysprep limit (3-8 times):**
```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\Setup\Status\SysprepStatus" -Name "GeneralizationState" -Value 7 -Force
```

### Terraform Provider Issues

**Proxmox 9 compatibility:**
Older Telmate provider may not work with Proxmox 9. Use bpg provider:

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.45"
    }
  }
}
```

**API permission errors:**
Ensure proper permissions (no `VM.Monitor` in Proxmox 9):

```bash
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"
```

### RDP Not Enabled

**Check RDP status:**
```powershell
Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections
# Should be 0 (enabled)
```

**Enable manually:**
```powershell
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

### Slow Clone Performance

**Solutions:**
1. Use linked clones (`full = false`)
2. Move template to faster storage (NVMe/SSD)
3. Use ZFS storage
4. Enable optimal cache settings (`cache=writeback`)
5. Increase Terraform parallelism

See [Performance Optimization](#performance-optimization) section for details.

---

## Summary Checklist

- [ ] Download Windows 10 ISO and VirtIO drivers
- [ ] Upload ISOs to Proxmox
- [ ] Create VM with VirtIO storage and network
- [ ] Install Windows with VirtIO SCSI driver
- [ ] Install full VirtIO driver package
- [ ] Install and configure Cloudbase-Init
- [ ] Install Windows updates (recommended)
- [ ] Clean and optimize Windows
- [ ] Create comprehensive unattend.xml
- [ ] Customize passwords in unattend.xml
- [ ] Run sysprep with unattend.xml
- [ ] Wait for automatic shutdown
- [ ] Convert VM to template
- [ ] Test template by cloning
- [ ] Verify OOBE is skipped
- [ ] Verify unique SID generation
- [ ] Configure Terraform provider
- [ ] Deploy test VM with Terraform
- [ ] Document template for team

---

## Additional Resources

- **Proxmox VE Documentation:** https://pve.proxmox.com/pve-docs/
- **Cloudbase-Init Documentation:** https://cloudbase-init.readthedocs.io/
- **VirtIO Drivers:** https://github.com/virtio-win/
- **Terraform Proxmox Provider (bpg):** https://registry.terraform.io/providers/bpg/proxmox/
- **Windows Unattend Reference:** https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/
- **Sysprep Documentation:** https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--system-preparation--overview

---

## License

This guide is provided as-is for educational and documentation purposes. Windows and related Microsoft products are subject to Microsoft licensing terms.

---

## Contributing

Found an issue or have improvements? Please submit issues or pull requests to improve this guide.

---

**Last Updated:** January 2026  
**Proxmox Version:** 9.x  
**Windows Version:** Windows 10 (also applicable to Windows 11 with noted modifications)
