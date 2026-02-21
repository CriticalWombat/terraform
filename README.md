# Proxmox Active Directory Lab — Terraform

This Terraform project provisions a Windows Active Directory lab environment on Proxmox. It clones a pre-prepared Windows template, promotes one VM to a Domain Controller, then joins a configurable number of Windows 10 client VMs to the domain — all over WinRM with no manual steps.

---

## Prerequisites

- A Proxmox node with the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest) provider accessible.
- A sysprepped Windows Server template for the DC (see `template_id` in the root module — default `9100`).
- A sysprepped Windows 10 template for clients (default `9010`). See the sibling [Windows 10 Template Preparation](Lab-Domain/image_conf/windows10-template-guide.md) docs.
- Both templates must have WinRM HTTPS configured on port 5986 and be reachable by Terraform (i.e. the machine running `terraform apply` must be able to reach the VM IPs).
- Proxmox guest agent installed and enabled in both templates so IP addresses can be discovered at runtime.
- Terraform >= 1.3.

---

## Project Structure

```
.
├── main.tf                          # Root — provider config and module calls
├── variables.tf                     # Root-level variable declarations
├── terraform.tfvars                 # Your local values (do not commit)
├── scripts/
│   ├── promote-dc.ps1               # Installs AD DS and promotes the DC
│   ├── verify-dc.ps1                # Confirms AD DS is healthy post-promotion
│   └── join-domain.ps1              # Joins a client to the domain
└── modules/
    ├── domain-controller/
    │   └── main.tf                  # DC VM, AD DS role install, promotion, verification
    └── windows-clients/
        └── main.tf                  # Client VMs, DNS config, domain join
```

---

## How It Works

Provisioning happens in a strict dependency chain enforced by `depends_on` and `null_resource` triggers.

**Domain Controller module** (`modules/domain-controller/main.tf`):

1. Clones the DC template as a linked clone and waits for the guest agent to report an IPv4 address.
2. Waits an additional 5 minutes for the first-boot WinRM setup to complete.
3. Uploads `promote-dc.ps1` and `verify-dc.ps1` to `C:\terraform-scripts\` on the VM.
4. Installs the `AD-Domain-Services` Windows feature (idempotent — skips if already installed).
5. Runs `promote-dc.ps1` to create a new forest with the configured domain name. The VM reboots automatically after promotion.
6. Waits 5 minutes for the reboot to complete.
7. Runs `verify-dc.ps1` to confirm AD DS is healthy before signalling readiness to the clients module.

**Windows Clients module** (`modules/windows-clients/windows-clients.tf`):

1. Clones `client_count` Windows 10 VMs from the client template and waits 10 minutes for first-boot WinRM setup to complete on all of them.
2. Only starts once `var.dc_verified` is set (passed from the DC module output).
3. Uploads `join-domain.ps1` to each client.
4. Points each client's DNS at the DC IP (with `1.1.1.1` as a fallback) so the domain name is resolvable.
5. Waits 30 seconds for DNS to settle, then runs `join-domain.ps1` on each client. The script triggers a reboot; the client comes up domain-joined.

Client VMs are named `WIN10-1`, `WIN10-2`, … `WIN10-N` and receive VM IDs starting at 200.

---

## Configuration

### `terraform.tfvars`

Create this file in the project root. It is not committed to source control.

```hcl
# Proxmox connection
proxmox_endpoint     = "https://192.168.1.10:8006"
proxmox_username     = "root@pam"
proxmox_api_token    = "root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
proxmox_insecure     = true   # set false if you have a valid Proxmox TLS cert
proxmox_ssh_username = "root"
proxmox_ssh_password = "your-proxmox-root-password"

# Windows credentials (must match what is set in the template unattend.xml)
admin_username = "Administrator"
admin_password = "LocalAdmin123!"

# Active Directory
domain_name         = "lab.local"
domain_netbios_name = "LAB"
safe_mode_password  = "SafeMode123!"

# Number of Windows 10 clients to provision
client_count = 3
```

### Root `main.tf` — key values to review

| Setting | Default | Description |
|---|---|---|
| `vm_id` (DC) | `8000` | Proxmox VM ID for the DC |
| `template_id` (DC) | `9100` | Template to clone for the DC |
| `template_id` (clients) | `9010` | Template to clone for clients |
| `node_name` | `pve` | Proxmox node name |
| `datastore_id` | `zfs-pool1` | Storage pool for VM disks |
| `network_bridge` | `vmbr0` | Network bridge for client NICs |

---

## Deployment

```bash
terraform init
terraform plan
terraform apply
```

A full apply with 3 client VMs typically takes 25–35 minutes end to end, accounting for VM boot times, sysprep first-boot, AD DS promotion, and domain joins.

To provision only the DC first:

```bash
terraform apply -target=module.domain_controller
```

Then apply the rest:

```bash
terraform apply
```

---

## Outputs

The DC module exposes two outputs consumed by the root and clients modules:

| Output | Description |
|---|---|
| `dc_ip` | The DHCP IP address of the DC as reported by the guest agent |
| `dc_verified` | Becomes set once `verify-dc.ps1` completes successfully; gates client provisioning |

---

## Timing and Boot Waits

The project uses `time_sleep` resources at several points because WinRM must be reachable and scripts must have finished before the next step can connect. The waits are:

| Wait | Duration | Reason |
|---|---|---|
| After DC clone | 5 min | First-boot sysprep + WinRM setup |
| After DC promotion | 5 min | Post-promotion reboot |
| After client clone | 10 min | First-boot sysprep + WinRM setup (all clients in parallel) |
| After DNS change | 30 sec | DNS propagation before domain join |

If your environment is slower or faster, adjust the `create_duration` values in the relevant `time_sleep` resources.

---

## Security Notes

> Credentials are passed as plaintext command-line arguments to `promote-dc.ps1` and `join-domain.ps1`. For a production environment, replace these with SecureString handling or a secrets manager.

Other considerations:

- **WinRM `insecure = true`** skips certificate validation on all connections. The self-signed certs generated at first boot cannot be verified by Terraform without additional trust configuration.
- **`proxmox_insecure = true`** skips TLS validation for the Proxmox API. Set to `false` if your Proxmox node has a trusted certificate.
- The `safe_mode_password` is a DSRM recovery password — store it somewhere safe outside of `terraform.tfvars`.
- Add `terraform.tfvars` to your `.gitignore` to avoid committing credentials.

```gitignore
terraform.tfvars
*.tfstate
*.tfstate.backup
.terraform/
```