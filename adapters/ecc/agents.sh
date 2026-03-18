#!/usr/bin/env bash
# ECC Agent resolution — reads agent .md files and returns content

# ecc_resolve_agent(agent_name)
# Reads ~/.claude/agents/<agent_name>.md
# Returns: the full markdown content on stdout
# Returns 1 if agent not found
ecc_resolve_agent() {
    local name="$1"
    # Validate name: alphanumeric, hyphens, underscores, colons (for ECC namespaced agents)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_:-]+$ ]]; then
        echo "ERROR: Invalid agent name (unsafe characters): $name" >&2
        return 1
    fi
    local agent_file="$ECC_AGENTS_DIR/${name}.md"
    if [[ ! -f "$agent_file" ]]; then
        echo "WARNING: Agent not found: $name" >&2
        return 1
    fi
    cat "$agent_file"
}

# ecc_resolve_agents(comma_separated_agents)
# Resolves multiple agents, concatenates their content with separators
# Returns: combined agent instructions on stdout
ecc_resolve_agents() {
    local agents_csv="$1"
    local result=""
    local IFS=','
    read -ra agent_list <<< "$agents_csv"
    for agent in "${agent_list[@]}"; do
        agent=$(echo "$agent" | xargs)  # trim whitespace
        [[ -z "$agent" ]] && continue
        local content
        content=$(ecc_resolve_agent "$agent") || continue
        result+=$'\n\n--- AGENT: '"$agent"$' ---\n'"$content"
    done
    echo "$result"
}

# ecc_agent_model(agent_name)
# Parses the model field from agent YAML frontmatter
# Returns: model name (e.g., "opus", "sonnet")
ecc_agent_model() {
    local name="$1"
    local agent_file="$ECC_AGENTS_DIR/${name}.md"
    [[ -f "$agent_file" ]] || return 1
    # Parse YAML frontmatter for model field
    sed -n '/^---$/,/^---$/p' "$agent_file" | grep '^model:' | awk '{print $2}' | head -1
}

# ecc_list_agents()
# Lists all available agent names (one per line)
ecc_list_agents() {
    if [[ ! -d "$ECC_AGENTS_DIR" ]]; then
        echo "No agents directory found at $ECC_AGENTS_DIR" >&2
        return 1
    fi
    for f in "$ECC_AGENTS_DIR"/*.md; do
        [[ -f "$f" ]] && basename "$f" .md
    done
}
