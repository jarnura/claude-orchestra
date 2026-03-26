#!/usr/bin/env bash
set -euo pipefail

# Test retry loop support in orchestra
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

echo "=== Retry and Verification Tests ==="

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Create mock claude CLI that always fails
cat > "$TMPDIR/mock-claude" << 'MOCK'
#!/usr/bin/env bash
# Mock claude CLI for testing
# If called with --help, print minimal help (no --effort)
if [[ "${1:-}" == "--help" ]]; then
    echo "mock claude cli"
    exit 0
fi
# If called with "auth", output empty JSON
if [[ "${1:-}" == "auth" ]]; then
    echo '{}'
    exit 0
fi
# For --print invocations: read stdin (consume the prompt), then fail
cat > /dev/null
exit 1
MOCK
chmod +x "$TMPDIR/mock-claude"

# Create mock claude CLI that always succeeds
cat > "$TMPDIR/mock-claude-ok" << 'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == "--help" ]]; then
    echo "mock claude cli"
    exit 0
fi
if [[ "${1:-}" == "auth" ]]; then
    echo '{}'
    exit 0
fi
cat > /dev/null
exit 0
MOCK
chmod +x "$TMPDIR/mock-claude-ok"

# -----------------------------------------------------------
# Test 1: Task with max_retries=2 should end with attempt=3
# -----------------------------------------------------------
echo ""
echo "Test 1: Task with max_retries=2 retries twice, ends failed at attempt 3"

cat > "$TMPDIR/tasks-retry.json" << 'JSON'
{
  "tasks": [{
    "id": "fail-task",
    "name": "Always Fail",
    "prompt": "exit 1",
    "workdir": ".",
    "model": "sonnet",
    "status": "pending",
    "max_retries": 2,
    "retry_delay_seconds": 0,
    "retry_backoff": "fixed"
  }]
}
JSON

CLAUDE_CMD="$TMPDIR/mock-claude" \
MAX_PARALLEL=1 \
POLL_INTERVAL=1 \
LAUNCH_DELAY=0 \
LOG_DIR="$TMPDIR/logs-retry" \
ECC_ENABLED=false \
"$ORCHESTRA_DIR/bin/orchestra" "$TMPDIR/tasks-retry.json" 2>&1 || true

# Check final status
status=$(jq -r '.tasks[0].status' "$TMPDIR/tasks-retry.json")
assert_eq "Task status is failed" "failed" "$status"

# Check attempt count (should be 3: initial + 2 retries)
attempt=$(jq '.tasks[0].attempt' "$TMPDIR/tasks-retry.json")
assert_eq "Task attempt is 3" "3" "$attempt"

# Check max_attempts (max_retries + 1 = 3)
max_attempts=$(jq '.tasks[0].max_attempts' "$TMPDIR/tasks-retry.json")
assert_eq "Task max_attempts is 3" "3" "$max_attempts"

# -----------------------------------------------------------
# Test 2: Task with max_retries=0 should fail immediately
# -----------------------------------------------------------
echo ""
echo "Test 2: Task with max_retries=0 fails immediately at attempt 1"

cat > "$TMPDIR/tasks-noretry.json" << 'JSON'
{
  "tasks": [{
    "id": "noretry-task",
    "name": "No Retry",
    "prompt": "exit 1",
    "workdir": ".",
    "model": "sonnet",
    "status": "pending",
    "max_retries": 0,
    "retry_delay_seconds": 0,
    "retry_backoff": "fixed"
  }]
}
JSON

CLAUDE_CMD="$TMPDIR/mock-claude" \
MAX_PARALLEL=1 \
POLL_INTERVAL=1 \
LAUNCH_DELAY=0 \
LOG_DIR="$TMPDIR/logs-noretry" \
ECC_ENABLED=false \
"$ORCHESTRA_DIR/bin/orchestra" "$TMPDIR/tasks-noretry.json" 2>&1 || true

status=$(jq -r '.tasks[0].status' "$TMPDIR/tasks-noretry.json")
assert_eq "Task status is failed" "failed" "$status"

attempt=$(jq '.tasks[0].attempt' "$TMPDIR/tasks-noretry.json")
assert_eq "Task attempt is 1" "1" "$attempt"

# -----------------------------------------------------------
# Test 3: Task without retry fields defaults to 0 retries
# -----------------------------------------------------------
echo ""
echo "Test 3: Task without retry fields defaults to no retries"

cat > "$TMPDIR/tasks-default.json" << 'JSON'
{
  "tasks": [{
    "id": "default-task",
    "name": "Default Task",
    "prompt": "exit 1",
    "workdir": ".",
    "model": "sonnet",
    "status": "pending"
  }]
}
JSON

CLAUDE_CMD="$TMPDIR/mock-claude" \
MAX_PARALLEL=1 \
POLL_INTERVAL=1 \
LAUNCH_DELAY=0 \
LOG_DIR="$TMPDIR/logs-default" \
ECC_ENABLED=false \
"$ORCHESTRA_DIR/bin/orchestra" "$TMPDIR/tasks-default.json" 2>&1 || true

status=$(jq -r '.tasks[0].status' "$TMPDIR/tasks-default.json")
assert_eq "Task status is failed" "failed" "$status"

attempt=$(jq '.tasks[0].attempt' "$TMPDIR/tasks-default.json")
assert_eq "Task attempt is 1" "1" "$attempt"

# -----------------------------------------------------------
# Test 4: verify: command with "true" -> done, verify_status "passed"
# -----------------------------------------------------------
echo ""
echo "Test 4: Verification with 'true' command passes, task done"

cat > "$TMPDIR/tasks-verify-pass.json" << 'JSON'
{
  "tasks": [{
    "id": "verify-pass",
    "name": "Verify Pass",
    "prompt": "do something",
    "workdir": ".",
    "model": "sonnet",
    "status": "pending",
    "verify_strategy": "command",
    "verify_command": "true",
    "verify_timeout": 10
  }]
}
JSON

CLAUDE_CMD="$TMPDIR/mock-claude-ok" \
MAX_PARALLEL=1 \
POLL_INTERVAL=1 \
LAUNCH_DELAY=0 \
LOG_DIR="$TMPDIR/logs-verify-pass" \
ECC_ENABLED=false \
"$ORCHESTRA_DIR/bin/orchestra" "$TMPDIR/tasks-verify-pass.json" 2>&1 || true

status=$(jq -r '.tasks[0].status' "$TMPDIR/tasks-verify-pass.json")
assert_eq "Task status is done" "done" "$status"

verify_status=$(jq -r '.tasks[0].verify_status' "$TMPDIR/tasks-verify-pass.json")
assert_eq "Verify status is passed" "passed" "$verify_status"

# -----------------------------------------------------------
# Test 5: verify: command with "false", max_retries: 1 -> retry then fail
# -----------------------------------------------------------
echo ""
echo "Test 5: Verification with 'false' command fails, retries once then fails"

cat > "$TMPDIR/tasks-verify-fail.json" << 'JSON'
{
  "tasks": [{
    "id": "verify-fail",
    "name": "Verify Fail",
    "prompt": "do something",
    "workdir": ".",
    "model": "sonnet",
    "status": "pending",
    "max_retries": 1,
    "retry_delay_seconds": 0,
    "retry_backoff": "fixed",
    "verify_strategy": "command",
    "verify_command": "false",
    "verify_timeout": 10
  }]
}
JSON

CLAUDE_CMD="$TMPDIR/mock-claude-ok" \
MAX_PARALLEL=1 \
POLL_INTERVAL=1 \
LAUNCH_DELAY=0 \
LOG_DIR="$TMPDIR/logs-verify-fail" \
ECC_ENABLED=false \
"$ORCHESTRA_DIR/bin/orchestra" "$TMPDIR/tasks-verify-fail.json" 2>&1 || true

status=$(jq -r '.tasks[0].status' "$TMPDIR/tasks-verify-fail.json")
assert_eq "Task status is failed" "failed" "$status"

verify_status=$(jq -r '.tasks[0].verify_status' "$TMPDIR/tasks-verify-fail.json")
assert_eq "Verify status is failed" "failed" "$verify_status"

attempt=$(jq '.tasks[0].attempt' "$TMPDIR/tasks-verify-fail.json")
assert_eq "Task attempt is 2" "2" "$attempt"

# -----------------------------------------------------------
# Test 6: No verify fields -> verify_status "skipped" (backwards compat)
# -----------------------------------------------------------
echo ""
echo "Test 6: No verify fields defaults to skipped"

cat > "$TMPDIR/tasks-verify-skip.json" << 'JSON'
{
  "tasks": [{
    "id": "verify-skip",
    "name": "Verify Skip",
    "prompt": "do something",
    "workdir": ".",
    "model": "sonnet",
    "status": "pending"
  }]
}
JSON

CLAUDE_CMD="$TMPDIR/mock-claude-ok" \
MAX_PARALLEL=1 \
POLL_INTERVAL=1 \
LAUNCH_DELAY=0 \
LOG_DIR="$TMPDIR/logs-verify-skip" \
ECC_ENABLED=false \
"$ORCHESTRA_DIR/bin/orchestra" "$TMPDIR/tasks-verify-skip.json" 2>&1 || true

status=$(jq -r '.tasks[0].status' "$TMPDIR/tasks-verify-skip.json")
assert_eq "Task status is done" "done" "$status"

verify_status=$(jq -r '.tasks[0].verify_status' "$TMPDIR/tasks-verify-skip.json")
assert_eq "Verify status is skipped" "skipped" "$verify_status"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
