# Windows 10 Proxmox Template Preparation

This toolkit prepares a Windows 10 VM for use as a Proxmox template. Once the template is created, every clone that spins up from it will automatically configure itself with a unique hostname, an enabled Administrator account, RDP access, and a fully configured WinRM HTTPS listener — ready for remote management with no manual intervention.

---

## Files

| File | Purpose |
|---|---|
| `Prepare-Template.ps1` | Run once on the source VM. Cleans the system and launches sysprep. |
| `setup.ps1` | Runs automatically on first boot of each clone. Configures WinRM. |
| `unattend.xml` | Drives Windows OOBE on each clone's first boot. Calls `setup.ps1`. |

---

## How It Works

**Before templating** — you run `Prepare-Template.ps1` on your source VM. It:

1. Resets the sysprep generalization counter (allowing sysprep to run even if it has been run before).
2. Rearms Windows activation.
3. Scrubs temporary files, event logs, Windows Update cache, NIC history, WinRM listeners, and machine certificates so clones start clean.
4. Copies `setup.ps1` into `C:\Windows\Setup\Scripts\` inside the image.
5. Places `unattend.xml` in the Sysprep folder and launches `sysprep /generalize /oobe /shutdown`.

**After shutdown** — you convert the VM to a template in Proxmox. Do not boot it again before doing so.

**On each clone's first boot** — Windows processes `unattend.xml`, which:

1. Assigns the clone a random unique hostname.
2. Enables the built-in Administrator account with the password defined in `unattend.xml`.
3. Enables RDP and opens its firewall rule.
4. Calls `setup.ps1`, which configures WinRM with a self-signed HTTPS certificate whose CN matches the clone's new hostname.

---

## Prerequisites

- Windows 10 (64-bit) source VM running in Proxmox.
- All three files placed in the same directory on the source VM.
- PowerShell session running as **Administrator**.

---

## Usage

### Basic — run everything including sysprep

```powershell
.\Prepare-Template.ps1
```

You will be prompted to press Enter before any destructive steps begin.

### Custom file paths

```powershell
.\Prepare-Template.ps1 -UnattendPath "D:\custom\unattend.xml" -WinRMScriptPath "D:\custom\setup.ps1"
```

### Pre-flight check only — no changes made

```powershell
.\Prepare-Template.ps1 -SkipSysprep
```

Validates that all required files exist and that the script is running as Administrator, then exits cleanly. Useful for confirming your setup before committing.

---

## Connecting to a Clone via WinRM

After a clone has booted and `setup.ps1` has completed, connect from a management machine using HTTPS on port 5986. Because the certificate is self-signed you need to skip certificate verification or add it to your trusted store.

```powershell
$cred = Get-Credential   # Administrator / LocalAdmin123!

$session = New-PSSession `
    -ComputerName <clone-ip> `
    -Port 5986 `
    -UseSSL `
    -Credential $cred `
    -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck)

Enter-PSSession $session
```

WinRM HTTP (port 5985) is also enabled with Basic auth if you prefer unencrypted connections on a trusted network.

---

## Security Notes

*This is intended for LAB use only.*
> **Change the Administrator password before using.**
> The password `LocalAdmin123!` is stored in plain text in `unattend.xml` and will be visible to anyone with access to the template or its disk image.

Other things to harden before production use:

- **WinRM Basic auth over HTTP** is enabled by `setup.ps1` (`AllowUnencrypted = 1`). Disable this if all management traffic will go over HTTPS.
- **TrustedHosts is set to `*`** on the WinRM client. Restrict this to known management hosts.
- **Firewall rules use `Profile: Any`**, meaning WinRM ports are open on all network profiles. Tighten this to your management VLAN/profile as appropriate.
- Replace the self-signed certificate with one from your internal CA if your tooling requires proper certificate validation.

---

## Logs

`setup.ps1` writes a timestamped log to `C:\Windows\Temp\setup.log` on each clone. Check this file if WinRM is not reachable after first boot.

---

## Workflow Summary

```
[Source VM]
  ├── Place all three files in the same folder
  ├── Run: .\Prepare-Template.ps1
  ├── (review prompt, press Enter)
  └── VM shuts down automatically after sysprep

[Proxmox]
  └── Convert VM to template (do NOT boot first)

[Clone]
  ├── Create linked or full clone from template
  ├── Boot clone
  ├── unattend.xml runs: sets hostname, enables RDP, calls setup.ps1
  ├── setup.ps1 runs: configures WinRM HTTPS with cert for new hostname
  └── Clone is ready for remote management on port 5986
```