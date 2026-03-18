#!/usr/bin/env bash
# prompt-builder.sh — Compound prompt assembly with size limits
# Handles construction of the final --append-system-prompt value

# Approximate limit to avoid context window issues (~50KB)
MAX_SYSTEM_PROMPT_SIZE="${MAX_SYSTEM_PROMPT_SIZE:-50000}"

# build_compound_prompt(user_prompt, agent_content, skill_content)
# Assembles the final --append-system-prompt value
# Priority: user prompt > agent instructions > skill reference
# Truncates skill content first if the combined prompt is too large
build_compound_prompt() {
    local user_prompt="$1"
    local agent_content="$2"
    local skill_content="$3"

    local result=""

    # User prompt goes first (highest priority)
    if [[ -n "$user_prompt" ]]; then
        result="$user_prompt"
    fi

    # Agent instructions next (high priority)
    if [[ -n "$agent_content" ]]; then
        result+=$'\n\n# Agent Instructions\n'"$agent_content"
    fi

    # Skill content last (truncated if needed)
    if [[ -n "$skill_content" ]]; then
        local current_size=${#result}
        local remaining=$(( MAX_SYSTEM_PROMPT_SIZE - current_size ))
        if [[ $remaining -gt 1000 ]]; then
            local truncated="${skill_content:0:$remaining}"
            result+=$'\n\n# Skill Reference\n'"$truncated"
        else
            result+=$'\n\n# Skills: Content truncated due to size limits. Agents and user instructions took priority.'
        fi
    fi

    echo "$result"
}
