# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

# claude-orchestra

A parallel task orchestrator for Claude Code with ECC (Everything-Claude-Code) intelligence.
Extends claude-fleet's proven process management with agent/skill/hook injection.

## Structure

```
bin/
  orchestra              # Main orchestrator — runs tasks in parallel with ECC integration
  orchestra-convert      # Converts tasks.md -> tasks.json (enhanced with agents/skills/hooks)
  orchestra-add          # Adds a single task to a tasks JSON file
  orchestra-reset        # Resets all tasks to pending
  orchestra-pipeline     # Multi-stage pipeline with output passing between stages
  orchestra-dashboard    # Real-time TUI dashboard with agent/skill columns (Python + rich)
  orchestra-spawn        # Quick single-task launcher (with --agent/--skill/--hooks flags)
  orchestra-report       # Aggregate pipeline outputs into summary report
lib/
  config.sh              # Shared configuration loading
  ecc-adapter.sh         # Core ECC integration facade
  prompt-builder.sh      # Compound prompt assembly with size limits
adapters/
  ecc/
    detect.sh            # ECC installation detection
    agents.sh            # Agent resolution and content loading
    skills.sh            # Skill resolution and content loading
    hooks.sh             # Hook profile resolution
templates/
  pipelines/             # Pre-built pipeline templates (feature, audit, bugfix, refactor, release)
  tasks/                 # Pre-built task templates
examples/
  tasks-hello-world.md   # Simple tasks (no ECC)
  tasks-with-agents.md   # Tasks with agent injection
  tasks-with-skills.md   # Tasks with skill injection
  pipeline.json          # Example multi-stage pipeline
tests/
  test-*.sh              # Test scripts
```

## Key Design Decisions

1. **Hybrid architecture**: Standalone tool + ECC adapter. Works without ECC (standalone mode), gains intelligence when ECC is present.
2. **Fork of claude-fleet**: Core process management (PID tracking, reap loop, slot scheduling) is inherited from claude-fleet's proven ~292-line Bash orchestrator.
3. **Agent injection via --append-system-prompt**: Agent .md files are read and concatenated into the claude CLI's `--append-system-prompt` flag.
4. **Skill injection**: Skill SKILL.md files are appended after agents. Skills are truncated first if combined prompt exceeds 50KB.
5. **Hook profiles per task**: `ECC_HOOK_PROFILE` env var is set per-task in the subshell, enabling strict/standard/minimal quality gates.
6. **Prompt via stdin**: `echo "$prompt" | claude --print ...` because `--allowedTools` is variadic and would consume the prompt arg.
7. **Stream output**: Tasks use `--output-format stream-json` piped through `jq` to extract text in real-time.
8. **Config hierarchy**: `./orchestra.conf` > `$ORCHESTRA_CONFIG` > `~/.config/claude-orchestra/config` > defaults.
9. **state.json**: The orchestrator writes `$LOG_DIR/state.json` on every task transition for the dashboard to poll.
10. **Pipeline output passing**: `pass_outputs_to_next: true` injects prior stage outputs as context into next stage tasks.

## Task Format

### Markdown (author-friendly, enhanced with agents/skills/hooks)

```markdown
## Task Name Here
- workdir: /path/to/repo
- model: opus
- effort: high
- agents: security-reviewer, code-reviewer
- skills: springboot-patterns, verification-loop
- hooks: strict
- allowedTools: Read Grep Glob Agent
- appendSystemPrompt: Optional extra instructions

Prompt text here. Everything until the next ## heading.
```

Convert: `orchestra-convert tasks.md tasks.json`

### JSON (machine format)

```json
{
  "tasks": [{
    "id": "task-name-slugified",
    "name": "Task Name",
    "prompt": "Full prompt...",
    "workdir": "/path/to/repo",
    "model": "opus",
    "effort": "high",
    "status": "pending",
    "allowedTools": "Read Grep Glob Agent",
    "appendSystemPrompt": "Optional",
    "agents": "security-reviewer, code-reviewer",
    "skills": "springboot-patterns, verification-loop",
    "hooks": "strict"
  }]
}
```

## Running

```bash
./install.sh                                # symlink bin/* to ~/.local/bin
orchestra tasks.json                        # run with 5 parallel (default)
MAX_PARALLEL=10 orchestra tasks.json        # run with 10 parallel
orchestra-dashboard tasks.json              # TUI monitor
orchestra-pipeline pipeline.json            # multi-stage pipeline
orchestra-spawn "prompt" --agent planner    # quick single-task
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `MAX_PARALLEL` | `5` | Max concurrent Claude sessions |
| `POLL_INTERVAL` | `10` | Seconds between reap/schedule cycles |
| `MODE` | `batch` | `batch` (--print) or `interactive` (--worktree --tmux) |
| `CLAUDE_CMD` | `claude` | CLI binary (`claude` or `happy`) |
| `ECC_ENABLED` | `auto` | ECC integration: `auto`, `true`, `false` |
| `ECC_DIR` | `~/.claude` | ECC installation directory |
| `ECC_HOOK_PROFILE` | `standard` | Default hook profile: `strict`, `standard`, `minimal` |

## ECC Integration

When ECC is detected (agents directory exists at `~/.claude/agents/`):
- **Agents**: Task `agents` field resolves agent .md files and injects them into system prompt
- **Skills**: Task `skills` field resolves SKILL.md files and appends them as reference material
- **Hooks**: Task `hooks` field sets `ECC_HOOK_PROFILE` env var in the task's subshell
- **Model override**: If a single agent is specified without explicit model, the agent's preferred model is used

When ECC is not detected, agent/skill/hook fields are silently ignored and the tool works as a standalone orchestrator.
