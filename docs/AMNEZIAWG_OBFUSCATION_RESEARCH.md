# AmneziaWG Obfuscation Research

Comprehensive analysis of AmneziaWG obfuscation patterns, protocol mimicry, and comparison with Mullvad obfuscation methods.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [AmneziaWG Parameter Reference](#amneziawg-parameter-reference)
3. [Protocol Mimic Feature (AWG 1.5)](#protocol-mimic-feature-awg-15)
4. [Mullvad Obfuscation Methods](#mullvad-obfuscation-methods)
5. [Compatibility Matrix](#compatibility-matrix)
6. [Implementation Recommendations](#implementation-recommendations)

---

## Executive Summary

### Key Findings

1. **AmneziaWG obfuscation is client-side only** - The obfuscation happens locally before packets leave the client. Standard WireGuard servers receive valid WireGuard packets after the client processes them.

2. **VPN providers don't provide AWG parameters** - Because their servers are standard WireGuard, providers like Mullvad, IVPN, and Proton don't distribute AmneziaWG-specific configuration values.

3. **wgtunnel compatibility mode is the gold standard** - The values `Jc=4, Jmin=40, Jmax=70, S1=0, S2=0, H1=1, H2=2, H3=3, H4=4` are tested and work with all standard WireGuard servers.

4. **AmneziaWG 1.5 adds protocol mimicry** - Extended parameters (i1-i5, j1-j3, itime) enable injection of protocol-signature packets (QUIC, DNS, SIP) to evade deep packet inspection.

5. **Mullvad QUIC ≠ AmneziaWG QUIC mimic** - Mullvad's QUIC obfuscation uses MASQUE tunneling (real QUIC-in-QUIC), requiring special servers. AmneziaWG's QUIC mimic injects QUIC-like packet headers client-side and works with any WireGuard server.

---

## AmneziaWG Parameter Reference

### Basic Parameters (AWG 1.0)

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| `Jc` | 1-128 | 4 | Junk packet count during handshake |
| `Jmin` | 0-1280 | 40 | Minimum junk packet size (bytes) |
| `Jmax` | 0-1280 | 70 | Maximum junk packet size (bytes) |
| `S1` | 0-2147483647 | 0 | Init packet junk size |
| `S2` | 0-2147483647 | 0 | Response packet junk size |
| `H1` | 0-2147483647 | 1 | Init packet magic header |
| `H2` | 0-2147483647 | 2 | Response packet magic header |
| `H3` | 0-2147483647 | 3 | Under-load packet magic header |
| `H4` | 0-2147483647 | 4 | Transport packet magic header |

### Extended Parameters (AWG 1.5)

| Parameter | Type | Description |
|-----------|------|-------------|
| `i1` | Hex blob | First special junk packet (protocol signature) |
| `i2` | Hex blob | Second special junk packet |
| `i3` | Hex blob | Third special junk packet |
| `i4` | Hex blob | Fourth special junk packet |
| `i5` | Hex blob | Fifth special junk packet |
| `j1` | Hex blob | First junk packet content |
| `j2` | Hex blob | Second junk packet content |
| `j3` | Hex blob | Third junk packet content |
| `itime` | Integer | Injection timing interval (ms) |

**Hex blob format:** `<b 0xHEXDATA>`

### Compatibility Configuration

From wgtunnel's `InterfaceProxy.kt`:

```kotlin
fun toAmneziaCompatibilityConfig(): InterfaceProxy {
    return copy(
        junkPacketCount = "4",
        junkPacketMinSize = "40",
        junkPacketMaxSize = "70",
        initPacketJunkSize = "0",
        responsePacketJunkSize = "0",
        initPacketMagicHeader = "1",
        responsePacketMagicHeader = "2",
        underloadPacketMagicHeader = "3",
        transportPacketMagicHeader = "4",
    )
}
```

**INI format:**
```ini
[Interface]
PrivateKey = YOUR_KEY
Jc = 4
Jmin = 40
Jmax = 70
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4
```

---

## Protocol Mimic Feature (AWG 1.5)

Protocol mimicry injects packets that resemble legitimate protocol traffic, making WireGuard connections harder to fingerprint.

### QUIC Mimic

Injects a QUIC Long Header Initial packet to make traffic appear as QUIC/HTTP3:

```kotlin
fun setQuicMimic(): InterfaceProxy {
    return copy(
        i1 = "<b 0xc1ff000012508394c8f03e51570800449f0dbc195a0000f3a694c75775b4e546172ce9e047cd0b5bee5181648c727adc87f7eae54473ec6cba6bdad4f59823174b769f12358abd292d4f3286934484fb8b239c38732e1f3bbbc6a003056487eb8b5c88b9fd9279ffff3b0f4ecf95c4624db6d65d4113329ee9b0bf8cdd7c8a8d72806d55df25ecb66488bc119d7c9a29abaf99bb33c56b08ad8c26995f838bb3b7a3d5c1858b8ec06b839db2dcf918d5ea9317f1acd6b663cc8925868e2f6a1bda546695f3c3f33175944db4a11a346afb07e78489e509b02add51b7b203eda5c330b03641179a31fbba9b56ce00f3d5b5e3d7d9c5429aebb9576f2f7eacbe27bc1b8082aaf68fb69c921aa5d33ec0c8510410865a178d86d7e54122d55ef2c2bbc040be46d7fece73fe8a1b24495ec160df2da9b20a7ba2f26dfa2a44366dbc63de5cd7d7c94c57172fe6d79c901f025c0010b02c89b395402c009f62dc053b8067a1e0ed0a1e0cf5087d7f78cbd94afe0c3dd55d2d4b1a5cfe2b68b86264e351d1dcd858783a240f893f008ceed743d969b8f735a1677ead960b1fb1ecc5ac83c273b49288d02d7286207e663c45e1a7baf50640c91e762941cf380ce8d79f3e86767fbbcd25b42ef70ec334835a3a6d792e170a432ce0cb7bde9aaa1e75637c1c34ae5fef4338f53db8b13a4d2df594efbfa08784543815c9c0d487bddfa1539bc252cf43ec3686e9802d651cfd2a829a06a9f332a733a4a8aed80efe3478093fbc69c8608146b3f16f1a5c4eac9320da49f1afa5f538ddecbbe7888f435512d0dd74fd9b8c99e3145ba84410d8ca9a36dd884109e76e5fb8222a52e1473da168519ce7a8a3c32e9149671b16724c6c5c51bb5cd64fb591e567fb78b10f9f6fee62c276f282a7df6bcf7c17747bc9a81e6c9c3b032fdd0e1c3ac9eaa5077de3ded18b2ed4faf328f49875af2e36ad5ce5f6cc99ef4b60e57b3b5b9c9fcbcd4cfb3975e70ce4c2506bcd71fef0e53592461504e3d42c885caab21b782e26294c6a9d61118cc40a26f378441ceb48f31a362bf8502a723a36c63502229a462cc2a3796279a5e3a7f81a68c7f81312c381cc16a4ab03513a51ad5b54306ec1d78a5e47e2b15e5b7a1438e5b8b2882dbdad13d6a4a8c3558cae043501b68eb3b040067152>",
        i2 = "<b 0x0000000000010000000000000000000000000000000000000000000000000000>",
        j1 = "<b 0x1234567890abcdef>",
        itime = "120",
    )
}
```

**Packet breakdown:**
- `0xc1` - QUIC Long Header form bit + fixed bit
- `0xff000012` - Version (draft-18 or similar)
- Connection IDs and encrypted payload follow

### DNS Mimic

Injects a DNS query packet to disguise traffic as DNS resolution:

```kotlin
fun setDnsMimic(): InterfaceProxy {
    return copy(
        i1 = "<b 0x123401000001000000000000076578616d706c6503636f6d0000010001>",
        itime = "120",
    )
}
```

**Packet breakdown:**
- `0x1234` - Transaction ID
- `0x0100` - Standard query flags
- `0x0001` - 1 question
- `example.com` - Query domain (encoded)
- `0x0001` - Type A (IPv4)
- `0x0001` - Class IN

### SIP Mimic

Injects SIP INVITE packets to appear as VoIP traffic:

```kotlin
fun setSipMimic(): InterfaceProxy {
    return copy(
        i1 = "<b 0x494e56495445207369703a626f624062696c6f78692e636f6d205349502f322e300d0a5669613a205349502f322e302f5544502070633333...>",
        i2 = "<b 0x5349502f322e302031303020547279696e670d0a5669613a205349502f322e302f5544502070633333...>",
        j1 = "<b 0xabcdef1234567890>",
        itime = "120",
    )
}
```

**Decoded i1 (partial):**
```
INVITE sip:bob@biloxi.com SIP/2.0
Via: SIP/2.0/UDP pc33...
```

### Official AmneziaWG QUIC Signature

From amneziavpn.org documentation (differs slightly from wgtunnel):

```
I1 = <b 0xc700000100081dcb44ae49f6d32f0820606c4f6d6d3fc3d7d1a43cd0000048040010000000010000000502034682007b1e...>
```

Both signatures are valid QUIC Initial packets captured from different sources. The key is the `0xc_` prefix indicating QUIC Long Header format.

---

## Mullvad Obfuscation Methods

### QUIC Tunneling (MASQUE)

**Technology:** RFC 9298 CONNECT-UDP over HTTP/3

**How it works:**
1. Client establishes real QUIC connection to Mullvad relay
2. WireGuard packets are encapsulated inside QUIC UDP proxying
3. Traffic appears as legitimate QUIC/HTTP3 to censors
4. Relay decapsulates and forwards to WireGuard server

**Requirements:**
- Special Mullvad QUIC relay servers
- Custom client implementation
- NOT compatible with standard WireGuard servers

**Availability:** iOS app, Desktop apps (2024)

### Lightweight WireGuard Obfuscation (LWO)

**Technology:** In-place header scrambling

**How it works:**
1. XOR scrambling of WireGuard packet headers
2. Shared secret between client and server
3. Headers descrambled at server before processing
4. Minimal overhead (~0.01ms latency)

**Requirements:**
- Mullvad LWO-enabled servers
- NOT compatible with standard WireGuard

### Shadowsocks (Deprecated)

**Technology:** AEAD cipher proxy (chacha20-ietf-poly1305)

**Status:** Mullvad discontinued this in favor of QUIC tunneling

### UDP-over-TCP (Deprecated)

**Technology:** UDP encapsulation in TCP stream

**Status:** Phased out due to TCP-over-TCP performance issues

---

## Compatibility Matrix

| Method | Standard WG Server | Special Server | DPI Resistance | Performance |
|--------|-------------------|----------------|----------------|-------------|
| AWG Basic (Jc, H1-H4) | ✅ Yes | Not needed | Medium | Excellent |
| AWG QUIC Mimic | ✅ Yes | Not needed | High | Excellent |
| AWG DNS Mimic | ✅ Yes | Not needed | Medium | Excellent |
| AWG SIP Mimic | ✅ Yes | Not needed | Medium | Excellent |
| Mullvad QUIC | ❌ No | ✅ Required | Very High | Good |
| Mullvad LWO | ❌ No | ✅ Required | High | Excellent |

### Key Distinction

```
┌─────────────────────────────────────────────────────────────────┐
│                    AmneziaWG Protocol Mimic                     │
│  ┌──────────┐    ┌─────────────┐    ┌────────────────────────┐  │
│  │  Client  │───►│ Inject QUIC │───►│ Standard WG Server     │  │
│  │          │    │ Header      │    │ (Sees valid WG packet) │  │
│  └──────────┘    └─────────────┘    └────────────────────────┘  │
│                                                                 │
│  Packet: [QUIC-like header] + [Valid WireGuard payload]         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Mullvad QUIC Tunneling                       │
│  ┌──────────┐    ┌─────────────┐    ┌────────────────────────┐  │
│  │  Client  │───►│ Real QUIC   │───►│ Mullvad QUIC Relay     │  │
│  │          │    │ Connection  │    │ (Decapsulates to WG)   │  │
│  └──────────┘    └─────────────┘    └──────────┬─────────────┘  │
│                                                │                │
│                                     ┌──────────▼─────────────┐  │
│                                     │ WireGuard Server       │  │
│                                     └────────────────────────┘  │
│                                                                 │
│  Packet: [Real QUIC] containing [Proxied UDP with WG payload]   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Recommendations

### For This Project (Privacy Router)

**Recommended configuration:**

```ini
[Interface]
PrivateKey = YOUR_KEY

# Basic obfuscation (works with any WireGuard server)
Jc = 4
Jmin = 40
Jmax = 70
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = server:51820
PersistentKeepalive = 25
```

**For environments with aggressive DPI (add protocol mimic):**

```ini
[Interface]
PrivateKey = YOUR_KEY

# Basic obfuscation
Jc = 4
Jmin = 40
Jmax = 70
S1 = 0
S2 = 0
H1 = 1
H2 = 2
H3 = 3
H4 = 4

# QUIC protocol mimic (AWG 1.5)
i1 = <b 0xc1ff000012508394c8f03e51570800449f...>
i2 = <b 0x0000000000010000000000000000000000000000000000000000000000000000>
j1 = <b 0x1234567890abcdef>
itime = 120

[Peer]
...
```

### Parameter Tuning Guide

| Environment | Jc | Jmin/Jmax | Protocol Mimic |
|-------------|-----|-----------|----------------|
| Light DPI (home ISP) | 4 | 40/70 | Not needed |
| Moderate DPI (corporate) | 8 | 50/100 | Optional |
| Heavy DPI (restrictive regions) | 16 | 100/200 | QUIC recommended |
| Maximum stealth | 32+ | 200/500 | QUIC + high itime |

### Cannot Convert Mullvad QUIC to AmneziaWG

Mullvad's QUIC obfuscation **cannot** be replicated with AmneziaWG because:

1. **Architecture difference**: Mullvad uses real QUIC tunneling (MASQUE), not header injection
2. **Server requirement**: MASQUE requires a decapsulating relay server
3. **Protocol depth**: Real QUIC includes TLS handshake, stream multiplexing, congestion control

AmneziaWG's QUIC mimic only adds QUIC-like packet headers to make DPI fingerprinting harder. It does not create actual QUIC connections.

**Bottom line:** Use AmneziaWG QUIC mimic for client-side obfuscation with any WireGuard server. Use Mullvad's native QUIC tunneling only with Mullvad's infrastructure.

---

## Sources

1. **wgtunnel** - https://github.com/zaneschepke/wgtunnel
   - `InterfaceProxy.kt` - Complete AmneziaWG implementation
   - Changelog v40000 - AmneziaWG 1.5 protocol mimic announcement

2. **AmneziaVPN Official** - https://amneziavpn.org/documentation
   - AmneziaWG 1.5 parameter documentation
   - Official QUIC signature values

3. **Mullvad Blog** - https://mullvad.net/blog
   - QUIC tunneling announcement (2024)
   - LWO technical details

4. **RFC 9298** - CONNECT-UDP HTTP method (MASQUE foundation)

---

*Last updated: 2025-12-01*
*Research conducted for privacy-router project*
