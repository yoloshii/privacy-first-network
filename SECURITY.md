# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in the scripts, configurations, or documentation that could compromise a user's network security or privacy, please report it responsibly.

**Report via:** Open a [GitHub issue](../../issues/new) with the title prefix `[SECURITY]`

Since this project contains configuration guides and shell scripts (not a running service), most security issues are safe to disclose publicly. However, if the issue involves:
- A way to bypass the kill switch that isn't obvious
- A credential or secret leak in the repository
- A flaw that could expose users' real IP addresses

Please email the maintainer first and allow 48 hours before public disclosure.

## Scope

Security-relevant areas of this project:

| Component | Security Impact |
|-----------|----------------|
| Kill switch (firewall rules) | Traffic leak if misconfigured |
| Watchdog scripts | Could restart tunnel without proper routing |
| Bootstrap DNS config | DNS leak if pointing to public DNS |
| Bypass routing rules | Could expose bypass devices if table 100 incomplete |
| AdGuard AAAA settings | IPv6 leak if AAAA not disabled |
| `.gitignore` patterns | Could fail to exclude secrets from commits |

## Not in Scope

- VPN provider security (Mullvad, IVPN, etc.) — report to them directly
- OpenWrt vulnerabilities — report to [openwrt.org](https://openwrt.org/security)
- AmneziaWG protocol issues — report to [amnezia-vpn](https://github.com/amnezia-vpn)
- User misconfiguration — use the troubleshooting guide

## Security Design Principles

This stack follows defense-in-depth:

1. **Kill switch** — No lan-to-wan forwarding rule (routing + firewall double protection)
2. **DNS leak prevention** — Bootstrap DNS uses VPN provider, AAAA disabled, external DNS blocked
3. **IPv6 disabled** — Kernel, UCI, firewall, and DNS layers
4. **Secrets never committed** — `.gitignore` excludes `.env`, `.conf`, keys
5. **Scripts fail closed** — If VPN can't connect, traffic is blocked (not leaked)
