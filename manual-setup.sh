#!/bin/bash
# Manual WireGuard Setup Script
# Run this on your existing instance to complete the setup

set -e

echo "=========================================="
echo "Manual WireGuard Setup"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Install missing packages
log "Installing required packages..."
apt update
apt install -y wireguard qrencode iptables iptables-persistent netfilter-persistent

# Enable IP forwarding
log "Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# Create WireGuard directory
log "Setting up WireGuard directory..."
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Generate keys (if not exist)
if [ ! -f /etc/wireguard/server_private.key ]; then
    log "Generating WireGuard keys..."
    wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
    chmod 600 /etc/wireguard/server_private.key
    chmod 644 /etc/wireguard/server_public.key
else
    log "WireGuard keys already exist"
fi

# Create WireGuard configuration
log "Creating WireGuard configuration..."
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $(cat /etc/wireguard/server_private.key)
PostUp = iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE

# Add client configurations below
# [Peer]
# PublicKey = CLIENT_PUBLIC_KEY
# AllowedIPs = 10.8.0.2/32
EOF

chmod 600 /etc/wireguard/wg0.conf

# Configure iptables rules
log "Configuring iptables rules..."
sleep 2

# Find REJECT rule and insert rules before it
REJECT_LINE=$(iptables -L INPUT --line-numbers | grep -m 1 "REJECT.*icmp-host-prohibited" | awk '{print $1}')

if [ -n "$REJECT_LINE" ]; then
    log "Inserting INPUT rules before OCI REJECT rule at line $REJECT_LINE"
    iptables -I INPUT $REJECT_LINE -p udp --dport 51820 -j ACCEPT -m comment --comment "WireGuard VPN"
    iptables -I INPUT $REJECT_LINE -p tcp --dport 1194 -j ACCEPT -m comment --comment "OpenVPN TCP"
    iptables -I INPUT $REJECT_LINE -p udp --dport 1194 -j ACCEPT -m comment --comment "OpenVPN UDP"
else
    warn "No OCI REJECT rule found, appending INPUT rules..."
    iptables -A INPUT -p udp --dport 51820 -j ACCEPT -m comment --comment "WireGuard VPN"
    iptables -A INPUT -p tcp --dport 1194 -j ACCEPT -m comment --comment "OpenVPN TCP"
    iptables -A INPUT -p udp --dport 1194 -j ACCEPT -m comment --comment "OpenVPN UDP"
fi

# Add FORWARD rules before any REJECT rule in FORWARD chain
FORWARD_REJECT_LINE=$(iptables -L FORWARD --line-numbers | grep -m 1 "REJECT.*icmp-host-prohibited" | awk '{print $1}')
if [ -n "$FORWARD_REJECT_LINE" ]; then
    log "Inserting FORWARD rules before OCI REJECT rule at line $FORWARD_REJECT_LINE"
    iptables -I FORWARD $FORWARD_REJECT_LINE -i wg0 -j ACCEPT -m comment --comment "WireGuard input"
    iptables -I FORWARD $FORWARD_REJECT_LINE -o wg0 -j ACCEPT -m comment --comment "WireGuard output"
else
    log "No FORWARD REJECT rule found, appending FORWARD rules..."
    iptables -A FORWARD -i wg0 -j ACCEPT -m comment --comment "WireGuard input"
    iptables -A FORWARD -o wg0 -j ACCEPT -m comment --comment "WireGuard output"
fi

# Save iptables rules
log "Saving iptables rules..."
netfilter-persistent save
iptables-save > /etc/iptables/rules.v4

# Enable and start WireGuard
log "Starting WireGuard service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Create helper script
log "Creating client helper script..."
cat > /usr/local/bin/add-wireguard-client << 'SCRIPT'
#!/bin/bash
if [ -z "$1" ]; then
  echo "Usage: add-wireguard-client <client-name>"
  exit 1
fi

CLIENT_NAME=$1
SERVER_PUBLIC_IP=$(curl -s ifconfig.me)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)
CLIENT_IP="10.8.0.$(($(wg show wg0 peers | wc -l) + 2))"

# Add peer to server config
cat >> /etc/wireguard/wg0.conf << EOF

[Peer]
# $CLIENT_NAME
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_IP/32
EOF

# Restart WireGuard
systemctl restart wg-quick@wg0

# Generate client config
cat > /root/wireguard-$CLIENT_NAME.conf << EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

echo "Client configuration created: /root/wireguard-$CLIENT_NAME.conf"
echo "Server public key: $SERVER_PUBLIC_KEY"
echo "Client added successfully!"

# Generate QR code
qrencode -t ansiutf8 < /root/wireguard-$CLIENT_NAME.conf
SCRIPT

chmod +x /usr/local/bin/add-wireguard-client

# Create completion marker
touch /var/log/wireguard-setup-complete

log "Setup completed successfully!"
echo ""
echo "Run verification:"
echo "  sudo bash ~/verify-setup.sh"
echo ""
echo "Add a client:"
echo "  sudo /usr/local/bin/add-wireguard-client <client-name>"
