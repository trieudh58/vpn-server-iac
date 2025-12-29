# Changelog

## [Latest] - 2025-12-29

### Fixed - OCI iptables REJECT Rule Issue

**Problem:**
Oracle Cloud Infrastructure adds a default iptables REJECT rule in the INPUT chain that blocks all traffic before UFW rules can allow it. This caused WireGuard handshake failures even though UFW was configured correctly.

**Root Cause:**
```
Chain INPUT (policy ACCEPT)
...
4. ACCEPT     tcp  --  anywhere             anywhere             state NEW tcp dpt:ssh
5. REJECT     all  --  anywhere             anywhere             reject-with icmp-host-prohibited  ← BLOCKS EVERYTHING
6. ufw-before-logging-input  all  --  anywhere             anywhere
7. ufw-before-input  all  --  anywhere             anywhere  ← UFW rules never reached
```

**Solution:**
The cloud-init script now automatically:

1. **Detects** the OCI REJECT rule in the INPUT chain
2. **Inserts** WireGuard/VPN allow rules BEFORE the REJECT rule:
   - UDP 51820 (WireGuard)
   - TCP 1194 (OpenVPN)
   - UDP 1194 (OpenVPN)
3. **Persists** the rules across reboots using `netfilter-persistent`

**Changes Made:**

### cloud-init.yaml
- Added `iptables-persistent` and `netfilter-persistent` packages
- Added script to detect and fix OCI REJECT rule:
  - Finds line number of REJECT rule
  - Inserts VPN allow rules before it
  - Saves rules to persist across reboots
- Rules are inserted with comments for easy identification

### Documentation
- **README.md**: Added OCI iptables fix information
- **WIREGUARD-TROUBLESHOOTING.md**: Added note about automatic fix
- **verify-setup.sh**: New verification script to check all components
- **CHANGELOG.md**: This file

### Files Created
- `verify-setup.sh` - Comprehensive setup verification script
- `CHANGELOG.md` - This changelog

**Testing:**
Verified on fresh OCI Ubuntu 24.04 deployment. WireGuard handshakes now succeed immediately after cloud-init completes.

**Backward Compatibility:**
The fix is safe for non-OCI deployments - if no REJECT rule is found, the script simply appends the rules normally.

---

## Initial Release

### Features
- Terraform configuration for OCI deployment
- Ubuntu 24.04 with VM.Standard.E2.1.Micro shape
- Automatic WireGuard installation and configuration
- Cloud-init based setup
- Helper script for adding clients
- QR code generation for mobile clients
- Comprehensive documentation
