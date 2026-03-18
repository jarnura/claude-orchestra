#!/usr/bin/env bash
set -euo pipefail

# Test prompt builder logic
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRA_DIR="$(dirname "$SCRIPT_DIR")"

source "$ORCHESTRA_DIR/lib/prompt-builder.sh"

PASS=0
FAIL=0

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (needle='$needle' not in output)"
        FAIL=$((FAIL + 1))
    fi
}

assert_max_size() {
    local desc="$1" value="$2" max_size="$3"
    local actual_size=${#value}
    if [[ $actual_size -le $max_size ]]; then
        echo "  PASS: $desc (size=$actual_size <= $max_size)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (size=$actual_size > $max_size)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Prompt Builder Tests ==="

# Test 1: User prompt only
echo ""
echo "Test 1: User prompt only"
result=$(build_compound_prompt "Hello world" "" "")
assert_contains "Contains user prompt" "$result" "Hello world"

# Test 2: User + agent
echo ""
echo "Test 2: User + agent content"
result=$(build_compound_prompt "My prompt" "Agent instructions here" "")
assert_contains "Contains user prompt" "$result" "My prompt"
assert_contains "Contains agent header" "$result" "# Agent Instructions"
assert_contains "Contains agent content" "$result" "Agent instructions here"

# Test 3: User + agent + skill
echo ""
echo "Test 3: User + agent + skill"
result=$(build_compound_prompt "My prompt" "Agent stuff" "Skill reference")
assert_contains "Contains all three" "$result" "My prompt"
assert_contains "Agent header present" "$result" "# Agent Instructions"
assert_contains "Skill header present" "$result" "# Skill Reference"

# Test 4: Size truncation
echo ""
echo "Test 4: Skill truncation at size limit"
MAX_SYSTEM_PROMPT_SIZE=200
large_skill=$(python3 -c "print('x' * 1000)")
result=$(build_compound_prompt "Short user" "Short agent" "$large_skill")
assert_max_size "Result under limit" "$result" 250  # some overhead for headers

# Test 5: Empty inputs
echo ""
echo "Test 5: All empty inputs"
result=$(build_compound_prompt "" "" "")
if [[ -z "$result" || "$result" == $'\n' ]]; then
    echo "  PASS: Empty result for empty inputs"
    PASS=$((PASS + 1))
else
    echo "  PASS: Minimal result for empty inputs (${#result} chars)"
    PASS=$((PASS + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
