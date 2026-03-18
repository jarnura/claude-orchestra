#!/usr/bin/env bash
set -euo pipefail

# Test agent resolution logic
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRA_DIR="$(dirname "$SCRIPT_DIR")"

source "$ORCHESTRA_DIR/lib/config.sh"
load_config
source "$ORCHESTRA_DIR/lib/ecc-adapter.sh"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected='$expected', actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

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

echo "=== Agent Resolution Tests ==="

# Initialize
ecc_init 2>/dev/null || true

if ! ecc_available; then
    echo "SKIP: ECC not available, cannot test agent resolution"
    exit 0
fi

# Test 1: Resolve a known agent
echo ""
echo "Test 1: Resolve planner agent"
content=$(ecc_resolve_agent "planner" 2>/dev/null) || true
assert_not_empty "Planner content" "$content"

# Test 2: Resolve unknown agent
echo ""
echo "Test 2: Resolve nonexistent agent"
content=$(ecc_resolve_agent "nonexistent-agent-xyz" 2>/dev/null) || true
if [[ -z "$content" ]]; then
    assert_eq "Unknown agent returns empty" "" ""
    PASS=$((PASS + 1))
else
    echo "  FAIL: Should have returned empty for unknown agent"
    FAIL=$((FAIL + 1))
fi

# Test 3: Resolve multiple agents
echo ""
echo "Test 3: Resolve multiple agents (planner,code-reviewer)"
content=$(ecc_resolve_agents "planner, code-reviewer" 2>/dev/null) || true
assert_not_empty "Combined agent content" "$content"
# Check both separators are present
if [[ "$content" == *"--- AGENT: planner ---"* && "$content" == *"--- AGENT: code-reviewer ---"* ]]; then
    echo "  PASS: Both agent separators found"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Missing agent separators"
    FAIL=$((FAIL + 1))
fi

# Test 4: Agent model parsing
echo ""
echo "Test 4: Parse agent model from frontmatter"
model=$(ecc_agent_model "planner" 2>/dev/null) || true
assert_eq "Planner model is opus" "opus" "$model"

# Test 5: List agents
echo ""
echo "Test 5: List available agents"
agent_list=$(ecc_list_agents 2>/dev/null)
count=$(echo "$agent_list" | wc -l | xargs)
if [[ "$count" -gt 0 ]]; then
    echo "  PASS: Found $count agents"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No agents found"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
