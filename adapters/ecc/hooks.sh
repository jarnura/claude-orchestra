#!/usr/bin/env bash
# ECC Hook profile resolution
# Maps hook profile names to environment variables

# ecc_resolve_hook_profile(profile_name)
# Validates profile name, returns the validated name
# Profile names: strict | standard | minimal
ecc_resolve_hook_profile() {
    local profile="${1:-standard}"
    case "$profile" in
        strict|standard|minimal)
            echo "$profile"
            ;;
        *)
            echo "WARNING: Unknown hook profile: $profile, using standard" >&2
            echo "standard"
            ;;
    esac
}

# ecc_hook_env_vars(profile_name)
# Returns the environment variable assignment string
ecc_hook_env_vars() {
    local profile
    profile=$(ecc_resolve_hook_profile "$1")
    echo "ECC_HOOK_PROFILE=$profile"
}
