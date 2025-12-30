#!/bin/bash
# WireGuard Setup Verification Script

echo "=========================================="
echo "WireGuard Setup Verification"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
}

echo ""
echo "Checking WireGuard configuration..."
echo ""

# Check 1: WireGuard service running
if systemctl is-active --quiet wg-quick@wg0; then
    pass "WireGuard service is running"
else
    fail "WireGuard service is not running"
    echo "  Try: sudo systemctl start wg-quick@wg0"
fi

# Check 2: WireGuard interface exists
if ip link show wg0 &>/dev/null; then
    pass "WireGuard interface (wg0) exists"
else
    fail "WireGuard interface (wg0) not found"
fi

# Check 3: Port listening
if ss -ulnp | grep -q ":51820"; then
    pass "WireGuard listening on port 51820"
else
    fail "WireGuard not listening on port 51820"
fi

# Check 4: IP forwarding
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" == "1" ]; then
    pass "IP forwarding enabled"
else
    fail "IP forwarding disabled"
    echo "  Try: sudo sysctl -w net.ipv4.ip_forward=1"
fi

# Check 5: OCI iptables REJECT rule fixed
REJECT_LINE=$(sudo iptables -L INPUT --line-numbers | grep -m 1 "REJECT.*icmp-host-prohibited" | awk '{print $1}')
if [ -n "$REJECT_LINE" ]; then
    # Get all WireGuard/OpenVPN rule line numbers
    WG_LINES=$(sudo iptables -L INPUT --line-numbers | grep -E "(51820|1194)" | awk '{print $1}' | tr '\n' ' ')
    # Get the first (lowest) WireGuard rule line number
    FIRST_WG_LINE=$(sudo iptables -L INPUT --line-numbers | grep -E "(51820|1194)" | head -1 | awk '{print $1}')

    if [ -n "$FIRST_WG_LINE" ] && [ "$FIRST_WG_LINE" -lt "$REJECT_LINE" ]; then
        pass "VPN rules inserted before OCI REJECT rule (lines: $WG_LINES < $REJECT_LINE)"
    else
        fail "VPN rules NOT before OCI REJECT rule"
        echo "  REJECT at line: $REJECT_LINE, VPN rules at lines: ${WG_LINES:-not found}"
        echo "  Fix: sudo iptables -I INPUT $REJECT_LINE -p udp --dport 51820 -j ACCEPT"
        echo "       sudo iptables -I INPUT $REJECT_LINE -p tcp --dport 1194 -j ACCEPT"
        echo "       sudo iptables -I INPUT $REJECT_LINE -p udp --dport 1194 -j ACCEPT"
    fi
else
    warn "No OCI REJECT rule found (might not be using OCI Ubuntu image)"
fi

# Check 6: Firewall status (using iptables directly)
WG_IPTABLES=$(sudo iptables -L INPUT -n | grep "51820" | wc -l)
if [ "$WG_IPTABLES" -gt 0 ]; then
    pass "iptables allows WireGuard port 51820"
else
    fail "iptables not configured for WireGuard"
    echo "  Try: sudo iptables -A INPUT -p udp --dport 51820 -j ACCEPT"
fi

# Check 7: FORWARD rules for WireGuard
FORWARD_WG=$(sudo iptables -L FORWARD -n | grep "wg0" | wc -l)
if [ "$FORWARD_WG" -ge 2 ]; then
    pass "FORWARD rules configured for WireGuard interface"
else
    fail "FORWARD rules missing for WireGuard"
    echo "  Try: sudo iptables -A FORWARD -i wg0 -j ACCEPT"
    echo "       sudo iptables -A FORWARD -o wg0 -j ACCEPT"
fi

# Check 8: NAT/MASQUERADE rules
if sudo iptables -t nat -L POSTROUTING -n | grep -q "MASQUERADE"; then
    pass "NAT MASQUERADE rule exists"
else
    fail "NAT MASQUERADE rule missing"
fi

# Check 9: Server keys exist
if [ -f /etc/wireguard/server_public.key ] && [ -f /etc/wireguard/server_private.key ]; then
    pass "WireGuard server keys exist"
    echo ""
    echo "  Server Public Key: $(cat /etc/wireguard/server_public.key)"
else
    fail "WireGuard server keys not found"
fi

# Check 10: Helper script exists
if [ -x /usr/local/bin/add-wireguard-client ]; then
    pass "add-wireguard-client helper script installed"
else
    fail "add-wireguard-client helper script not found"
fi

# Check 11: Cloud-init completed
if [ -f /var/log/wireguard-setup-complete ]; then
    pass "Cloud-init setup completed successfully"
else
    warn "Cloud-init setup marker not found (might still be running)"
    echo "  Check: sudo tail -f /var/log/cloud-init-output.log"
fi

echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="

# Show WireGuard status
echo ""
echo "WireGuard Interface Status:"
sudo wg show

# Show network interface
echo ""
echo "Network Configuration:"
echo "  Primary interface: $(ip route | grep default | awk '{print $5}')"
echo "  Public IP: $(curl -s ifconfig.me 2>/dev/null || echo "Unable to fetch")"

# Show peers
PEER_COUNT=$(sudo wg show wg0 peers 2>/dev/null | wc -l)
echo "  Configured peers: $PEER_COUNT"

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Add a client:"
echo "   sudo /usr/local/bin/add-wireguard-client <client-name>"
echo ""
echo "2. Monitor connections:"
echo "   watch -n 1 'sudo wg show'"
echo ""
echo "3. View logs:"
echo "   sudo journalctl -u wg-quick@wg0 -f"
echo ""
echo "=========================================="
