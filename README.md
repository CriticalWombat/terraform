# Active Directory Lab - Terraform Automation

Automated deployment of Windows Active Directory lab environment on Proxmox using Terraform.

## Architecture

- **Domain Controller:** Windows Server 2022 (10.27.11.240)
- **Clients:** Windows 10/11 (10.27.11.241+)
- **Network:** vmbr1 bridge
- **Domain:** contoso.local

## Prerequisites

### Templates Required

1. **Windows Server 2022 Template (ID: 9100)**
   - Static IP: 10.27.11.240/24
   - Gateway: 10.27.11.1
   - DNS: 1.1.1.1, 1.0.0.1
   - WinRM enabled on port 5986
   - QEMU Guest Agent installed

2. **Windows 10/11 Template (ID: 8001)**
   - Static IP: 10.27.11.241/24
   - Gateway: 10.27.11.1
   - DNS: 1.1.1.1, 1.0.0.1
   - WinRM enabled on port 5986
   - QEMU Guest Agent installed

### Software Requirements

- Terraform >= 1.0
- SSH access to Proxmox host
- Network connectivity to 10.27.11.0/24 subnet

## Quick Start

### 1. Clone Repository
```bash
git clone <your-repo-url>
cd terraform-ad-lab
```

### 2. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Fill in your Proxmox credentials and desired configuration.

### 3. Initialize Terraform
```bash
terraform init
```

### 4. Deploy Domain Controller
```bash
terraform apply -target=module.domain_controller
```

Wait 20-25 minutes for DC promotion to complete.

### 5. Deploy Clients
```bash
terraform apply
```

Wait 10-15 minutes per client for domain join.

## IP Address Scheme

| Component | IP Address | Notes |
|-----------|------------|-------|
| DC (AD01) | 10.27.11.240 | Domain Controller |
| WIN10-1 | 10.27.11.241 | First client |
| WIN10-2 | 10.27.11.242 | Second client |
| WIN10-3 | 10.27.11.243 | Third client (if enabled) |

## Configuration

### Adjust Client Count

Edit `terraform.tfvars`:
```hcl
client_count = 3  # Create 3 clients instead of 2
```

### Change Domain Name

Edit `terraform.tfvars`:
```hcl
domain_name         = "lab.local"
domain_netbios_name = "LAB"
```

## Troubleshooting

### View Outputs
```bash
terraform output
```

### Check Specific Module
```bash
terraform state list | grep domain_controller
```

### Retry Failed Resource
```bash
terraform taint 'module.windows_clients.null_resource.join_domain["WIN10-1"]'
terraform apply
```

### Connect via RDP
```bash
# Get RDP commands
terraform output rdp_commands

# Example:
xfreerdp /v:10.27.11.240 /u:Administrator /p:YourPassword
```

### Verify DC Status

SSH to DC and check:
```powershell
Get-ADDomain
Get-Service ADWS,DNS,Netlogon,KDC
Get-ADComputer -Filter *
```

## Cleanup

### Destroy All Resources
```bash
terraform destroy
```

### Destroy Only Clients
```bash
terraform destroy -target=module.windows_clients
```

## Project Structure
```
terraform-ad-lab/
├── main.tf                      # Root module
├── variables.tf                 # Input variables
├── terraform.tfvars.example     # Example configuration
├── outputs.tf                   # Output values
├── modules/
│   ├── domain-controller/       # DC module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── windows-clients/         # Clients module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── scripts/                     # PowerShell scripts
    ├── configure-winrm.ps1
    ├── promote-dc.ps1
    ├── verify-dc.ps1
    └── join-domain.ps1
```

## Time Estimates

- **DC Deployment:** 20-25 minutes
- **Per Client:** 10-15 minutes
- **Full Lab (1 DC + 2 clients):** 35-45 minutes

## Security Notes

⚠️ **This is a LAB environment configuration:**

- Uses plaintext passwords in tfvars
- WinRM allows unencrypted connections
- Self-signed certificates
- Not suitable for production

For production, use:
- HashiCorp Vault for secrets
- Proper PKI infrastructure
- Encrypted WinRM with proper certificates
- Network segmentation