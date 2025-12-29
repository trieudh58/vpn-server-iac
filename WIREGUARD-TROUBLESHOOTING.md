# WireGuard Troubleshooting Guide

## Important: OCI iptables REJECT Rule

**This setup automatically fixes the most common issue on OCI!**

Oracle Cloud Infrastructure adds a default iptables REJECT rule that blocks all traffic before UFW rules can take effect. The cloud-init script automatically:

✅ Detects the OCI REJECT rule
✅ Inserts WireGuard allow rules BEFORE the REJECT rule
✅ Persists the rules across reboots

If you deployed using this Terraform configuration, **this issue is already handled**. If you're still having problems, continue with the diagnostics below.

## Quick Diagnostics Checklist

Run these commands on the server to diagnose handshake failures:

```bash
# SSH into the server
ssh ubuntu@138.2.78.116

# 1. Check if WireGuard is running
sudo systemctl status wg-quick@wg0

# 2. Check WireGuard interface status
sudo wg show

# 3. View recent WireGuard logs
sudo journalctl -u wg-quick@wg0 -n 50

# 4. Check if the interface is up
ip addr show wg0

# 5. Verify firewall rules
sudo ufw status
sudo iptables -L -n -v | grep -i wireguard
sudo iptables -t nat -L -n -v
```

## Common Issues and Solutions

### Issue 1: WireGuard Not Running

**Check:**
```bash
sudo systemctl status wg-quick@wg0
```

**Fix:**
```bash
# Start WireGuard
sudo systemctl start wg-quick@wg0

# Check for errors
sudo journalctl -u wg-quick@wg0 -n 100

# If there are config errors, check the config file
sudo cat /etc/wireguard/wg0.conf
```

### Issue 2: Handshake Failing (Most Common)

**Symptoms:**
- Client shows "Handshake..." but never completes
- No data transfer

**Debugging Steps:**

1. **Check server is listening:**
```bash
# Verify WireGuard is listening on port 51820
sudo ss -ulnp | grep 51820
# Should show: *:51820
```

2. **Check if client is added to server:**
```bash
sudo wg show
# Should show peers with their public keys
```

3. **Test from server side:**
```bash
# Watch for incoming connections
sudo wg show wg0 | grep handshake
# Should show: latest handshake: X seconds ago (when successful)
```

4. **Check cloud firewall (OCI Security List):**
   - Go to OCI Console → Networking → Virtual Cloud Networks
   - Select your VCN → Security Lists
   - Verify ingress rule allows UDP port 51820 from 0.0.0.0/0

5. **Check server firewall:**
```bash
# UFW status
sudo ufw status numbered

# Should show:
# [ X] 51820/udp         ALLOW IN    Anywhere

# If not, add the rule:
sudo ufw allow 51820/udp
```

6. **Check IP forwarding:**
```bash
# Should return 1
cat /proc/sys/net/ipv4/ip_forward

# If it returns 0, enable it:
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -p
```

7. **Check NAT rules:**
```bash
# View NAT table
sudo iptables -t nat -L -n -v

# Should see MASQUERADE rule for wg0
# If not, add it:
sudo iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
```

### Issue 3: Wrong Network Interface in Config

**Problem:** The cloud-init script uses `ens3` for the network interface, but OCI might use a different name.

**Check the actual interface name:**
```bash
# List all network interfaces
ip addr show
# or
ip link show

# Common names: ens3, enp0s3, eth0
```

**Fix if interface is different:**
```bash
# Get the actual primary interface name (the one with public IP)
INTERFACE=$(ip route | grep default | awk '{print $5}')
echo "Primary interface: $INTERFACE"

# Update WireGuard config
sudo sed -i "s/ens3/$INTERFACE/g" /etc/wireguard/wg0.conf

# Restart WireGuard
sudo systemctl restart wg-quick@wg0
```

### Issue 4: Client Configuration Issues

**On the client side:**

1. **Verify endpoint is correct:**
```bash
# In your client config, ensure Endpoint matches:
Endpoint = 138.2.78.116:51820
```

2. **Check client logs (Linux):**
```bash
sudo journalctl -u wg-quick@wg0 -f
```

3. **Check client logs (macOS/Windows):**
   - Open WireGuard app → View Logs

4. **Test connectivity to server:**
```bash
# Test if port is reachable
nc -vuz 138.2.78.116 51820
# or
nmap -sU -p 51820 138.2.78.116
```

### Issue 5: Key Mismatch

**Verify keys match:**

**On server:**
```bash
# Server's public key
sudo cat /etc/wireguard/server_public.key

# Client's public key (should be in wg0.conf)
sudo grep PublicKey /etc/wireguard/wg0.conf
```

**On client:**
- Your client config should have the server's public key in the `[Peer]` section
- Make sure there are no extra spaces or newlines in the keys

## Advanced Debugging

### Enable WireGuard Debug Logging

```bash
# Increase kernel logging
sudo modprobe wireguard
sudo dmesg -w | grep wireguard &

# In another terminal, try connecting from client
# Watch for kernel messages about WireGuard
```

### Packet Capture

```bash
# Capture traffic on port 51820
sudo tcpdump -i any -n udp port 51820 -v

# In another terminal/client, try to connect
# You should see UDP packets if client is reaching the server
```

### Check Cloud-Init Completion

```bash
# Verify cloud-init finished successfully
sudo tail -f /var/log/cloud-init-output.log

# Check for the completion marker
ls -la /var/log/wireguard-setup-complete

# If setup didn't complete, check for errors
sudo grep -i error /var/log/cloud-init-output.log
```

## Complete Reset (If Nothing Works)

```bash
# Stop WireGuard
sudo systemctl stop wg-quick@wg0

# Remove configuration
sudo rm -f /etc/wireguard/wg0.conf

# Regenerate keys
sudo wg genkey | sudo tee /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key
sudo chmod 600 /etc/wireguard/server_private.key

# Get the correct network interface
INTERFACE=$(ip route | grep default | awk '{print $5}')
PRIVATE_KEY=$(sudo cat /etc/wireguard/server_private.key)

# Create new config with correct interface
sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE
EOF

sudo chmod 600 /etc/wireguard/wg0.conf

# Start WireGuard
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0

# Display server public key for client configuration
echo "Server public key (use this in your client config):"
sudo cat /etc/wireguard/server_public.key
```

## Step-by-Step Handshake Test

1. **On server - watch for connections:**
```bash
watch -n 1 'sudo wg show'
```

2. **On client - attempt connection:**
```bash
# Start your WireGuard connection
sudo wg-quick up wg0
# or use the WireGuard GUI
```

3. **Look for these indicators of success:**
   - `latest handshake:` should show recent timestamp
   - `transfer:` should show bytes sent/received
   - You should be able to ping the server through VPN: `ping 10.8.0.1`

## Quick Health Check Script

Run this on the server:

```bash
#!/bin/bash
echo "=== WireGuard Status ==="
sudo systemctl status wg-quick@wg0 | grep Active

echo -e "\n=== WireGuard Interface ==="
sudo wg show

echo -e "\n=== IP Forwarding ==="
cat /proc/sys/net/ipv4/ip_forward

echo -e "\n=== Listening Port ==="
sudo ss -ulnp | grep 51820

echo -e "\n=== Network Interface ==="
ip route | grep default

echo -e "\n=== Firewall Status ==="
sudo ufw status | grep 51820

echo -e "\n=== NAT Rules ==="
sudo iptables -t nat -L POSTROUTING -n | grep MASQUERADE

echo -e "\n=== Server Public Key ==="
sudo cat /etc/wireguard/server_public.key
```

Save this as `wg-debug.sh`, make it executable with `chmod +x wg-debug.sh`, and run it.

## Still Having Issues?

If none of the above works, provide this information:

1. Output of `sudo wg show`
2. Output of `sudo journalctl -u wg-quick@wg0 -n 50`
3. Output of `ip addr show`
4. Client configuration (with private key redacted)
5. Cloud provider firewall rules screenshot
