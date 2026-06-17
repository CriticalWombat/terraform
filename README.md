# Proxmox AD Pentesting Lab — Terraform

Provisions a Windows Active Directory lab on Proxmox. Clones pre-built templates, promotes a DC, joins Windows 10 clients, then runs a selectable vulnerability profile to make the domain ready for pentesting practice — all fully automated over WinRM, no manual steps.

---

## Prerequisites

- Proxmox node with the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) provider reachable
- A sysprepped **Windows Server** template (WinRM HTTPS on 5986, Proxmox guest agent installed)
- A sysprepped **Windows 10** template (same requirements)
- The machine running `terraform apply` must be able to reach the VM IPs over the network
- Terraform >= 1.3

See [`Lab-Domain/image_conf/`](Lab-Domain/image_conf/) for template preparation guidance.

---

## Project Structure

```
Lab-Domain/
├── main.tf                          # Provider, module wiring, lab_profile selection
├── variables.tf                     # All input variables
├── outputs.tf                       # DC IP, client IPs, RDP commands
├── terraform.tfvars.example         # Copy → terraform.tfvars and fill in
└── modules/
    ├── domain-controller/           # Clone DC template, install AD DS, promote
    │   └── scripts/
    │       └── promote-dc.ps1
    ├── windows-clients/             # Clone client templates, set DNS, join domain
    │   └── scripts/
    │       └── join-domain.ps1
    └── lab-profiles/                # Post-setup vulnerability profiles (pick one)
        ├── bad-blood/               # davidprowe/BadBlood — random users/groups/ACEs
        │   └── scripts/
        │       └── run-badblood.ps1
        └── vuln-ad/                 # WazeHell/vulnerable-AD — targeted misconfigurations
            └── scripts/
                └── run-vulnad.ps1
```

---

## Quick Start

```bash
cd Lab-Domain
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

terraform init
terraform apply
```

A full apply with 2 clients and BadBlood typically takes **30–45 minutes** end to end.

---

## Configuration

### Key variables (`terraform.tfvars`)

| Variable | Default | Description |
|---|---|---|
| `proxmox_endpoint` | — | `https://<host>:8006` |
| `proxmox_api_token` | — | `root@pam!<name>=<uuid>` |
| `proxmox_ssh_password` | — | Proxmox root password |
| `proxmox_node` | `pve` | Proxmox node name |
| `datastore` | `local-lvm` | Disk storage pool |
| `network_bridge` | `vmbr0` | Network bridge |
| `dc_template_id` | — | VM ID of your Windows Server template |
| `win10_template_id` | — | VM ID of your Windows 10 template |
| `vm_id_base` | `8000` | DC gets this ID; clients get `8001`, `8002`, … |
| `admin_password` | — | Local Administrator password (must match template) |
| `domain_name` | `corp.local` | AD domain FQDN |
| `domain_netbios` | `CORP` | NetBIOS name |
| `safe_mode_password` | — | DSRM password |
| `client_count` | `1` | Number of Windows 10 workstations |
| `lab_profile` | `badblood` | Vulnerability profile: `badblood`, `vulnad`, `none` |

---

## Lab Profiles

Set `lab_profile` in `terraform.tfvars` to select which post-setup tool runs on the DC after promotion.

### `badblood` (default)
Runs [davidprowe/BadBlood](https://github.com/davidprowe/BadBlood). Populates the domain with hundreds of randomised users, groups, OUs, and ACE misconfigurations — good for realistic-feeling AD recon and lateral movement practice.

### `vulnad`
Runs [WazeHell/vulnerable-AD](https://github.com/WazeHell/vulnerable-AD). Applies a targeted set of well-known AD misconfigurations: AS-REP roastable accounts, Kerberoastable SPNs, DCSync-privileged accounts, ACL abuses, and delegation issues. Smaller footprint than BadBlood; easier to verify specific attack paths.

### `none`
Skips post-setup entirely. Leaves you with a clean domain to configure manually.

### Adding a new profile

1. Create `modules/lab-profiles/<name>/main.tf` with a `null_resource` that connects to `var.dc_ip` and runs your setup script.
2. Create `modules/lab-profiles/<name>/variables.tf` — only `dc_ip` and `admin_password` are required.
3. Add a conditional module call in the root `main.tf`:
   ```hcl
   module "profile_<name>" {
     count      = var.lab_profile == "<name>" ? 1 : 0
     source     = "./modules/lab-profiles/<name>"
     depends_on = [module.domain_controller]
     dc_ip          = module.domain_controller.dc_ip
     admin_password = var.admin_password
   }
   ```
4. Add `"<name>"` to the `validation` block in `variables.tf`.

---

## How It Works

```
Clone DC template
  └── wait 3m (WinRM ready)
      └── promote-dc.ps1  (installs AD DS role + promotes forest + reboots)
          └── wait 5m (post-promotion reboot)
              └── lab profile runs  (BadBlood / VulnAD / none)

Clone client templates  (parallel, depends on DC module completing)
  └── wait 5m (WinRM ready)
      └── set DNS → DC IP
          └── join-domain.ps1  (joins domain + reboots)
```

---

## Outputs

After `terraform apply`:

```
dc_ip          = "192.168.1.101"
client_ips     = { "WIN10-01" = "192.168.1.102", ... }
rdp_commands   = { dc = "xfreerdp /v:... ", "WIN10-01" = "xfreerdp /v:..." }
lab_summary    = { profile = "badblood", domain = "corp.local", ... }
```

---

## Security Notes

- Credentials are passed as plaintext CLI args to WinRM. This is intentional for a sandboxed pentesting lab — do not deploy this pattern in production.
- WinRM uses self-signed certs (`insecure = true`). Fine for an isolated lab network.
- Add `terraform.tfvars` to `.gitignore` — it contains all your secrets.

```gitignore
terraform.tfvars
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl
```
