# SSH Key Pair Setup Guide

This guide will walk you through creating an SSH key pair for securely accessing your OCI VM.

## What is an SSH Key Pair?

An SSH key pair consists of two files:
- **Private key**: Stays on your local machine (keep this secret!)
- **Public key**: Gets installed on the VM (safe to share)

When you SSH into the VM, your private key proves your identity without needing a password.

## Step-by-Step Guide

### Option 1: ED25519 Key (Recommended - Modern & Secure)

ED25519 keys are more secure, faster, and smaller than RSA keys.

```bash
# Generate the key pair
ssh-keygen -t ed25519 -C "your-email@example.com"

# You'll see this prompt - press Enter to use default location:
# Enter file in which to save the key (/Users/dylan/.ssh/id_ed25519):

# Optional: Set a passphrase for extra security (or press Enter for no passphrase)
# Enter passphrase (empty for no passphrase):
# Enter same passphrase again:
```

**Result:** Two files created:
- Private key: `~/.ssh/id_ed25519`
- Public key: `~/.ssh/id_ed25519.pub`

### Option 2: RSA Key (Traditional - Widely Compatible)

If you need compatibility with older systems:

```bash
# Generate a 4096-bit RSA key pair
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# Press Enter to use default location:
# Enter file in which to save the key (/Users/dylan/.ssh/id_rsa):

# Optional: Set a passphrase
# Enter passphrase (empty for no passphrase):
```

**Result:** Two files created:
- Private key: `~/.ssh/id_rsa`
- Public key: `~/.ssh/id_rsa.pub`

### Option 3: Custom Key Name (For Multiple Keys)

If you want to create a key specifically for this OCI VM:

```bash
# Create a dedicated key for OCI
ssh-keygen -t ed25519 -f ~/.ssh/oci_vm_key -C "oci-vpn-server"

# This creates:
# - Private key: ~/.ssh/oci_vm_key
# - Public key: ~/.ssh/oci_vm_key.pub
```

## Getting Your Public Key

After generating the key, you need to get the public key content:

```bash
# For ED25519 key
cat ~/.ssh/id_ed25519.pub

# For RSA key
cat ~/.ssh/id_rsa.pub

# For custom key
cat ~/.ssh/oci_vm_key.pub
```

**Output looks like this:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJxXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX your-email@example.com
```

**Copy the entire line** - this goes into your `terraform.tfvars` file as the `ssh_public_key` value.

## Adding to terraform.tfvars

Edit your `terraform.tfvars` file:

```hcl
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJxXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX your-email@example.com"
```

**Important:**
- Keep it on one line
- Include the entire key from `ssh-ed25519` (or `ssh-rsa`) to the email comment
- Use double quotes

## Connecting to Your VM

After deploying with Terraform, connect using:

### If using default key location:
```bash
ssh ubuntu@<instance_public_ip>
```

### If using custom key:
```bash
ssh -i ~/.ssh/oci_vm_key ubuntu@<instance_public_ip>
```

### Save time with SSH config:

Create/edit `~/.ssh/config`:

```
Host oci-vpn
    HostName <instance_public_ip>
    User ubuntu
    IdentityFile ~/.ssh/oci_vm_key
    ServerAliveInterval 60
```

Then simply connect with:
```bash
ssh oci-vpn
```

## Security Best Practices

### 1. Set Proper Permissions

```bash
# Private key should only be readable by you
chmod 600 ~/.ssh/id_ed25519
# or
chmod 600 ~/.ssh/id_rsa
chmod 600 ~/.ssh/oci_vm_key

# Public key can be more permissive but should still be protected
chmod 644 ~/.ssh/id_ed25519.pub
```

### 2. Use a Passphrase

When generating keys, consider adding a passphrase:
- Protects your private key if your laptop is compromised
- Slightly less convenient (you'll type it when connecting)
- Use ssh-agent to avoid typing it repeatedly:

```bash
# Start ssh-agent
eval "$(ssh-agent -s)"

# Add your key (will ask for passphrase once)
ssh-add ~/.ssh/id_ed25519

# Now you can SSH without entering passphrase each time
```

### 3. Never Share Your Private Key

- **DO**: Share your public key (the .pub file)
- **DON'T**: Share your private key (the file without .pub)
- **DON'T**: Commit private keys to Git
- **DON'T**: Send private keys via email/Slack/etc.

### 4. Backup Your Keys

```bash
# Create encrypted backup
tar czf ssh-keys-backup.tar.gz ~/.ssh/id_*
# Store this backup somewhere secure (encrypted USB drive, password manager, etc.)
```

## Troubleshooting

### "Permission denied (publickey)"

1. Check if you're using the correct key:
   ```bash
   ssh -v ubuntu@<ip>  # Verbose mode shows which keys are tried
   ```

2. Verify the public key is in terraform.tfvars correctly

3. Check private key permissions:
   ```bash
   ls -la ~/.ssh/id_*
   # Should show: -rw------- for private key
   ```

### "Bad permissions" warning

```bash
# Fix permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

### Testing before deployment

You can verify your key is valid:

```bash
# Check key format
ssh-keygen -l -f ~/.ssh/id_ed25519.pub

# Should output something like:
# 256 SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx your-email@example.com (ED25519)
```

## Quick Reference

| Command | Purpose |
|---------|---------|
| `ssh-keygen -t ed25519` | Generate new ED25519 key |
| `ssh-keygen -t rsa -b 4096` | Generate new RSA key |
| `cat ~/.ssh/id_ed25519.pub` | View public key |
| `ssh-keygen -l -f ~/.ssh/id_ed25519.pub` | Show key fingerprint |
| `ssh -i ~/.ssh/key ubuntu@ip` | Connect with specific key |
| `chmod 600 ~/.ssh/id_ed25519` | Fix private key permissions |
| `ssh-add ~/.ssh/id_ed25519` | Add key to ssh-agent |

## Next Steps

After generating your SSH key:

1. Copy the public key content
2. Add it to `terraform.tfvars` as `ssh_public_key`
3. Run `terraform apply`
4. Connect to your VM with `ssh ubuntu@<instance_public_ip>`

---

**Need more help?** Check the main [README.md](README.md) for full deployment instructions.
