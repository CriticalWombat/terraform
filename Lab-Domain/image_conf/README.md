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
| `Prepare-Template.ps1` | Run once on the source VM to clean, stage scripts, register the WinRM scheduled task, and sysprep |
| `setup-specialize.ps1` | Runs during the unattend `specialize` pass via `RunSynchronous`; handles only registry and config operations that do not require Windows services |
| `setup-winrm.ps1` | Runs on first clone boot via the `FirstBootWinRM` scheduled task; handles all service-dependent setup (WinRM, firewall, guest agent) |
| `unattend-server.xml` | Drives Windows Setup and OOBE for the Server template |
| `unattend-win10.xml` | Drives Windows Setup and OOBE for the Windows 10 template |

---

## End-to-End Flow

```
[Proxmox] Create VM
    └── Install Windows from ISO
        └── Install VirtIO drivers + guest agent
            └── Run Windows Update to completion (reboot until none remain)
                └── Run Prepare-Template.ps1 -Password "YourPassword"
                    └── VM shuts down (sysprep complete)
                        └── [Proxmox] Convert VM to template
                            └── terraform apply  (Terraform clones + configures everything)
```

---

## Step 1 — Create the VM in Proxmox

Create a new VM with these settings (adjust to your hardware):

**System tab**

| Setting | Value |
|---|---|
| Machine | Q35 |
| BIOS | SeaBIOS |
| SCSI Controller | VirtIO SCSI |
| Qemu Agent | Enabled |

**CPU tab**

| Setting | Windows Server (DC) | Windows 10 (clients) |
|---|---|---|
| CPU Type | kvm64 | kvm64 |
| Cores | 4 | 4 |
| NUMA | Enabled | Enabled |

**Memory tab**

| Setting | Windows Server (DC) | Windows 10 (clients) |
|---|---|---|
| RAM | 8 GB | 8 GB |
| Ballooning Device | Disabled | Disabled |
| Allow KSM | Disabled | Disabled |

**Hard Disk tab**

| Setting | Windows Server (DC) | Windows 10 (clients) |
|---|---|---|
| Bus/Device | SCSI | SCSI |
| Size | 80 GB | 60 GB |
| Cache | No cache | No cache |
| Discard | Yes | Yes |

**Network tab**

| Setting | Value |
|---|---|
| Model | VirtIO (paravirtualized) |
| Firewall | Disabled |

**CD Drives**

| Drive | Value |
|---|---|
| CD drive 1 | Windows ISO |
| CD drive 2 | [VirtIO ISO](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso) |

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

## Step 3 — Post-Install: VirtIO Drivers, Guest Agent, and Windows Update

After Windows boots for the first time:

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
3. Disable reserved storage (`DISM /Set-ReservedStorageState /State:Disabled`)
4. Inject your password into the correct unattend file (auto-detected from OS type)
5. Stage `setup-specialize.ps1` and `setup-winrm.ps1` into `C:\Windows\Setup\Scripts\`
6. Register the `FirstBootWinRM` scheduled task (see below)
7. Run `sysprep /generalize /oobe /shutdown`

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

When Terraform clones a template and starts it, three things happen in sequence:

### Phase 1 — Specialize pass (`setup-specialize.ps1`)

Windows Setup runs the `specialize` pass from the staged unattend. A `RunSynchronous` command calls `setup-specialize.ps1` synchronously in SYSTEM context.

This script is intentionally limited to operations that do not require Windows services — only registry writes and executable calls. This avoids the failure mode where WinRM or the Windows Firewall aren't yet started:

- QEMU guest agent startup type set to Automatic (service will be started in Phase 3)
- Windows Update auto-restart disabled
- High-performance power plan, sleep disabled
- RDP enabled (registry key only — firewall rule added in Phase 3)
- Server Manager auto-open disabled (Server SKUs only)

### Phase 2 — OOBE pass (`oobeSystem`)

After specialize, Windows processes the `oobeSystem` pass from the unattend:

- Administrator password set to the value embedded by `Prepare-Template.ps1`
- AutoLogon configured for 3 logon cycles

### Phase 3 — First startup (`setup-winrm.ps1` via scheduled task)

The `FirstBootWinRM` scheduled task was registered in the template by `Prepare-Template.ps1` **before sysprep ran**. It survives sysprep generalization because it runs as `SYSTEM` — a well-known SID that is not remapped during generalization. The task fires at startup, after the Service Control Manager has started all automatic-start services, which is the only point at which WinRM and the Windows Firewall can be configured reliably.

`setup-winrm.ps1` runs and:

- Sets the network profile to Private (required for PSRemoting)
- Starts the QEMU guest agent service
- Opens the RDP firewall rule
- Starts WinRM, runs `winrm quickconfig`, enables PSRemoting
- Configures WSMan authentication settings (Basic, unencrypted, TrustedHosts)
- Creates the WinRM HTTP firewall rule on port 5985
- Restarts WinRM to apply all settings
- **Removes the `FirstBootWinRM` scheduled task** — it is a one-shot operation and must not run again after domain promotion changes the system state

The guest agent reports the VM's IP to Proxmox. Terraform reads this IP and waits up to 30 minutes for WinRM to become available before beginning provisioning.

---

## Why a Scheduled Task Instead of Other Mechanisms

Several other approaches were tried and failed in this deployment pattern:

| Mechanism | Why it failed |
|---|---|
| `FirstLogonCommands` | Requires AutoLogon to fire; unreliable on first boot |
| `SetupComplete.cmd` | Did not execute reliably in this sysprep/clone scenario |
| `RunSynchronous` (full setup) | WinRM and firewall services not started during specialize pass — script aborted |

The scheduled task approach works because the Task Scheduler fires startup tasks after the system is fully operational, independent of any user interaction. The SYSTEM SID is preserved through sysprep so no re-registration is needed per clone.

---

## Troubleshooting

**Terraform hangs waiting for IP**  
The guest agent is not running. RDP into the VM and run `Get-Service QEMU-GA`. If missing, install `qemu-ga-x86_64.msi` from the VirtIO ISO and re-template.

**WinRM connection refused / timeout**  
Check `C:\Windows\Temp\setup.log` on the clone. Look for the `=== WinRM first-boot setup` section. If it is missing, the `FirstBootWinRM` scheduled task did not run — check Task Scheduler (`taskschd.msc`) on the clone to see if the task still exists and whether it has a last-run result. If the task is missing entirely, the template was not built with the current `Prepare-Template.ps1` — rebuild the template.

**`FirstBootWinRM` task exists but shows a failure code**  
Open `C:\Windows\Temp\setup.log` and find the `FATAL:` line. Common causes: WinRM service failed to start (check Event Viewer → System for Service Control Manager errors), or the Scripts directory is missing (`C:\Windows\Setup\Scripts\setup-winrm.ps1`). The latter means the template disk image is from before the split-script change — rebuild the template.

**Sysprep fails with `hr = 0x800f0975` (reserved storage in use)**  
A Windows Update or servicing operation is holding reserved storage. Run Windows Update to completion (rebooting until no updates remain), then re-run `Prepare-Template.ps1`. The script also runs `DISM /Set-ReservedStorageState /State:Disabled` automatically, but this cannot override an actively running update.

**Sysprep fails with "A fatal error occurred"**  
Usually caused by an installed Microsoft Store app incompatible with sysprep. Run `Get-AppxPackage | Remove-AppxPackage` on the source VM before running `Prepare-Template.ps1`.

**Password doesn't work after clone**  
The password in the unattend did not match what you provided. Re-run `Prepare-Template.ps1 -Password "..."` with the correct password and re-template. Ensure the same value is in `admin_password` in `terraform.tfvars`.
