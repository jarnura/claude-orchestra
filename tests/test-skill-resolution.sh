#!/usr/bin/env bash
set -euo pipefail

# Test skill resolution logic
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRA_DIR="$(dirname "$SCRIPT_DIR")"

source "$ORCHESTRA_DIR/lib/config.sh"
load_config
source "$ORCHESTRA_DIR/lib/ecc-adapter.sh"

PASS=0
FAIL=0

assert_not_empty() {
    local desc="$1" value="$2"
    if [[ -n "$value" ]]; then
        echo "  PASS: $desc (${#value} chars)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (empty)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Skill Resolution Tests ==="

ecc_init 2>/dev/null || true

if ! ecc_available; then
    echo "SKIP: ECC not available, cannot test skill resolution"
    exit 0
fi

# Test 1: List skills
echo ""
echo "Test 1: List available skills"
skill_list=$(ecc_list_skills 2>/dev/null)
count=$(echo "$skill_list" | wc -l | xargs)
if [[ "$count" -gt 0 ]]; then
    echo "  PASS: Found $count skills"
    PASS=$((PASS + 1))
    # Pick first skill for resolution test
    FIRST_SKILL=$(echo "$skill_list" | head -1)
    echo "  First skill: $FIRST_SKILL"
else
    echo "  FAIL: No skills found"
    FAIL=$((FAIL + 1))
    exit 1
fi

# Test 2: Resolve a known skill
echo ""
echo "Test 2: Resolve skill: $FIRST_SKILL"
content=$(ecc_resolve_skill "$FIRST_SKILL" 2>/dev/null) || true
assert_not_empty "Skill content for $FIRST_SKILL" "$content"

# Test 3: Resolve unknown skill
echo ""
echo "Test 3: Resolve nonexistent skill"
content=$(ecc_resolve_skill "nonexistent-skill-xyz" 2>/dev/null) || true
if [[ -z "$content" ]]; then
    echo "  PASS: Unknown skill returns empty"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Should have returned empty"
    FAIL=$((FAIL + 1))
fi

# Test 4: Resolve multiple skills
echo ""
echo "Test 4: Resolve multiple skills"
if [[ "$count" -ge 2 ]]; then
    SECOND_SKILL=$(echo "$skill_list" | sed -n '2p')
    content=$(ecc_resolve_skills "$FIRST_SKILL, $SECOND_SKILL" 2>/dev/null) || true
    assert_not_empty "Combined skill content" "$content"
    if [[ "$content" == *"--- SKILL: $FIRST_SKILL ---"* ]]; then
        echo "  PASS: Skill separator found"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Missing skill separator"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  SKIP: Need at least 2 skills"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
