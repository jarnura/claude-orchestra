#!/usr/bin/env bash
# ecc-adapter.sh — Core ECC integration library for claude-orchestra
# Facade that combines detect, agents, skills, and hooks into a single interface

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../adapters/ecc" && pwd)"

source "$ADAPTER_DIR/detect.sh"
source "$ADAPTER_DIR/agents.sh"
source "$ADAPTER_DIR/skills.sh"
source "$ADAPTER_DIR/hooks.sh"

# Global state
_ECC_DETECTED=""

# ecc_init()
# Initialize ECC adapter. Call once at orchestrator startup.
# Sets _ECC_DETECTED to "yes" or "no"
ecc_init() {
    if ecc_is_available; then
        _ECC_DETECTED="yes"
        local agent_count
        agent_count=$(ecc_list_agents 2>/dev/null | wc -l | xargs)
        local skill_count
        skill_count=$(ecc_list_skills 2>/dev/null | wc -l | xargs)
        echo -e "\033[0;35m[ecc]\033[0m Detected: ${agent_count} agents, ${skill_count} skills"
    else
        _ECC_DETECTED="no"
        echo -e "\033[0;35m[ecc]\033[0m Not detected — running in standalone mode"
    fi
}

# ecc_available()
# Quick check if ECC was detected during init
ecc_available() {
    [[ "$_ECC_DETECTED" == "yes" ]]
}

# ecc_build_system_prompt(task_json)
# Takes a task JSON blob, resolves agents/skills, returns the compound system prompt
# This is the main integration point
ecc_build_system_prompt() {
    local task_json="$1"
    local result=""

    # Start with any explicit appendSystemPrompt
    local user_prompt
    user_prompt=$(echo "$task_json" | jq -r '.appendSystemPrompt // ""')
    [[ -n "$user_prompt" ]] && result="$user_prompt"

    if ! ecc_available; then
        echo "$result"
        return
    fi

    # Resolve agents
    local agents_csv
    agents_csv=$(echo "$task_json" | jq -r '.agents // ""')
    if [[ -n "$agents_csv" ]]; then
        local agent_content
        agent_content=$(ecc_resolve_agents "$agents_csv")
        [[ -n "$agent_content" ]] && result+="$agent_content"
    fi

    # Resolve skills
    local skills_csv
    skills_csv=$(echo "$task_json" | jq -r '.skills // ""')
    if [[ -n "$skills_csv" ]]; then
        local skill_content
        skill_content=$(ecc_resolve_skills "$skills_csv")
        [[ -n "$skill_content" ]] && result+="$skill_content"
    fi

    echo "$result"
}

# ecc_get_hook_profile(task_json)
# Returns the hook profile for this task
ecc_get_hook_profile() {
    local task_json="$1"
    local profile
    profile=$(echo "$task_json" | jq -r '.hooks // ""')
    if [[ -z "$profile" ]]; then
        echo "$ECC_HOOK_PROFILE"  # use global default
    else
        ecc_resolve_hook_profile "$profile"
    fi
}

# ecc_get_model_override(task_json)
# If a task specifies a single agent, use that agent's preferred model
# unless the task explicitly sets model
ecc_get_model_override() {
    local task_json="$1"
    local explicit_model
    explicit_model=$(echo "$task_json" | jq -r '.model // ""')
    [[ -n "$explicit_model" ]] && { echo "$explicit_model"; return; }

    if ! ecc_available; then
        echo "$MODEL"
        return
    fi

    # Check if single agent specified, use its model
    local agents_csv
    agents_csv=$(echo "$task_json" | jq -r '.agents // ""')
    if [[ -n "$agents_csv" && "$agents_csv" != *","* ]]; then
        local agent_model
        agent_model=$(ecc_agent_model "$agents_csv" 2>/dev/null)
        [[ -n "$agent_model" ]] && { echo "$agent_model"; return; }
    fi

    echo "$MODEL"  # global default
}
