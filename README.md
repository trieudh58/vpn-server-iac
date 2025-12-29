# Oracle Cloud Infrastructure WireGuard VPN Server

This Terraform configuration deploys a WireGuard VPN server on Oracle Cloud Infrastructure using Ubuntu 24.04 with the VM.Standard.E2.1.Micro shape. WireGuard is automatically installed and configured during instance provisioning.

## Prerequisites

1. Oracle Cloud Infrastructure account
2. OCI CLI configured or API keys generated
3. Terraform installed (>= 1.0)

## Setup

### 1. Generate OCI API Keys (if not already done)

```bash
mkdir -p ~/.oci
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 600 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

Upload the public key to OCI Console:
- Go to User Settings → API Keys → Add API Key
- Copy the fingerprint shown after upload

### 2. Get Required OCIDs

You'll need:
- **Tenancy OCID**: OCI Console → Tenancy Details
- **User OCID**: OCI Console → User Settings
- **Compartment OCID**: OCI Console → Identity → Compartments (can use tenancy OCID for root compartment)
- **SSH Public Key**: Your SSH public key for instance access
  - **New to SSH keys?** See [SSH-KEY-SETUP.md](SSH-KEY-SETUP.md) for a complete guide

### 3. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

**Quick Reference - terraform.tfvars variables:**

| Variable | Where to Find | Example |
|----------|---------------|---------|
| `tenancy_ocid` | OCI Console → Profile → Tenancy | `ocid1.tenancy.oc1..aaa...` |
| `user_ocid` | OCI Console → Profile → User Settings | `ocid1.user.oc1..aaa...` |
| `fingerprint` | After uploading API key to OCI Console | `aa:bb:cc:dd:...` |
| `private_key_path` | Path to your OCI API private key | `~/.oci/oci_api_key.pem` |
| `region` | Choose from OCI regions | `us-ashburn-1` |
| `compartment_ocid` | Same as tenancy_ocid (for root) | `ocid1.tenancy.oc1..aaa...` |
| `ssh_public_key` | Your SSH public key (see [SSH-KEY-SETUP.md](SSH-KEY-SETUP.md)) | `ssh-ed25519 AAA...` |

### 4. Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

## Resources Created

- Virtual Cloud Network (VCN)
- Internet Gateway
- Route Table
- Security List (allows SSH, ICMP, WireGuard port 51820, and OpenVPN port 1194)
- Subnet
- Compute Instance (VM.Standard.E2.1.Micro, Ubuntu 24.04) with WireGuard pre-installed

## Connecting to Your Instance

After deployment, use the SSH command from outputs:

```bash
ssh ubuntu@<instance_public_ip>
```

## WireGuard Setup

WireGuard is automatically installed and configured during instance provisioning. The setup includes:

- WireGuard server running on port 51820 (UDP)
- IP forwarding enabled
- Firewall configured (both UFW and iptables)
- **OCI iptables REJECT rule automatically handled** - fixes common handshake issues
- Server keys generated automatically
- Helper script for adding clients

### Wait for Installation to Complete

Cloud-init runs in the background after instance creation. To check if WireGuard setup is complete:

```bash
ssh ubuntu@<instance_public_ip>
sudo tail -f /var/log/cloud-init-output.log
# Or check for completion marker
sudo ls -la /var/log/wireguard-setup-complete
```

### Verify Setup

After deployment, verify everything is configured correctly:

```bash
# Copy verification script to server
scp verify-setup.sh oci-vpn:~/

# Run verification
ssh oci-vpn "sudo bash ~/verify-setup.sh"
```

This will check:
- WireGuard service status
- Port listening on 51820
- IP forwarding enabled
- OCI iptables REJECT rule fixed
- Firewall configuration
- NAT rules
- Server keys generated

### Adding Clients

A helper script is provided to easily add WireGuard clients:

```bash
# SSH into the server
ssh ubuntu@<instance_public_ip>

# Add a client (run as root)
sudo /usr/local/bin/add-wireguard-client laptop

# This will:
# - Generate client keys
# - Update server configuration
# - Create client config file at /root/wireguard-laptop.conf
# - Display a QR code for mobile devices
```

### Getting Client Configuration

```bash
# View client configuration file
sudo cat /root/wireguard-<client-name>.conf

# For mobile devices, the QR code is displayed automatically
# Or regenerate it:
sudo qrencode -t ansiutf8 < /root/wireguard-<client-name>.conf
```

### Client Configuration

On your client device:

**Linux:**
```bash
# Install WireGuard
sudo apt install wireguard  # Debian/Ubuntu
sudo dnf install wireguard-tools  # Fedora/RHEL

# Copy the config
sudo nano /etc/wireguard/wg0.conf
# Paste the client configuration

# Start the connection
sudo wg-quick up wg0

# Enable on boot
sudo systemctl enable wg-quick@wg0
```

**macOS/Windows/Mobile:**
- Install the WireGuard app
- Import the configuration file or scan the QR code

### Verify Connection

On the server:
```bash
sudo wg show
```

### WireGuard Network Details

- Server VPN IP: `10.8.0.1/24`
- Client VPN IPs: `10.8.0.2`, `10.8.0.3`, etc. (auto-assigned)
- VPN Port: `51820/udp`

## Clean Up

To destroy all resources:

```bash
terraform destroy
```

## Security Notes

- The security list allows SSH (port 22) from anywhere - consider restricting to your IP
- WireGuard port (51820/UDP) is open for VPN functionality
- OpenVPN ports (1194 TCP/UDP) are also open if you want to use OpenVPN instead
- Default Ubuntu user is `ubuntu`
- UFW firewall is configured automatically
- **OCI iptables issue handled**: The setup automatically fixes OCI's default REJECT rule that blocks VPN traffic
- Server and client keys are automatically generated and stored securely
- All traffic through the VPN is encrypted using WireGuard's modern cryptography

## Technical Notes

### OCI iptables REJECT Rule Fix

Oracle Cloud Infrastructure adds a default iptables REJECT rule that blocks all traffic before UFW rules can allow it. This setup automatically:

1. Detects the OCI REJECT rule in the INPUT chain
2. Inserts WireGuard/VPN allow rules **before** the REJECT rule
3. Persists these rules across reboots using `netfilter-persistent`

This ensures WireGuard handshakes succeed without manual intervention. For more details, see [WIREGUARD-TROUBLESHOOTING.md](WIREGUARD-TROUBLESHOOTING.md).
