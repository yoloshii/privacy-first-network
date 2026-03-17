---
name: Bug Report
about: Something isn't working as documented
title: ''
labels: bug
assignees: ''
---

## Environment

- **Hardware:** (e.g., Raspberry Pi 5, x86 mini PC, VM on Proxmox)
- **OpenWrt version:** (e.g., 23.05.5)
- **VPN provider:** (e.g., Mullvad, IVPN)
- **Deployment option:** (A: Dedicated hardware / B: VM / C: Docker)
- **AmneziaWG package version:** (`opkg info amneziawg-tools`)

## What happened?

<!-- Describe the issue clearly -->

## What did you expect?

<!-- What should have happened instead -->

## Steps to reproduce

1.
2.
3.

## Diagnostic output

<!-- Run these and paste the output: -->

```bash
# VPN status
awg show awg0

# Routes
ip route
ip route show table 100

# Bypass rules (if applicable)
ip rule show | grep 100

# Watchdog status
ps | grep awg-watchdog
tail -20 /var/log/awg-watchdog.log

# Relevant logs
logread | grep -E "awg|watchdog" | tail -30
```

## Additional context

<!-- Screenshots, config snippets (redact private keys!), etc. -->
