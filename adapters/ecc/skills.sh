#!/usr/bin/env bash
# ECC Skill resolution — reads SKILL.md files from skill directories

# ecc_resolve_skill(skill_name)
# Reads ~/.claude/skills/<skill_name>/SKILL.md
# Returns: the skill content on stdout
ecc_resolve_skill() {
    local name="$1"
    # Validate name: alphanumeric, hyphens, underscores, colons (for ECC namespaced skills)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_:-]+$ ]]; then
        echo "ERROR: Invalid skill name (unsafe characters): $name" >&2
        return 1
    fi
    local skill_file="$ECC_SKILLS_DIR/${name}/SKILL.md"
    if [[ ! -f "$skill_file" ]]; then
        echo "WARNING: Skill not found: $name" >&2
        return 1
    fi
    cat "$skill_file"
}

# ecc_resolve_skills(comma_separated_skills)
# Resolves multiple skills, concatenates content with separators
ecc_resolve_skills() {
    local skills_csv="$1"
    local result=""
    local IFS=','
    read -ra skill_list <<< "$skills_csv"
    for skill in "${skill_list[@]}"; do
        skill=$(echo "$skill" | xargs)  # trim whitespace
        [[ -z "$skill" ]] && continue
        local content
        content=$(ecc_resolve_skill "$skill") || continue
        result+=$'\n\n--- SKILL: '"$skill"$' ---\n'"$content"
    done
    echo "$result"
}

# ecc_list_skills()
# Lists all available skill names (one per line)
ecc_list_skills() {
    if [[ ! -d "$ECC_SKILLS_DIR" ]]; then
        echo "No skills directory found at $ECC_SKILLS_DIR" >&2
        return 1
    fi
    for d in "$ECC_SKILLS_DIR"/*/; do
        if [[ -f "${d}SKILL.md" ]]; then
            basename "$d"
        fi
    done
}
