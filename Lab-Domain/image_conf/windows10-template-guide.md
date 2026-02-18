# Windows 10 Proxmox Template Image Creation Guide

This document covers the full process of building a Windows 10 VM template in Proxmox
for use with Terraform. The end result is a template that, when cloned, boots into a
fully configured machine with WinRM available and a correct self-signed certificate
bound to the clone's unique hostname.

---

## Prerequisites

- Proxmox VE host with sufficient storage and RAM
- Windows 10 ISO (Pro or Enterprise recommended — Home lacks WinRM support)
- [VirtIO drivers ISO](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso) — download and upload to Proxmox ISO storage
- The three template files from this repo placed somewhere accessible (e.g. a network share, USB, or uploaded via the Proxmox web console):
  - `Prepare-Template.ps1`
  - `winrm-setup.ps1`
  - `unattend.xml`

---

## Part 1 — Create the VM in Proxmox

Create a new VM with the following settings. These are the recommended values for a
Windows 10 template — adjust CPU/RAM/disk to your environment.

| Setting | Value |
|---|---|
| OS Type | Microsoft Windows, 10/2016/2019 |
| BIOS | OVMF (UEFI) or SeaBIOS — be consistent with your clones |
| CPU | 2 cores minimum, type `host` for best performance |
| RAM | 4096 MB minimum |
| Disk bus | VirtIO Block or SCSI with VirtIO SCSI controller |
| Disk size | 60 GB minimum (template is thin-provisioned) |
| Network | VirtIO (paravirt) |
| CD Drive 1 | Windows 10 ISO |
| CD Drive 2 | VirtIO drivers ISO |

> **Note:** Using VirtIO for disk and network requires the drivers to be installed during
> Windows Setup (see Part 2). If you prefer to skip the driver install during setup,
> use IDE for disk temporarily — you can switch to VirtIO after drivers are installed.
> VirtIO gives significantly better disk and network throughput.

---

## Part 2 — Install Windows 10

Boot the VM and proceed through Windows Setup normally with the following notes.

### Load VirtIO storage drivers during setup

If you chose VirtIO Block or VirtIO SCSI for your disk, Windows Setup will show no
available disks. You must load the driver manually:

1. At the "Where do you want to install Windows?" screen, click **Load driver**
2. Browse to the VirtIO ISO (usually `D:\` or `E:\`)
3. Navigate to `virtio-win\viostor\w10\amd64`
4. Select the driver and click **Next**
5. Your disk will now appear — proceed with installation

### Installation options

- Choose **Custom: Install Windows only (advanced)**
- Create a single partition using the full disk
- When prompted for a product key, click **I don't have a product key** — activation
  is handled separately per-clone

### OOBE (Out of Box Experience)

Complete the minimal OOBE setup. Create a local administrator account when prompted.
This account is temporary — the unattend.xml will use the built-in Administrator
account on clones. A simple name like `localadmin` with a known password is fine.

---

## Part 3 — Initial Configuration After Installation

Log in with the account created during OOBE. All steps below are performed in an
elevated PowerShell prompt unless stated otherwise.

Right-click the Start menu → **Windows PowerShell (Admin)**.

### 3.1 Install VirtIO drivers

If you did not install all VirtIO drivers during setup, install them now via the
bundled installer on the VirtIO ISO:

```powershell
# Assuming VirtIO ISO is mounted as D:
Start-Process -FilePath "D:\virtio-win-gt-x64.msi" -Wait
```

This installs all paravirtualised drivers including:
- VirtIO SCSI / Block storage
- VirtIO network (NetKVM)
- Memory balloon driver
- VirtIO serial
- VirtIO RNG (random number generator)

Reboot after the installer completes, then log back in.

### 3.2 Install QEMU Guest Agent

The QEMU Guest Agent enables Proxmox to communicate with the VM for operations
such as graceful shutdown, IP address reporting, filesystem freeze during snapshots,
and `qm agent` commands from the host.

```powershell
# Assuming VirtIO ISO is mounted as D:
Start-Process -FilePath "D:\guest-agent\qemu-ga-x86_64.msi" -Wait
```

Verify the agent is running:

```powershell
Get-Service QEMU-GA
```

It should show `Running`. If not, start it:

```powershell
Start-Service QEMU-GA
Set-Service QEMU-GA -StartupType Automatic
```

Also enable the QEMU Guest Agent on the VM in Proxmox:
**VM → Options → QEMU Guest Agent → Enabled: Yes**

### 3.3 Set PowerShell Execution Policy

The default execution policy on Windows 10 is `Restricted`, which blocks all scripts
including the preparation script. Set it to `Bypass` for the local machine:

```powershell
Set-ExecutionPolicy Bypass -Scope LocalMachine -Force
```

Verify:

```powershell
Get-ExecutionPolicy -List
```

The `LocalMachine` scope should show `Bypass`. This setting persists into every clone,
which is intentional — Terraform provisioners and any post-boot scripts need to run
without policy interference.

### 3.4 Install Windows Updates

Run Windows Update fully and reboot as many times as needed until no further updates
are available. This is important to do on the template rather than on every clone.

```powershell
# Optional: use PSWindowsUpdate module for scripted update
Install-Module PSWindowsUpdate -Force
Get-WindowsUpdate -Install -AcceptAll -AutoReboot
```

Or use the Settings app: **Settings → Update & Security → Windows Update**.

### 3.5 Install Cloudbase-Init (optional but recommended for Proxmox cloud-init)

Cloudbase-Init is the Windows equivalent of cloud-init. It allows Proxmox to inject
configuration (hostname, IP, user-data) at clone boot time via the cloud-init drive.

1. Download the [Cloudbase-Init stable installer](https://cloudbase.it/cloudbase-init/)
2. Run the installer, accepting defaults
3. On the final screen, **do not** check "Run Sysprep" or "Shutdown" — the
   preparation script handles this

The `unattend.xml` already includes an `Order 4` command that runs Cloudbase-Init
on first boot if it is present, so no further configuration is needed here.

### 3.6 Disable hibernation and fast startup

These can interfere with clean shutdowns and snapshot consistency:

```powershell
powercfg /hibernate off
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" `
    -Name "HiberbootEnabled" -Value 0 -Force
```

### 3.7 Disable Windows Defender real-time protection (optional)

In a lab or trusted environment this reduces noise and improves clone boot performance.
Skip this step if clones will be internet-facing or require AV coverage.

```powershell
Set-MpPreference -DisableRealtimeMonitoring $true
```

To make this survive reboots you can also disable it via Group Policy or the registry:

```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" `
    -Name "DisableAntiSpyware" -Value 1 -Force
```

### 3.8 Disable automatic updates for the template

Windows Update should not run on the template during sysprep or immediately after
cloning before Terraform provisioning completes:

```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
    -Name "NoAutoUpdate" -Value 1 -Force
```

Re-enable this on clones via Terraform provisioner or GPO once the machine is
configured if desired.

---

## Part 4 — Transfer and Run the Preparation Script

Copy the three files to the VM. The simplest methods are:

- Mount a second ISO containing the files (create with `mkisofs` or ImgBurn)
- Use a shared folder if VMware Tools / SPICE is configured
- Download from an internal web server or SMB share

All three files must be in the same directory:

```
Prepare-Template.ps1
winrm-setup.ps1
unattend.xml
```

Run the preparation script from an elevated PowerShell prompt:

```powershell
.\Prepare-Template.ps1
```

The script will:

1. Validate prerequisites (unattend.xml and winrm-setup.ps1 present, running as admin)
2. Reset sysprep generalization state
3. Rearm Windows activation
4. Clear Panther cache (prevents stale unattend from overriding the new one)
5. Clear Windows Update and temp caches
6. Remove non-default user profiles
7. Clear event logs
8. **Wipe all WinRM listeners and LocalMachine\My certificates**
9. Reset Cloudbase-Init state if installed
10. Clear NIC history to prevent ghosting hardware in clones
11. Run disk cleanup
12. Stage `winrm-setup.ps1` to `C:\Windows\Setup\Scripts\`
13. Copy `unattend.xml` to `C:\Windows\System32\Sysprep\`
14. Launch sysprep `/generalize /oobe /shutdown`

The VM will shut down automatically when sysprep completes. **Do not boot it again.**

> **Tip:** Run with `-SkipSysprep` first to validate all prerequisites without
> committing to a sysprep run:
> ```powershell
> .\Prepare-Template.ps1 -SkipSysprep
> ```

---

## Part 5 — Convert to Template in Proxmox

Once the VM has shut down after sysprep:

1. In the Proxmox web UI, right-click the VM
2. Select **Convert to Template**
3. Confirm — this is irreversible on the VM itself

Alternatively via the Proxmox CLI on the host:

```bash
qm template <vmid>
```

The VM is now a template. It will appear with a different icon in the UI and cannot
be started directly.

---

## Part 6 — Clone Behaviour (What Happens on First Boot)

When Terraform (or any other tool) clones this template and boots it, the following
happens automatically in order:

1. Sysprep's specialize pass runs — Windows assigns a unique random hostname
2. OOBE runs unattended — Administrator account is configured, locale is set
3. Auto-logon triggers as Administrator
4. `FirstLogonCommands` runs in order:
   - **Order 1:** RDP is enabled via registry
   - **Order 2:** RDP firewall rule is opened
   - **Order 3:** `winrm-setup.ps1` runs — generates a fresh self-signed cert for
     the clone's hostname, creates the HTTPS listener, configures auth, opens firewall
     ports 5985/5986
   - **Order 4:** Cloudbase-Init runs if present (applies Proxmox cloud-init data)
5. WinRM is available on port 5986 (HTTPS) and 5985 (HTTP)

From this point Terraform's `winrm` provisioner can connect and begin configuration.

---

## Terraform WinRM Connection Block

Since the cert is self-signed, the WinRM provider must be configured to skip
certificate validation:

```hcl
connection {
  type     = "winrm"
  host     = self.default_ipv4_address
  user     = "Administrator"
  password = "LocalAdmin123!"
  port     = 5986
  https    = true
  insecure = true   # required - cert is self-signed, not CA-signed
  timeout  = "10m"
}
```

---

## Troubleshooting

**WinRM not reachable after clone boots**
Check `C:\Windows\Temp\winrm-setup.log` on the clone — this log is written by
`winrm-setup.ps1` and will show exactly which step failed and why.

**Wrong certificate CN on clone**
The template was likely booted after sysprep but before templating, or the cert store
was not fully wiped before sysprep. Re-run `Prepare-Template.ps1` on a fresh base VM.

**Sysprep fails with "Package ... was installed for a user but not provisioned"**
Some Microsoft Store apps block sysprep generalization. Remove them before running
the prep script:
```powershell
Get-AppxPackage -AllUsers | Where-Object { $_.NonRemovable -ne $true } |
    Remove-AppxPackage -ErrorAction SilentlyContinue
```

**Clone hostname is not random / clones share a hostname**
Ensure `<ComputerName>*</ComputerName>` is present in the `specialize` pass of
`unattend.xml`. The asterisk is what tells sysprep to generate a unique name.

**Cloudbase-Init not applying Proxmox cloud-init data**
Ensure the VM in Proxmox has a Cloud-Init drive attached
(**Hardware → Add → CloudInit Drive**) and that the Cloud-Init configuration is
populated under the **Cloud-Init** tab before cloning.
