# claude-orchestra

A parallel task orchestrator for Claude Code with [Everything-Claude-Code](https://github.com/affaan-m/everything-claude-code) intelligence.

Run N concurrent Claude Code sessions from a task file, with optional agent/skill/hook injection per task.

## Quick Start

```bash
# Install
./install.sh

# Run tasks in parallel (5 concurrent by default)
orchestra tasks.md

# Run with 10 parallel sessions
MAX_PARALLEL=10 orchestra tasks.md

# Monitor with real-time dashboard
orchestra-dashboard tasks.json

# Quick single task with agent
orchestra-spawn "Audit auth module" --agent security-reviewer --readonly

# Multi-stage pipeline
orchestra-pipeline pipeline.json
```

## How It Works

```
tasks.md (with agents/skills/hooks)
    |
    v
orchestra-convert (parse enhanced metadata)
    |
    v
orchestra (parallel process orchestrator)
    |
    |-- for each task:
    |     1. Resolve ECC agents -> read agent .md files
    |     2. Resolve ECC skills -> read SKILL.md files
    |     3. Build compound system prompt (user + agents + skills)
    |     4. Set ECC_HOOK_PROFILE per task
    |     5. Launch: echo "$prompt" | claude --print --append-system-prompt ...
    |
    v
logs/<timestamp>/
    task-id.stream.jsonl   # Raw stream output
    task-id.output.md      # Extracted text
    task-id.log            # Stderr/errors
    state.json             # Live status for dashboard
```

## Task Format

```markdown
## Security Audit of Auth Module
- workdir: ~/code/myapp
- model: opus
- effort: high
- agents: security-reviewer, code-reviewer    # ECC agents (comma-separated)
- skills: springboot-patterns, verification-loop  # ECC skills
- hooks: strict                                   # Hook profile
- allowedTools: Read Grep Glob Agent
- appendSystemPrompt: Extra context

Audit the authentication module for OWASP Top 10 vulnerabilities.
```

### New Fields (vs claude-fleet)

| Field | Description | Example |
|-------|-------------|---------|
| `agents` | ECC agent names (comma-separated) | `security-reviewer, code-reviewer` |
| `skills` | ECC skill names (comma-separated) | `springboot-patterns, verification-loop` |
| `hooks` | Hook profile per task | `strict`, `standard`, `minimal` |

## Commands

| Command | Description |
|---------|-------------|
| `orchestra <tasks.md\|json>` | Run tasks in parallel |
| `orchestra-convert <in.md> [out.json]` | Markdown to JSON conversion |
| `orchestra-dashboard <tasks.json>` | Real-time TUI monitor |
| `orchestra-pipeline <pipeline.json>` | Multi-stage sequential pipeline |
| `orchestra-spawn "prompt" [opts]` | Quick single-task launcher |
| `orchestra-add <id> <name> <dir> <prompt>` | Append task to JSON file |
| `orchestra-reset <tasks.json>` | Reset all tasks to pending |
| `orchestra-report <log-dir>` | Aggregate outputs into summary |

## Pipeline Templates

Pre-built pipelines in `templates/pipelines/`:

| Template | Stages |
|----------|--------|
| `feature.json` | Plan -> Implement -> Review (code + security) |
| `audit.json` | Parallel: security + code-quality + architecture |
| `bugfix.json` | Diagnose -> Fix -> Verify |
| `refactor.json` | Architect -> Implement -> Test -> Review |
| `release.json` | Test -> Security -> Docs + Changelog |

### Pipeline Features

- **`pass_outputs_to_next`**: Stage outputs are injected as context into next stage's task prompts
- **`aggregate`**: Auto-generate summary report when pipeline completes

```json
{
  "name": "Feature Pipeline",
  "stages": [
    {"name": "Plan", "tasks": [{"file": "tasks-plan.json", "max_parallel": 1}], "pass_outputs_to_next": true},
    {"name": "Implement", "tasks": [{"file": "tasks-impl.json", "max_parallel": 5}]},
    {"name": "Review", "tasks": [{"file": "tasks-review.json", "max_parallel": 3}]}
  ],
  "aggregate": true
}
```

## ECC Integration

When [Everything-Claude-Code](https://github.com/affaan-m/everything-claude-code) is installed:

### Agents

Specify `agents` in task metadata to inject agent instructions into the system prompt:

```markdown
## My Task
- agents: security-reviewer, code-reviewer
```

Available agents: `planner`, `architect`, `tdd-guide`, `code-reviewer`, `security-reviewer`, `database-reviewer`, `e2e-runner`, `refactor-cleaner`, `doc-updater`, `python-reviewer`, `go-reviewer`, `kotlin-reviewer`, `loop-operator`, `chief-of-staff`, `harness-optimizer`, `build-error-resolver`

### Skills

Specify `skills` to append skill reference material:

```markdown
## My Task
- skills: backend-patterns, verification-loop
```

### Hook Profiles

Control quality gates per task:

```markdown
## My Task
- hooks: strict    # strict | standard | minimal
```

### Discovery

```bash
orchestra-spawn --list-agents    # List available agents
orchestra-spawn --list-skills    # List available skills
```

### Standalone Mode

Without ECC, agent/skill/hook fields are silently ignored. The tool works as a standard parallel orchestrator.

Force standalone: `ECC_ENABLED=false orchestra tasks.json`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_PARALLEL` | `5` | Max concurrent sessions |
| `POLL_INTERVAL` | `10` | Seconds between schedule cycles |
| `MODE` | `batch` | `batch` or `interactive` (worktree+tmux) |
| `CLAUDE_CMD` | `claude` | CLI binary |
| `MODEL` | `opus` | Default model |
| `EFFORT` | `high` | Default effort level |
| `ECC_ENABLED` | `auto` | `auto`, `true`, `false` |
| `ECC_DIR` | `~/.claude` | ECC installation path |
| `ECC_HOOK_PROFILE` | `standard` | Default hook profile |

## Configuration

Config hierarchy (later overrides earlier):

1. `~/.config/claude-orchestra/config` (user global)
2. `$ORCHESTRA_CONFIG` (env override)
3. `./orchestra.conf` (project local)
4. Environment variables (highest priority)

Config files are bash-sourceable:

```bash
# orchestra.conf
MAX_PARALLEL=10
MODEL=sonnet
ECC_HOOK_PROFILE=strict
```

## Dependencies

- Claude Code CLI (`claude`)
- `jq` (JSON processing)
- Python 3 (for convert and dashboard)
- `rich` Python library (dashboard only: `pip install rich`)

## Credits

Built on [claude-fleet](https://github.com/nammayatri/claude-fleet) by NammaYatri.
Enhanced with [Everything-Claude-Code](https://github.com/affaan-m/everything-claude-code) integration.
