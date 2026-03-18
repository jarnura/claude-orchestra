#!/usr/bin/env bash
# claude-orchestra — Shared configuration loading
# Config hierarchy: ./orchestra.conf > $ORCHESTRA_CONFIG > ~/.config/claude-orchestra/config > defaults

load_config() {
    # Fleet-inherited defaults
    MAX_PARALLEL="${MAX_PARALLEL:-5}"
    POLL_INTERVAL="${POLL_INTERVAL:-10}"
    MODE="${MODE:-batch}"
    CLAUDE_CMD="${CLAUDE_CMD:-}"
    LOG_DIR="${LOG_DIR:-}"
    MODEL="${MODEL:-opus}"
    EFFORT="${EFFORT:-high}"

    # Orchestra-specific defaults
    LAUNCH_DELAY="${LAUNCH_DELAY:-2}"  # seconds between task launches (prevents OAuth rate limiting)
    ECC_DIR="${ECC_DIR:-$HOME/.claude}"
    ECC_HOOK_PROFILE="${ECC_HOOK_PROFILE:-standard}"
    ECC_ENABLED="${ECC_ENABLED:-auto}"
    AGGREGATE_OUTPUTS="${AGGREGATE_OUTPUTS:-false}"

    # Load config files (later sources override earlier)
    local configs=(
        "$HOME/.config/claude-orchestra/config"
        "${ORCHESTRA_CONFIG:-}"
        "./orchestra.conf"
    )
    for cfg in "${configs[@]}"; do
        [[ -n "$cfg" && -f "$cfg" ]] && source "$cfg"
    done

    # Re-apply env vars (they take precedence over config files)
    MAX_PARALLEL="${MAX_PARALLEL}"
    POLL_INTERVAL="${POLL_INTERVAL}"
    MODE="${MODE}"
}
