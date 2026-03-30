#!/usr/bin/env bash
set -euo pipefail

# Test ECC detection logic
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRA_DIR="$(dirname "$SCRIPT_DIR")"

source "$ORCHESTRA_DIR/adapters/ecc/detect.sh"

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

echo "=== ECC Detection Tests ==="

# Test 1: ECC detected with real ~/.claude/agents/
echo ""
echo "Test 1: Detect real ECC installation"
ECC_DIR="$HOME/.claude"
ECC_ENABLED="auto"
if ecc_is_available; then
    assert_eq "ECC detected at ~/.claude" "0" "0"
    assert_eq "ECC_AGENTS_DIR set" "$HOME/.claude/agents" "$ECC_AGENTS_DIR"
    echo "  Agents dir: $ECC_AGENTS_DIR"
    echo "  Skills dir: $ECC_SKILLS_DIR"
else
    echo "  SKIP: ECC not installed at ~/.claude (this is OK for CI)"
fi

# Test 2: ECC not detected with invalid path
echo ""
echo "Test 2: Invalid path detection"
ECC_DIR="/nonexistent/path"
if ecc_detect; then
    assert_eq "Should not detect at invalid path" "1" "0"
else
    assert_eq "Correctly rejected invalid path" "1" "1"
fi

# Test 3: ECC_ENABLED=false skips detection
echo ""
echo "Test 3: ECC_ENABLED=false"
ECC_DIR="$HOME/.claude"
ECC_ENABLED="false"
if ecc_is_available; then
    assert_eq "Should be disabled" "1" "0"
else
    assert_eq "Correctly disabled" "1" "1"
fi

# Test 4: ECC_ENABLED=true forces detection
echo ""
echo "Test 4: ECC_ENABLED=true"
ECC_DIR="$HOME/.claude"
ECC_ENABLED="true"
if ecc_is_available; then
    assert_eq "Forced detection" "0" "0"
else
    echo "  SKIP: ECC not installed (expected in CI)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
