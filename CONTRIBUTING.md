# Contributing

Thanks for your interest in improving the privacy router stack. This project is primarily a configuration guide and deployment toolkit rather than a traditional software project, so contributions look a bit different.

## What We Need

### High-Value Contributions

- **Deployment reports** — Deployed on hardware not listed? Share your experience (device model, OpenWrt version, issues encountered, solutions found)
- **VPN provider configs** — Tested with a provider other than Mullvad? Submit example configs and provider-specific notes
- **Bug fixes in scripts** — Found an issue in the watchdog, hotplug, or other scripts? Fix it and explain what broke
- **Troubleshooting additions** — Encountered and solved an issue not covered in TROUBLESHOOTING.md? Document it
- **Docker improvements** — Better health checks, multi-arch support, compose enhancements

### Also Welcome

- Documentation clarity improvements
- Typo and formatting fixes
- New obfuscation profiles for `awg-profiles.sh`
- Translation of key docs

### Not Looking For

- Feature creep — this stack intentionally stays focused on VPN + kill switch + DNS
- CI/CD pipelines — there's no application to build or test programmatically
- Dependency additions — scripts use only standard OpenWrt/Linux tools

## How to Contribute

### For Documentation and Config Changes

1. Fork the repository
2. Create a branch (`git checkout -b fix/watchdog-timeout`)
3. Make your changes
4. Test if applicable (deploy on your hardware, verify the fix)
5. Submit a pull request with:
   - What you changed and why
   - How you tested it (hardware, OpenWrt version, VPN provider)

### For Bug Reports

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) and include:
- Your hardware (Pi 4/5, x86, VM)
- OpenWrt version
- VPN provider
- Relevant log output (`logread | grep awg`)

### For Deployment Reports

Open an issue with the "deployment report" label including:
- Hardware used
- OpenWrt version and architecture
- VPN provider
- Any modifications needed
- Performance observations

## Script Style

If modifying shell scripts:
- Use `#!/bin/sh` (POSIX sh, not bash) for OpenWrt compatibility
- Include comments explaining non-obvious logic
- Use `logger -t <tag>` for syslog output
- Handle errors gracefully (`2>/dev/null`, return codes)
- Test on OpenWrt — not all GNU coreutils flags are available (BusyBox)

## Commit Messages

Follow conventional commits:
```
fix(watchdog): increase handshake timeout for high-latency links
docs(troubleshooting): add AdGuard boot race condition section
feat(docker): add arm64 multi-arch build support
```

## Questions?

Open an issue. There's no discussion forum — issues are fine for questions.
