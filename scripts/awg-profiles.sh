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
# Source: wgtunnel (https://github.com/zaneschepke/wgtunnel)
# =============================================================================

# Profile hex blobs (AmneziaWG 1.5 protocol mimic)
# These are injected as i1/i2/j1/itime parameters

AWG_QUIC_I1='<b 0xc1ff000012508394c8f03e51570800449f0dbc195a0000f3a694c75775b4e546172ce9e047cd0b5bee5181648c727adc87f7eae54473ec6cba6bdad4f59823174b769f12358abd292d4f3286934484fb8b239c38732e1f3bbbc6a003056487eb8b5c88b9fd9279ffff3b0f4ecf95c4624db6d65d4113329ee9b0bf8cdd7c8a8d72806d55df25ecb66488bc119d7c9a29abaf99bb33c56b08ad8c26995f838bb3b7a3d5c1858b8ec06b839db2dcf918d5ea9317f1acd6b663cc8925868e2f6a1bda546695f3c3f33175944db4a11a346afb07e78489e509b02add51b7b203eda5c330b03641179a31fbba9b56ce00f3d5b5e3d7d9c5429aebb9576f2f7eacbe27bc1b8082aaf68fb69c921aa5d33ec0c8510410865a178d86d7e54122d55ef2c2bbc040be46d7fece73fe8a1b24495ec160df2da9b20a7ba2f26dfa2a44366dbc63de5cd7d7c94c57172fe6d79c901f025c0010b02c89b395402c009f62dc053b8067a1e0ed0a1e0cf5087d7f78cbd94afe0c3dd55d2d4b1a5cfe2b68b86264e351d1dcd858783a240f893f008ceed743d969b8f735a1677ead960b1fb1ecc5ac83c273b49288d02d7286207e663c45e1a7baf50640c91e762941cf380ce8d79f3e86767fbbcd25b42ef70ec334835a3a6d792e170a432ce0cb7bde9aaa1e75637c1c34ae5fef4338f53db8b13a4d2df594efbfa08784543815c9c0d487bddfa1539bc252cf43ec3686e9802d651cfd2a829a06a9f332a733a4a8aed80efe3478093fbc69c8608146b3f16f1a5c4eac9320da49f1afa5f538ddecbbe7888f435512d0dd74fd9b8c99e3145ba84410d8ca9a36dd884109e76e5fb8222a52e1473da168519ce7a8a3c32e9149671b16724c6c5c51bb5cd64fb591e567fb78b10f9f6fee62c276f282a7df6bcf7c17747bc9a81e6c9c3b032fdd0e1c3ac9eaa5077de3ded18b2ed4faf328f49875af2e36ad5ce5f6cc99ef4b60e57b3b5b9c9fcbcd4cfb3975e70ce4c2506bcd71fef0e53592461504e3d42c885caab21b782e26294c6a9d61118cc40a26f378441ceb48f31a362bf8502a723a36c63502229a462cc2a3796279a5e3a7f81a68c7f81312c381cc16a4ab03513a51ad5b54306ec1d78a5e47e2b15e5b7a1438e5b8b2882dbdad13d6a4a8c3558cae043501b68eb3b040067152>'
AWG_QUIC_I2='<b 0x0000000000010000000000000000000000000000000000000000000000000000>'
AWG_QUIC_J1='<b 0x1234567890abcdef>'

AWG_DNS_I1='<b 0x123401000001000000000000076578616d706c6503636f6d0000010001>'

AWG_SIP_I1='<b 0x494e56495445207369703a626f624062696c6f78692e636f6d205349502f322e300d0a5669613a205349502f322e302f5544502070633333>'
AWG_SIP_I2='<b 0x5349502f322e302031303020547279696e670d0a5669613a205349502f322e302f5544502070633333>'
AWG_SIP_J1='<b 0xabcdef1234567890>'

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
i1 = $AWG_QUIC_I1
i2 = $AWG_QUIC_I2
j1 = $AWG_QUIC_J1
itime = 120
EOF
            ;;

        dns)
            # DNS query mimic - appears as DNS resolution
            cat >> "$runtime_config" << EOF

# Profile: dns (DNS query protocol mimic)
# Injects DNS query packet signature
i1 = $AWG_DNS_I1
itime = 120
EOF
            ;;

        sip)
            # SIP/VoIP mimic - appears as voice traffic
            cat >> "$runtime_config" << EOF

# Profile: sip (SIP/VoIP protocol mimic)
# Injects SIP INVITE packet signature
i1 = $AWG_SIP_I1
i2 = $AWG_SIP_I2
j1 = $AWG_SIP_J1
itime = 120
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
i1 = $AWG_QUIC_I1
i2 = $AWG_QUIC_I2
j1 = $AWG_QUIC_J1
itime = 120
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
