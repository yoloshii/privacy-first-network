#!/bin/bash
# =============================================================================
# AmneziaWG Obfuscation Profiles (Shared)
# =============================================================================
# Unified profile system for all deployment types (OpenWrt, Docker, systemd)
#
# Usage:
#   source /path/to/awg-profiles.sh
#   AWG_PROFILE=quic
#   apply_awg_profile /etc/amneziawg/awg0.conf /tmp/awg0.runtime.conf
#
# Profiles:
#   basic   - Junk packets + header obfuscation (default)
#   quic    - QUIC/HTTP3 protocol mimic (high DPI resistance)
#   dns     - DNS query protocol mimic
#   sip     - SIP/VoIP protocol mimic
#   stealth - Maximum obfuscation (QUIC + aggressive junk)
#
# Official AWG Parameters (from amnezia-vpn/amneziawg-tools):
#   I1-I5  - Init packet specs (hex blobs sent before handshake)
#   Jc     - Junk packet count
#   Jmin   - Min junk packet size
#   Jmax   - Max junk packet size
#   S1-S4  - Packet padding sizes
#   H1-H4  - Magic header values
#
# NOT Official (wgtunnel-only, will cause errors):
#   j1, itime - DO NOT USE
# =============================================================================

# Profile hex blobs (AmneziaWG 1.5 protocol mimic)
# These are injected as I1/I2 parameters (UPPERCASE per official spec)
# QUIC blob from official AmneziaVPN docs (https://amneziavpn.org/documentation/instructions/new-amneziawg-selfhosted)

AWG_QUIC_I1='<b 0xc70000000108ce1bf31eec7d93360000449e227e4596ed7f75c4d35ce31880b4133107c822c6355b51f0d7c1bba96d5c210a48aca01885fed0871cfc37d59137d73b506dc013bb4a13c060ca5b04b7ae215af71e37d6e8ff1db235f9fe0c25cb8b492471054a7c8d0d6077d430d07f6e87a8699287f6e69f54263c7334a8e144a29851429bf2e350e519445172d36953e96085110ce1fb641e5efad42c0feb4711ece959b72cc4d6f3c1e83251adb572b921534f6ac4b10927167f41fe50040a75acef62f45bded67c0b45b9d655ce374589cad6f568b8475b2e8921ff98628f86ff2eb5bcce6f3ddb7dc89e37c5b5e78ddc8d93a58896e530b5f9f1448ab3b7a1d1f24a63bf981634f6183a21af310ffa52e9ddf5521561760288669de01a5f2f1a4f922e68d0592026bbe4329b654d4f5d6ace4f6a23b8560b720a5350691c0037b10acfac9726add44e7d3e880ee6f3b0d6429ff33655c297fee786bb5ac032e48d2062cd45e305e6d8d8b82bfbf0fdbc5ec09943d1ad02b0b5868ac4b24bb10255196be883562c35a713002014016b8cc5224768b3d330016cf8ed9300fe6bf39b4b19b3667cddc6e7c7ebe4437a58862606a2a66bd4184b09ab9d2cd3d3faed4d2ab71dd821422a9540c4c5fa2a9b2e6693d411a22854a8e541ed930796521f03a54254074bc4c5bca152a1723260e7d70a24d49720acc544b41359cfc252385bda7de7d05878ac0ea0343c77715e145160e6562161dfe2024846dfda3ce99068817a2418e66e4f37dea40a21251c8a034f83145071d93baadf050ca0f95dc9ce2338fb082d64fbc8faba905cec66e65c0e1f9b003c32c943381282d4ab09bef9b6813ff3ff5118623d2617867e25f0601df583c3ac51bc6303f79e68d8f8de4b8363ec9c7728b3ec5fcd5274edfca2a42f2727aa223c557afb33f5bea4f64aeb252c0150ed734d4d8eccb257824e8e090f65029a3a042a51e5cc8767408ae07d55da8507e4d009ae72c47ddb138df3cab6cc023df2532f88fb5a4c4bd917fafde0f3134be09231c389c70bc55cb95a779615e8e0a76a2b4d943aabfde0e394c985c0cb0376930f92c5b6998ef49ff4a13652b787503f55c4e3d8eebd6e1bc6db3a6d405d8405bd7a8db7cefc64d16e0d105a468f3d33d29e5744a24c4ac43ce0eb1bf6b559aed520b91108cda2de6e2c4f14bc4f4dc58712580e07d217c8cca1aaf7ac04bab3e7b1008b966f1ed4fba3fd93a0a9d3a27127e7aa587fbcc60d548300146bdc126982a58ff5342fc41a43f83a3d2722a26645bc961894e339b953e78ab395ff2fb854247ad06d446cc2944a1aefb90573115dc198f5c1efbc22bc6d7a74e41e666a643d5f85f57fde81b87ceff95353d22ae8bab11684180dd142642894d8dc34e402f802c2fd4a73508ca99124e428d67437c871dd96e506ffc39c0fc401f666b437adca41fd563cbcfd0fa22fbbf8112979c4e677fb533d981745cceed0fe96da6cc0593c430bbb71bcbf924f70b4547b0bb4d41c94a09a9ef1147935a5c75bb2f721fbd24ea6a9f5c9331187490ffa6d4e34e6bb30c2c54a0344724f01088fb2751a486f425362741664efb287bce66c4a544c96fa8b124d3c6b9eaca170c0b530799a6e878a57f402eb0016cf2689d55c76b2a91285e2273763f3afc5bc9398273f5338a06d>'

AWG_DNS_I1='<b 0x123401000001000000000000076578616d706c6503636f6d0000010001>'

AWG_SIP_I1='<b 0x494e56495445207369703a626f624062696c6f78692e636f6d205349502f322e300d0a5669613a205349502f322e302f5544502070633333>'
AWG_SIP_I2='<b 0x5349502f322e302031303020547279696e670d0a5669613a205349502f322e302f5544502070633333>'

# =============================================================================
# apply_awg_profile - Generate runtime config with profile-specific parameters
# =============================================================================
# Arguments:
#   $1 - Source config file (e.g., /etc/amneziawg/awg0.conf)
#   $2 - Output runtime config (e.g., /tmp/awg0.runtime.conf)
#   $3 - Profile name (optional, uses AWG_PROFILE env var if not set)
#
# Returns:
#   0 on success, 1 on error
#   Sets AWG_RUNTIME_CONFIG to output path
# =============================================================================
apply_awg_profile() {
    local source_config="$1"
    local runtime_config="$2"
    local profile="${3:-${AWG_PROFILE:-basic}}"

    # Validate source exists
    if [[ ! -f "$source_config" ]]; then
        echo "Error: Source config not found: $source_config" >&2
        return 1
    fi

    # Create runtime config directory if needed
    mkdir -p "$(dirname "$runtime_config")" 2>/dev/null || true

    # Start with base config
    cp "$source_config" "$runtime_config"

    # Apply profile-specific parameters
    case "$profile" in
        basic)
            # Default profile - base config already has Jc/Jmin/Jmax/H1-H4
            echo "# Profile: basic (junk packets + header obfuscation)" >> "$runtime_config"
            ;;

        quic)
            # QUIC protocol mimic - appears as HTTP/3 traffic
            cat >> "$runtime_config" << EOF

# Profile: quic (QUIC/HTTP3 protocol mimic)
# Injects QUIC Long Header Initial packet signature
# Official I1 param from AmneziaVPN docs (0xc7 header byte)
I1 = $AWG_QUIC_I1
EOF
            ;;

        dns)
            # DNS query mimic - appears as DNS resolution
            cat >> "$runtime_config" << EOF

# Profile: dns (DNS query protocol mimic)
# Injects DNS query packet signature
I1 = $AWG_DNS_I1
EOF
            ;;

        sip)
            # SIP/VoIP mimic - appears as voice traffic
            cat >> "$runtime_config" << EOF

# Profile: sip (SIP/VoIP protocol mimic)
# Injects SIP INVITE packet signature
I1 = $AWG_SIP_I1
I2 = $AWG_SIP_I2
EOF
            ;;

        stealth)
            # Maximum obfuscation - QUIC + aggressive junk
            cat >> "$runtime_config" << EOF

# Profile: stealth (maximum obfuscation)
# QUIC mimic + aggressive junk packet settings
Jc = 16
Jmin = 100
Jmax = 200
I1 = $AWG_QUIC_I1
EOF
            ;;

        *)
            echo "Warning: Unknown profile '$profile', using basic" >&2
            echo "# Profile: basic (unknown profile fallback)" >> "$runtime_config"
            ;;
    esac

    # Export for use by calling script
    export AWG_RUNTIME_CONFIG="$runtime_config"
    return 0
}

# =============================================================================
# get_awg_profile_description - Get human-readable profile description
# =============================================================================
get_awg_profile_description() {
    local profile="${1:-${AWG_PROFILE:-basic}}"

    case "$profile" in
        basic)   echo "basic (junk packets + header obfuscation)" ;;
        quic)    echo "quic (QUIC/HTTP3 protocol mimic)" ;;
        dns)     echo "dns (DNS query protocol mimic)" ;;
        sip)     echo "sip (SIP/VoIP protocol mimic)" ;;
        stealth) echo "stealth (maximum obfuscation)" ;;
        *)       echo "$profile (unknown)" ;;
    esac
}

# =============================================================================
# list_awg_profiles - List available profiles
# =============================================================================
list_awg_profiles() {
    cat << 'EOF'
Available AmneziaWG obfuscation profiles:

  basic   - Junk packets + header obfuscation (default)
            Works everywhere, minimal overhead

  quic    - QUIC/HTTP3 protocol mimic
            High DPI resistance, traffic appears as HTTP/3

  dns     - DNS query protocol mimic
            Traffic appears as DNS resolution

  sip     - SIP/VoIP protocol mimic
            Traffic appears as voice/video calls

  stealth - Maximum obfuscation
            QUIC mimic + aggressive junk packets (Jc=16)

All profiles work with standard WireGuard servers (Mullvad, IVPN, Proton, etc.)
EOF
}
