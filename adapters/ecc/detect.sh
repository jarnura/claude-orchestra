#!/usr/bin/env bash
# ECC installation detection
# Checks for Everything-Claude-Code agents/skills/hooks directories

# ecc_detect()
# Returns 0 if ECC is found, 1 if not.
# Sets global: ECC_AGENTS_DIR, ECC_SKILLS_DIR, ECC_HOOKS_FILE, ECC_PLUGIN_ROOT
ecc_detect() {
    local ecc_dir="${ECC_DIR:-$HOME/.claude}"

    # Check agents directory exists and has .md files
    ECC_AGENTS_DIR="$ecc_dir/agents"
    if [[ ! -d "$ECC_AGENTS_DIR" ]]; then
        return 1
    fi

    # Verify at least one agent file exists (using glob, not ls)
    local found_agent=false
    for f in "$ECC_AGENTS_DIR"/*.md; do
        if [[ -f "$f" ]]; then
            found_agent=true
            break
        fi
    done
    if [[ "$found_agent" == "false" ]]; then
        return 1
    fi

    # Check skills directory
    ECC_SKILLS_DIR="$ecc_dir/skills"

    # Check hooks.json
    ECC_HOOKS_FILE="$ecc_dir/hooks/hooks.json"

    # Resolve plugin root (for hook scripts)
    local plugin_root=""
    for candidate in \
        "$ecc_dir/plugins/cache/everything-claude-code/everything-claude-code/"*/  \
        "$ecc_dir/plugins/marketplaces/everything-claude-code/" \
        "$ecc_dir/plugins/everything-claude-code/"; do
        if [[ -d "$candidate" ]]; then
            plugin_root="$candidate"
            break
        fi
    done
    ECC_PLUGIN_ROOT="$plugin_root"

    return 0
}

# ecc_is_available()
# Cached check: returns 0 if ECC detected, 1 otherwise.
# Respects ECC_ENABLED config: auto | true | false
ecc_is_available() {
    case "$ECC_ENABLED" in
        false) return 1 ;;
        true)  ecc_detect; return $? ;;
        auto)  ecc_detect; return $? ;;
        *)     ecc_detect; return $? ;;
    esac
}
