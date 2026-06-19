# Template Preparation Guide

This folder contains everything needed to turn a raw Windows ISO into a Proxmox template that Terraform can clone, configure, and use with no manual intervention.

You build **two** templates:
- **Windows Server** — cloned into the Domain Controller
- **Windows 10** — cloned into each client workstation

Both templates are identical in what they need (WinRM, guest agent, VirtIO). The process is the same for both.

---

## Files

| File | Purpose |
|---|---|
| `Prepare-Template.ps1` | Run once on the source VM to clean and sysprep it |
| `setup.ps1` | Runs automatically on first boot of every clone; configures WinRM, Defender, RDP, guest agent |
| `unattend-server.xml` | Drives Windows OOBE for the Server template |
| `unattend-win10.xml` | Drives Windows OOBE for the Windows 10 template |

---

## End-to-End Flow

```
[Proxmox] Create VM
    └── Install Windows from ISO
        └── Install VirtIO drivers + guest agent
            └── Run Prepare-Template.ps1 -Password "YourPassword"
                └── VM shuts down (sysprep complete)
                    └── [Proxmox] Convert VM to template
                        └── terraform apply  (Terraform clones + configures everything)
```

---

## Step 1 — Create the VM in Proxmox

Create a new VM with these settings (adjust to your hardware):

| Setting | Windows Server (DC) | Windows 10 (clients) |
|---|---|---|
| CPU | 4 cores | 4 cores |
| RAM | 8 GB | 4 GB |
| Disk | 80 GB, **SCSI**, VirtIO SCSI controller | 60 GB, **SCSI**, VirtIO SCSI controller |
| NIC | **VirtIO** (paravirtualized) | **VirtIO** (paravirtualized) |
| CD drive 1 | Windows ISO | Windows ISO |
| CD drive 2 | [VirtIO ISO](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso) | VirtIO ISO |
| QEMU Guest Agent | **Enabled** (VM Options tab) | **Enabled** |

> The VirtIO ISO is needed so Windows can see the SCSI disk and NIC during installation.

---

## Step 2 — Install Windows

Boot from the Windows ISO. When the installer asks where to install:

1. Click **Load driver**
2. Browse to the VirtIO CD → `vioscsi\w10\amd64` (Win10) or `vioscsi\2k19\amd64` (Server 2019) or `vioscsi\2k22\amd64` (Server 2022)
3. Load the **Red Hat VirtIO SCSI** driver — the disk will appear
4. Complete the installation normally

**Windows 10**: Select "Windows 10 Pro" (domain join requires Pro or Enterprise).  
**Windows Server**: Select "Desktop Experience" (with GUI).

---

## Step 3 — Post-Install: VirtIO Drivers + Guest Agent

After Windows boots for the first time, open Device Manager or PowerShell and install:

1. **VirtIO drivers** — run the VirtIO ISO installer:
   ```
   D:\virtio-win-guest-tools.exe
   ```
   This installs all VirtIO drivers (NIC, balloon, serial, etc.) in one shot.

2. **Proxmox guest agent** — install from the same ISO:
   ```
   D:\guest-agent\qemu-ga-x86_64.msi
   ```
   The guest agent is what Terraform uses to discover the VM's IP address after cloning. Without it, `terraform apply` will hang.

3. Reboot once after installation.

> Verify with: `Get-Service QEMU-GA` — it should show `Running`.

4. **Run Windows Update to completion before proceeding.**

   Open Settings → Windows Update and install all available updates. Reboot as many times as needed until no further updates are offered. Sysprep's generalize pass fails with `hr = 0x800f0975` if a pending update or servicing operation is holding reserved storage — fully updating beforehand is the most reliable way to avoid this.

---

## Step 4 — Run Prepare-Template.ps1

Copy the `image_conf` folder to the VM (drag-drop via RDP, or map a shared folder), then open PowerShell as Administrator and allow script execution:

```powershell
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force
```

Then run the preparation script:

```powershell
# Validate everything looks good first (no changes made)
.\Prepare-Template.ps1 -Password "LabAdmin123!" -Check

# When ready — cleans the VM and launches sysprep
.\Prepare-Template.ps1 -Password "LabAdmin123!" -Force
```

**The password you set here must match `admin_password` in `terraform.tfvars`.**

The script will:
1. Check prerequisites (admin, guest agent, VirtIO)
2. Clean temp files, event logs, WU cache, NIC history, WinRM certs
3. Inject your password into the correct unattend file (auto-detected from OS type)
4. Stage `setup.ps1` into `C:\Windows\Setup\Scripts\`
5. Run `sysprep /generalize /oobe /shutdown`

The VM shuts down automatically when sysprep finishes.

---

## Step 5 — Convert to Template in Proxmox

In the Proxmox web UI:
1. Select the VM (do **not** start it)
2. Right-click → **Convert to Template**

Note the VM ID — you'll need it for `dc_template_id` or `win10_template_id` in `terraform.tfvars`.

> Repeat Steps 1–5 for your second template (Server + Win10).

---

## Step 6 — Terraform Apply

```bash
cd Lab-Domain
cp terraform.tfvars.example terraform.tfvars
# Set dc_template_id, win10_template_id, admin_password (must match Step 4), etc.

terraform init
terraform apply
```

---

## What Happens on Each Clone's First Boot

When Terraform clones a template and starts it:

1. Windows processes the staged `unattend.xml`, which:
   - Assigns a unique random hostname
   - Sets the Administrator password
   - Enables RDP
   - Runs `setup.ps1`

2. `setup.ps1` configures:
   - Proxmox guest agent (starts/enables it)
   - WinRM HTTPS on port 5986 with a self-signed cert for the new hostname
   - Defender real-time protection **disabled** (required for pentesting tools)
   - Windows Update auto-restart **disabled** (prevents mid-session reboots)
   - NLA for RDP **disabled** (allows RDP without domain pre-auth)
   - High-performance power plan (prevents VM sleep)

3. The guest agent reports the VM's IP to Proxmox, which Terraform reads to proceed with WinRM connections.

---

## Troubleshooting

**Terraform hangs waiting for IP**  
The guest agent is not running. RDP into the VM and run `Get-Service QEMU-GA`. If missing, install `qemu-ga-x86_64.msi` from the VirtIO ISO and re-template.

**WinRM connection refused / timeout**  
Check `C:\Windows\Temp\setup.log` on the clone. If the file is empty or missing, the unattend didn't run `setup.ps1` — the template may have been booted after sysprep. Rebuild from the ISO.

**Sysprep fails with `hr = 0x800f0975` (reserved storage in use)**  
A Windows Update or servicing operation is holding reserved storage. Run Windows Update to completion (rebooting until no updates remain), then re-run `Prepare-Template.ps1`. The script also runs `DISM /Set-ReservedStorageState /State:Disabled` automatically, but this cannot override an actively running update.

**Sysprep fails with "A fatal error occurred"**  
Usually caused by an installed Microsoft Store app incompatible with sysprep. Run `Get-AppxPackage | Remove-AppxPackage` on the source VM before running `Prepare-Template.ps1`.

**Password doesn't work after clone**  
The password in the unattend did not match what you provided. Re-run `Prepare-Template.ps1 -Password "..."` with the correct password and re-template. Ensure the same value is in `admin_password` in `terraform.tfvars`.

**BadBlood / VulnAD fails with Defender errors**  
If you're seeing AV alerts during lab setup, the Defender disable in `setup.ps1` may not have run. Verify in the log, or manually run `Set-MpPreference -DisableRealtimeMonitoring $true` on the DC after cloning.
