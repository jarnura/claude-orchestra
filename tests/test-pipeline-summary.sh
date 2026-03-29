#!/usr/bin/env bash
set -euo pipefail

# Test pipeline summary generation helpers and API logic
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

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

# Helper: Python import for the serve module (no .py extension)
IMPORT_HELPER="
import types
mod = types.ModuleType('serve')
mod.__file__ = '$ORCHESTRA_DIR/bin/orchestra-serve'
with open('$ORCHESTRA_DIR/bin/orchestra-serve') as f:
    code = compile(f.read(), '$ORCHESTRA_DIR/bin/orchestra-serve', 'exec')
exec(code, mod.__dict__)
"

echo "=== Pipeline Summary Tests ==="

# Create test data directory structure
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# --- Test fixture: a completed pipeline with task outputs ---
LOGS_DIR="$TMPDIR/logs"
mkdir -p "$LOGS_DIR"

# Pipeline state file
cat > "$LOGS_DIR/test-pipeline.json" << 'JSON'
{
  "id": "test-pipeline",
  "name": "Test Pipeline",
  "started_at": 1700000000,
  "pipeline_file": "/tmp/pipeline.json",
  "stages": [
    {
      "name": "Plan",
      "index": 0,
      "status": "done",
      "run_ids": ["test-pipeline-plan"],
      "task_files": ["tasks-plan.json"],
      "pass_outputs_to_next": true
    },
    {
      "name": "Implement",
      "index": 1,
      "status": "failed",
      "run_ids": ["test-pipeline-implement"],
      "task_files": ["tasks-implement.json"],
      "pass_outputs_to_next": false
    }
  ]
}
JSON

# Run state for Plan stage
mkdir -p "$LOGS_DIR/test-pipeline-plan"
cat > "$LOGS_DIR/test-pipeline-plan/state.json" << 'JSON'
{
  "log_dir": "/tmp/logs/test-pipeline-plan",
  "started_at": 1700000000,
  "ecc_enabled": true,
  "tasks": [
    {
      "id": "plan-task",
      "name": "Plan Task",
      "status": "done",
      "model": "opus",
      "cost_usd": 0.50,
      "started_at": 1700000000,
      "finished_at": 1700000120
    }
  ]
}
JSON
echo "This is the plan output. It describes the implementation strategy." > "$LOGS_DIR/test-pipeline-plan/plan-task.output.md"

# Run state for Implement stage
mkdir -p "$LOGS_DIR/test-pipeline-implement"
cat > "$LOGS_DIR/test-pipeline-implement/state.json" << 'JSON'
{
  "log_dir": "/tmp/logs/test-pipeline-implement",
  "started_at": 1700000130,
  "ecc_enabled": true,
  "tasks": [
    {
      "id": "impl-task",
      "name": "Implement Task",
      "status": "failed",
      "model": "sonnet",
      "cost_usd": 0.30,
      "started_at": 1700000130,
      "finished_at": 1700000300
    }
  ]
}
JSON
echo "Error: Build failed with exit code 1." > "$LOGS_DIR/test-pipeline-implement/impl-task.output.md"

# --- Test 1: _build_summary_prompt returns valid prompt ---
echo ""
echo "Test 1: _build_summary_prompt produces correct XML structure"
PROMPT=$(python3 -c "
${IMPORT_HELPER}
from pathlib import Path
import json

logs_dir = Path('$LOGS_DIR')
pipeline_data = json.loads((logs_dir / 'test-pipeline.json').read_text())
prompt = mod._build_summary_prompt(pipeline_data, logs_dir)
print(prompt)
")
assert_contains "Prompt includes pipeline name" "Test Pipeline" "$PROMPT"
assert_contains "Prompt includes run ID" "test-pipeline" "$PROMPT"
assert_contains "Prompt includes stage Plan" 'name="Plan"' "$PROMPT"
assert_contains "Prompt includes stage Implement" 'name="Implement"' "$PROMPT"
assert_contains "Prompt includes SUCCEEDED status" "SUCCEEDED" "$PROMPT"
assert_contains "Prompt includes FAILED status" "FAILED" "$PROMPT"
assert_contains "Prompt includes plan output" "implementation strategy" "$PROMPT"
assert_contains "Prompt includes impl output" "Build failed" "$PROMPT"
assert_contains "Prompt overall status is PARTIAL" "Overall status: PARTIAL" "$PROMPT"

# --- Test 2: _truncate_output truncates long text ---
echo ""
echo "Test 2: _truncate_output truncation"
RESULT=$(python3 -c "
${IMPORT_HELPER}

short = 'hello'
assert mod._truncate_output(short) == short, 'Short text unchanged'
print('short_ok')

long_text = 'x' * 10000
truncated = mod._truncate_output(long_text)
assert truncated.startswith('(truncated'), f'Starts with truncation note: {truncated[:50]}'
assert len(truncated) < 7000, f'Truncated length: {len(truncated)}'
print('long_ok')
")
assert_contains "Short text unchanged" "short_ok" "$RESULT"
assert_contains "Long text truncated" "long_ok" "$RESULT"

# --- Test 3: _build_summary_prompt returns None when all tasks skipped ---
echo ""
echo "Test 3: _build_summary_prompt returns None for all-skipped pipeline"

SKIPPED_DIR="$TMPDIR/logs-skipped"
mkdir -p "$SKIPPED_DIR"
cat > "$SKIPPED_DIR/skipped-pipeline.json" << 'JSON'
{
  "id": "skipped-pipeline",
  "name": "Skipped Pipeline",
  "started_at": 1700000000,
  "stages": [
    {
      "name": "Plan",
      "index": 0,
      "status": "skipped",
      "run_ids": [],
      "task_files": []
    }
  ]
}
JSON

RESULT=$(python3 -c "
${IMPORT_HELPER}
from pathlib import Path
import json

logs_dir = Path('$SKIPPED_DIR')
data = json.loads((logs_dir / 'skipped-pipeline.json').read_text())
result = mod._build_summary_prompt(data, logs_dir)
print('none' if result is None else 'not_none')
")
assert_eq "All-skipped pipeline returns None" "none" "$RESULT"

# --- Test 4: _pipeline_summary_path returns correct path ---
echo ""
echo "Test 4: _pipeline_summary_path"
RESULT=$(python3 -c "
${IMPORT_HELPER}
from pathlib import Path

p = mod._pipeline_summary_path(Path('/tmp/logs'), 'my-pipeline')
print(p)
")
assert_eq "Summary path" "/tmp/logs/my-pipeline.summary.md" "$RESULT"

# --- Test 5: _generate_summary_sync returns cached if file exists ---
echo ""
echo "Test 5: Immutability — cached summary returned without regeneration"

echo "# Existing summary" > "$LOGS_DIR/test-pipeline.summary.md"
RESULT=$(python3 -c "
${IMPORT_HELPER}
from pathlib import Path

summary, error = mod._generate_summary_sync('test-pipeline', Path('$LOGS_DIR'))
print(summary.strip() if summary else 'ERROR')
print(error or 'none')
")
assert_contains "Returns cached summary" "Existing summary" "$RESULT"
assert_contains "No error for cached" "none" "$RESULT"

# Clean up the cached file for other tests
rm -f "$LOGS_DIR/test-pipeline.summary.md"

# --- Test 6: _generate_summary_sync returns no_output for skipped pipeline ---
echo ""
echo "Test 6: Skipped pipeline returns no_output error"
RESULT=$(python3 -c "
${IMPORT_HELPER}
from pathlib import Path

summary, error = mod._generate_summary_sync('skipped-pipeline', Path('$SKIPPED_DIR'))
print(summary or 'none')
print(error or 'none')
")
assert_eq "Summary is None" "none" "$(echo "$RESULT" | head -1)"
assert_eq "Error is no_output" "no_output" "$(echo "$RESULT" | tail -1)"

# --- Test 7: Pipeline not found ---
echo ""
echo "Test 7: _generate_summary_sync returns error for missing pipeline"
RESULT=$(python3 -c "
${IMPORT_HELPER}
from pathlib import Path

summary, error = mod._generate_summary_sync('nonexistent', Path('$LOGS_DIR'))
print(summary or 'none')
print(error or 'none')
")
assert_eq "Summary is None" "none" "$(echo "$RESULT" | head -1)"
assert_contains "Error mentions not found" "not found" "$(echo "$RESULT" | tail -1)"

# --- Test 8: Duration calculation ---
echo ""
echo "Test 8: Duration calculation in prompt"
DURATION=$(python3 -c "
${IMPORT_HELPER}
from pathlib import Path
import json

logs_dir = Path('$LOGS_DIR')
data = json.loads((logs_dir / 'test-pipeline.json').read_text())
prompt = mod._build_summary_prompt(data, logs_dir)
# Extract Total duration line
for line in prompt.split('\n'):
    if 'Total duration' in line:
        print(line.strip())
        break
")
assert_contains "Duration includes minutes" "5m 0s" "$DURATION"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
