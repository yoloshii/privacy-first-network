## What does this PR do?

<!-- Brief description of the change -->

## Type of change

- [ ] Bug fix (scripts, configs, or documentation)
- [ ] New feature (new script, config template, or deployment option)
- [ ] Documentation improvement
- [ ] New VPN provider support
- [ ] Deployment report / hardware support

## Testing

- **Hardware tested on:** <!-- e.g., Pi 5, x86, Docker -->
- **OpenWrt version:** <!-- e.g., 23.05.5 -->
- **VPN provider:** <!-- e.g., Mullvad -->

### Verification steps

- [ ] VPN connects and shows correct exit IP
- [ ] Kill switch tested (VPN down = no internet)
- [ ] Watchdog recovers from simulated failure
- [ ] Bypass routing works (if modified)
- [ ] No secrets or personal data in the diff

## Checklist

- [ ] I've tested this on actual hardware (not just reviewed the code)
- [ ] Shell scripts use `#!/bin/sh` (POSIX, not bash)
- [ ] No hardcoded IPs, keys, or environment-specific values
- [ ] Commit messages follow conventional format
