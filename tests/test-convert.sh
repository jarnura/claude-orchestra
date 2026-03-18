#!/usr/bin/env bash
set -euo pipefail

# Test orchestra-convert (enhanced markdown -> JSON conversion)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRA_DIR="$(dirname "$SCRIPT_DIR")"

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

echo "=== Convert Tests ==="

# Create test input
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat > "$TMPDIR/test-tasks.md" << 'MARKDOWN'
# Test Tasks

## Security Audit
- workdir: /tmp/test
- model: opus
- effort: high
- agents: security-reviewer, code-reviewer
- skills: backend-patterns
- hooks: strict
- allowedTools: Read Grep Glob

Audit the code for security issues.

## Code Review
- workdir: /tmp/test2
- model: sonnet
- agents: code-reviewer

Review code quality and patterns.
MARKDOWN

# Test 1: Convert works
echo ""
echo "Test 1: Conversion produces valid JSON"
"$ORCHESTRA_DIR/bin/orchestra-convert" "$TMPDIR/test-tasks.md" "$TMPDIR/test-tasks.json"
assert_eq "Output file exists" "true" "$(test -f "$TMPDIR/test-tasks.json" && echo true || echo false)"

# Test 2: Correct task count
echo ""
echo "Test 2: Task count"
count=$(jq '.tasks | length' "$TMPDIR/test-tasks.json")
assert_eq "Two tasks" "2" "$count"

# Test 3: Agents field parsed
echo ""
echo "Test 3: Agents field"
agents=$(jq -r '.tasks[0].agents' "$TMPDIR/test-tasks.json")
assert_eq "First task agents" "security-reviewer, code-reviewer" "$agents"

# Test 4: Skills field parsed
echo ""
echo "Test 4: Skills field"
skills=$(jq -r '.tasks[0].skills' "$TMPDIR/test-tasks.json")
assert_eq "First task skills" "backend-patterns" "$skills"

# Test 5: Hooks field parsed
echo ""
echo "Test 5: Hooks field"
hooks=$(jq -r '.tasks[0].hooks' "$TMPDIR/test-tasks.json")
assert_eq "First task hooks" "strict" "$hooks"

# Test 6: Standard fields preserved
echo ""
echo "Test 6: Standard fields"
model=$(jq -r '.tasks[0].model' "$TMPDIR/test-tasks.json")
workdir=$(jq -r '.tasks[0].workdir' "$TMPDIR/test-tasks.json")
assert_eq "Model" "opus" "$model"
assert_eq "Workdir" "/tmp/test" "$workdir"

# Test 7: Second task without all fields
echo ""
echo "Test 7: Second task (partial fields)"
agents2=$(jq -r '.tasks[1].agents' "$TMPDIR/test-tasks.json")
skills2=$(jq -r '.tasks[1].skills // "null"' "$TMPDIR/test-tasks.json")
assert_eq "Second task agents" "code-reviewer" "$agents2"
assert_eq "Second task skills (missing)" "null" "$skills2"

# Test 8: Prompt text preserved
echo ""
echo "Test 8: Prompt text"
prompt=$(jq -r '.tasks[0].prompt' "$TMPDIR/test-tasks.json")
if [[ "$prompt" == *"security issues"* ]]; then
    echo "  PASS: Prompt contains expected text"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Prompt missing expected text: $prompt"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
