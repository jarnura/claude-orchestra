# Codebase Audit: claude-orchestra

**Date**: 2026-03-26
**Scope**: Full codebase analysis across architecture, security, reliability, and code quality

---

## Phase 1: Understanding — How It Works

### Purpose & Domain

claude-orchestra is a **parallel task orchestrator for Claude Code**. It solves the problem of running multiple Claude Code sessions concurrently — batch code reviews, multi-file refactors, parallel security audits — with optional intelligence from an "Everything-Claude-Code" (ECC) plugin system that injects agents, skills, and hook profiles into each session.

**Target users**: Developers and teams running Claude Code at scale who need to parallelize work across repositories or task lists.

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Core orchestrator | Bash (`bin/orchestra`, 403 lines) |
| Web server/API | Python 3 (`bin/orchestra-serve`, 3,127 lines) — `http.server` stdlib |
| TUI dashboard | Python 3 + `rich` library (`bin/orchestra-dashboard`, 628 lines) |
| Markdown converter | Embedded Python 3 in Bash (`bin/orchestra-convert`) |
| Report generator | Embedded Python 3 in Bash (`bin/orchestra-report`) |
| Frontend viewer | Single-file HTML/CSS/JS (`viewer/index.html`) |
| Data format | JSON (tasks, state, pipelines), JSONL (streams), Markdown (task authoring) |
| CLI dependency | `claude` CLI, `jq` |
| Auth (unused) | PBKDF2-HMAC-SHA256 password hashing, HS256 JWT tokens |

No traditional database, no containers, no external services beyond the Claude CLI.

### Entry Points

| Entry Point | Type | Purpose |
|-------------|------|---------|
| `bin/orchestra <tasks.json>` | CLI | Main orchestrator — runs tasks in parallel |
| `bin/orchestra-serve` | HTTP server | REST API + SSE for web dashboard |
| `bin/orchestra-pipeline <pipeline.json>` | CLI | Multi-stage pipeline with output passing |
| `bin/orchestra-spawn "prompt"` | CLI | Quick single-task launcher |
| `bin/orchestra-convert <tasks.md>` | CLI | Markdown → JSON task conversion |
| `bin/orchestra-dashboard <tasks.json>` | TUI | Rich terminal dashboard |
| `bin/orchestra-add` | CLI | Add single task to JSON file |
| `bin/orchestra-reset` | CLI | Reset all task statuses to pending |
| `bin/orchestra-report <log_dir>` | CLI | Generate summary report from run logs |

### Typical Request Flow (Task Execution)

```
User authors tasks.md
  → orchestra-convert → tasks.json
  → orchestra reads tasks.json
  → For each task (up to MAX_PARALLEL=5 concurrent):
      → ecc-adapter resolves agents/skills/hooks
      → prompt-builder assembles compound system prompt (≤50KB)
      → echo "$prompt" | claude --print --output-format stream-json | jq
      → Stream output written to logs/{run_id}/{task_id}.stream.jsonl
      → Final output saved to logs/{run_id}/{task_id}.output.md
      → state.json updated on each task transition
  → orchestra-report generates summary
```

### Key Modules & Responsibilities

| Module | Responsibility |
|--------|---------------|
| `lib/config.sh` | Configuration loading with cascade: env > local conf > user conf > defaults |
| `lib/ecc-adapter.sh` | Facade for ECC integration — agent/skill/hook resolution |
| `lib/prompt-builder.sh` | Assembles compound prompts with 50KB size limit (truncates skills first) |
| `adapters/ecc/detect.sh` | Detects ECC installation by scanning `~/.claude/agents/` |
| `adapters/ecc/agents.sh` | Resolves agent `.md` files, extracts model from YAML frontmatter |
| `adapters/ecc/skills.sh` | Resolves skill `SKILL.md` files from directory-based structure |
| `adapters/ecc/hooks.sh` | Maps hook profile names (strict/standard/minimal) to env vars |
| `bin/orchestra-serve` | Full REST API (40+ endpoints), SSE broker, workspace management, brainstorm |

### Data Flow

```
Input:  tasks.md / tasks.json / pipeline.json / CLI prompt
  ↓
Config: orchestra.conf → env vars → defaults
  ↓
ECC:    agents/*.md + skills/*/SKILL.md + hook profiles → compound prompt
  ↓
Exec:   echo prompt | claude --print → stream-json → jq → .stream.jsonl
  ↓
State:  logs/{run_id}/state.json (updated per task transition, polled by dashboard)
  ↓
Output: logs/{run_id}/{task_id}.output.md → orchestra-report → summary
```

---

## Phase 2: Architecture Deep Dive

### Architecture Pattern

**Hybrid shell-based process orchestrator + Python HTTP API layer.**

The core is a **Bash process manager** (forked from `claude-fleet`) using classic Unix patterns: PID tracking, slot scheduling, a reap loop (`wait -n`), and signal traps. The Python layer (`orchestra-serve`) adds a REST API, SSE event streaming, and workspace management on top.

This is effectively a **two-tier architecture**:
1. **Orchestration tier** (Bash): process lifecycle, task scheduling, log management
2. **API/UI tier** (Python): HTTP endpoints, SSE broker, brainstorm integration, config management

There is no message queue, no service mesh — communication is via the filesystem (JSON state files) and subprocess spawning.

### Dependency Graph

```
orchestra-serve (Python HTTP)
  ├── subprocess → bin/orchestra
  ├── subprocess → bin/orchestra-pipeline
  ├── subprocess → bin/orchestra-convert
  └── filesystem → logs/*/state.json (polling)

bin/orchestra (Bash)
  ├── lib/config.sh
  ├── lib/ecc-adapter.sh
  │     ├── adapters/ecc/detect.sh
  │     ├── adapters/ecc/agents.sh
  │     ├── adapters/ecc/skills.sh
  │     └── adapters/ecc/hooks.sh
  ├── lib/prompt-builder.sh
  └── subprocess → claude CLI

bin/orchestra-pipeline (Bash)
  └── bin/orchestra (subprocess per stage)

bin/orchestra-spawn (Bash)
  └── bin/orchestra (subprocess)

bin/orchestra-dashboard (Python)
  └── filesystem → logs/*/state.json (polling)
```

**Circular dependencies**: None detected. The dependency graph is a clean DAG.

**Tight coupling**: `orchestra-serve` duplicates some logic that exists in the Bash scripts (task JSON manipulation, path resolution). The Python layer sometimes shells out to Bash scripts and sometimes reimplements their logic inline.

### State Management

All state is **file-based**:
- `logs/{run_id}/state.json` — task status, cost, timing (updated atomically via mktemp + mv)
- `logs/{run_id}/{task_id}.stream.jsonl` — real-time stream data (append-only)
- `logs/{run_id}/metadata.json` — run metadata (repo, pipeline name, timestamps)
- `{data_dir}/users.json` — user accounts (thread-locked, atomic writes)

No in-memory state survives process restarts (except the SSE broker's subscriber queues, which are ephemeral).

**Cache**: `orchestra-serve` has a 5-second in-memory cache (`_CACHE_TTL = 5`) for file reads, with a thread-safe dict keyed by file path.

### Configuration & Environment

**Cascade hierarchy** (highest priority first):
1. Environment variables (`MAX_PARALLEL`, `MODEL`, etc.)
2. `./orchestra.conf` (project-local)
3. `$ORCHESTRA_CONFIG` (custom path)
4. `~/.config/claude-orchestra/config` (user global)
5. Hardcoded defaults in `lib/config.sh`

Config files are **Bash-sourced** (`source "$cfg"`) — this means config files can execute arbitrary shell commands. This is by design (common in Unix tools) but is a security consideration.

**Secrets**: `ORCHESTRA_JWT_SECRET` env var for JWT signing. `ANTHROPIC_API_KEY` for Claude CLI. Neither is persisted to disk by the tool itself.

### Error Handling & Logging

**Bash scripts**: Use `set -eo pipefail` (exit on error, pipe failures). The main orchestrator has a `trap cleanup EXIT INT TERM` for graceful process cleanup. Errors are printed to stderr with color codes.

**Python server**: Returns structured JSON errors with HTTP status codes (400, 404, 409, 500, 503, 504). Subprocess errors include truncated stderr (200 chars). No structured logging framework — uses `print()` to stdout.

**Observability**: Minimal. No structured logging, no metrics, no request tracing. The SSE broker broadcasts events for UI consumption but these are not persisted.

### Testing Strategy

5 Bash test scripts covering the ECC adapter layer:

| Test | What it tests |
|------|--------------|
| `test-ecc-detect.sh` | ECC installation detection, enable/disable flags |
| `test-agent-resolution.sh` | Agent .md file resolution, model extraction |
| `test-skill-resolution.sh` | Skill SKILL.md resolution, listing |
| `test-prompt-builder.sh` | Prompt assembly, 50KB size limit enforcement |
| `test-convert.sh` | Markdown → JSON conversion, field extraction |

**Coverage gaps**: Zero tests for `orchestra-serve` (3,127 lines, 40+ endpoints). Zero tests for the main `orchestra` script's process management. No integration tests for the full task execution flow. No Python unit tests at all.

---

## Phase 3: Gap Analysis

### Security

| # | Issue | Severity | Location | Details |
|---|-------|----------|----------|---------|
| S1 | No authentication on any HTTP endpoint | **Critical** | `bin/orchestra-serve` (all handlers) | Auth code exists (JWT, password hashing) but is never wired into request handlers. All 40+ endpoints are publicly accessible. |
| S2 | Path traversal allows access to sensitive home files | **High** | `bin/orchestra-serve:542` (`_validate_workspace_path`) | Validation only checks paths are under `$HOME`. Allows reading `~/.ssh/`, `~/.aws/credentials`, `~/.bash_history`, etc. |
| S3 | Predictable temp file path in orchestra-spawn | **High** | `bin/orchestra-spawn:121` | Uses `/tmp/orchestra-${ID}.json` instead of `mktemp`. Attackable via symlink/race condition (CWE-377). |
| S4 | Config files execute arbitrary code | **Medium** | `lib/config.sh:29` | `source "$cfg"` runs any shell commands in config files. Standard Unix pattern but risky if configs are user-editable or fetched remotely. |
| S5 | CORS allows all origins | **Medium** | `bin/orchestra-serve:1116` | `Access-Control-Allow-Origin: *` — acceptable for local dev tool, problematic if exposed on a network. |
| S6 | No rate limiting on brainstorm endpoints | **Medium** | `bin/orchestra-serve` (POST brainstorm routes) | Unlimited Claude CLI invocations can generate unbounded API costs. |
| S7 | Unquoted `$allowed_tools` in command array | **Low** | `bin/orchestra:296` | Word splitting possible if tool names contain spaces. |

### Reliability

| # | Issue | Severity | Location | Details |
|---|-------|----------|----------|---------|
| R1 | Temp files never cleaned up on failure | **Medium** | `bin/orchestra:199-223`, `bin/orchestra-pipeline:88,239` | `mktemp` used without `trap` cleanup. Script crash orphans temp files. |
| R2 | Background processes not cleaned on server shutdown | **Medium** | `bin/orchestra-serve` (subprocess.Popen with `start_new_session=True`) | No PID tracking or `atexit` handler. Zombie processes possible. |
| R3 | SSE broker drops events silently | **Medium** | `bin/orchestra-serve:581` | Queue size 256, full queues silently drop. No backpressure mechanism. |
| R4 | No retry logic for Claude CLI failures | **Low** | `bin/orchestra:305` | A transient API error fails the entire task. No retry with backoff. |
| R5 | File-based state has no locking between orchestra and serve | **Low** | `logs/*/state.json` | Concurrent reads during writes could see partial JSON. Atomic mv helps but timing window exists. |

### Scalability

| # | Issue | Severity | Location | Details |
|---|-------|----------|----------|---------|
| SC1 | `ThreadingHTTPServer` with stdlib server | **Medium** | `bin/orchestra-serve` | Python's `http.server` is not production-grade. No connection pooling, no async I/O, limited concurrency. |
| SC2 | File-based state polling | **Low** | `bin/orchestra-dashboard`, SSE broker | Dashboard polls `state.json` every 2s. Works for <100 tasks but doesn't scale. |
| SC3 | No pagination on `/api/runs` | **Low** | `bin/orchestra-serve` | Returns all runs. Could be slow with hundreds of historical runs. |

### Code Quality

| # | Issue | Severity | Location | Details |
|---|-------|----------|----------|---------|
| CQ1 | `orchestra-serve` is a 3,127-line monolith | **High** | `bin/orchestra-serve` | All 40+ endpoints, auth, SSE broker, subprocess management, caching, and workspace logic in a single file with no module decomposition. |
| CQ2 | Duplicated logic between Bash and Python layers | **Medium** | `bin/orchestra-serve` vs `bin/orchestra`, `bin/orchestra-convert` | Task JSON manipulation, path resolution, and state management reimplemented in both. |
| CQ3 | Embedded Python scripts in Bash | **Medium** | `bin/orchestra-convert`, `bin/orchestra-report` | Large Python scripts passed via `python3 -c "..."`. Difficult to test, lint, or type-check. |
| CQ4 | No type annotations in orchestra-serve | **Low** | `bin/orchestra-serve` | Large Python codebase with no type hints on handler methods. |
| CQ5 | Inconsistent error message formatting | **Low** | Various | Some errors use JSON, others plain text. Some to stderr, others to stdout. |

### DevOps & CI/CD

| # | Issue | Severity | Location | Details |
|---|-------|----------|----------|---------|
| D1 | No CI/CD pipeline | **High** | Repository root | No GitHub Actions, no `.github/workflows/`. Tests must be run manually. |
| D2 | No linting or formatting enforcement | **Medium** | Repository root | No `shellcheck` for Bash, no `ruff`/`flake8` for Python, no pre-commit hooks. |
| D3 | No containerization | **Low** | Repository root | No Dockerfile. Install is manual symlink-based (`install.sh`). |
| D4 | No dependency manifest | **Low** | Repository root | No `requirements.txt` or `pyproject.toml`. Python deps (`rich`) are runtime-discovered via ImportError. |

### Documentation

| # | Issue | Severity | Location | Details |
|---|-------|----------|----------|---------|
| DO1 | No API documentation | **Medium** | `bin/orchestra-serve` | 40+ REST endpoints with no OpenAPI spec, no route documentation, no example payloads. |
| DO2 | No architecture decision records (ADRs) | **Low** | Repository root | Key decisions documented in CLAUDE.md but not in a structured ADR format. |
| DO3 | README is solid | N/A | `README.md` | Good coverage of installation, usage, configuration, and examples. |

### Observability

| # | Issue | Severity | Location | Details |
|---|-------|----------|----------|---------|
| O1 | No structured logging | **High** | `bin/orchestra-serve` | Uses `print()` only. No log levels, no timestamps, no request IDs, no correlation. |
| O2 | No request access logs | **Medium** | `bin/orchestra-serve` | No record of who called which endpoint, when, or what the response was. |
| O3 | No metrics | **Medium** | All | No task throughput metrics, no latency percentiles, no error rates. |
| O4 | No health check endpoint | **Low** | `bin/orchestra-serve` | No `/health` or `/ready` endpoint for monitoring. |

---

## Phase 4: Future Scope & Recommendations

### Quick Wins (1-2 sprints)

| # | What | Why | Effort |
|---|------|-----|--------|
| QW1 | **Fix predictable temp file in `orchestra-spawn`** — replace `/tmp/orchestra-${ID}.json` with `mktemp --suffix=.json` | Eliminates CWE-377 symlink/race vulnerability | Small |
| QW2 | **Add `trap 'rm -f "$tmp"' EXIT` to all Bash scripts using mktemp** | Prevents temp file accumulation on crash | Small |
| QW3 | **Quote `$allowed_tools`** in `bin/orchestra:296` — change to `cmd+=(--allowedTools "$allowed_tools")` | Prevents word splitting on tool names with spaces | Small |
| QW4 | **Add a health endpoint** (`/api/health`) to `orchestra-serve` | Enables basic monitoring and load balancer integration | Small |
| QW5 | **Add `shellcheck` and `ruff` to a GitHub Actions workflow** | Catches bugs automatically on every push | Small |
| QW6 | **Create `requirements.txt`** listing `rich` (and version pin) | Makes dependency installation reproducible | Small |
| QW7 | **Add Python logging module** to `orchestra-serve` — replace `print()` with `logging.info/error` | Adds timestamps, levels, and structured output | Small |
| QW8 | **Restrict `_validate_workspace_path` to allowed directories** — require paths contain a git repo (check for `.git/`) | Prevents reading `~/.ssh/`, `~/.aws/` etc. | Small |

### Medium-Term Improvements (Next quarter)

| # | What | Why | Effort |
|---|------|-----|--------|
| MT1 | **Decompose `orchestra-serve` into modules** — split into `routes/`, `services/`, `models/` packages | 3,127-line monolith is unmaintainable. Separate HTTP handlers from business logic and subprocess management. | Medium |
| MT2 | **Add Python test suite** for `orchestra-serve` — pytest with `httpx` for endpoint testing | Zero test coverage on 3,127 lines of API code. Cover path validation, input sanitization, error cases. | Medium |
| MT3 | **Wire authentication into HTTP handlers** — the code already exists, just needs middleware | Auth code (JWT, password hashing) is implemented but unused. Add `@require_auth` decorator. | Medium |
| MT4 | **Extract embedded Python from Bash scripts** — move `orchestra-convert` and `orchestra-report` logic into standalone `.py` files | Enables linting, type checking, and unit testing of the Python code. | Small |
| MT5 | **Add rate limiting** — simple token bucket on brainstorm endpoints | Prevents unbounded API cost from repeated brainstorm calls. | Small |
| MT6 | **Add integration test suite** — end-to-end tests using mock Claude CLI | Validates the full flow: tasks.md → convert → orchestrate → report. | Medium |
| MT7 | **Implement proper process lifecycle management** in `orchestra-serve` — track spawned PIDs, add `atexit` cleanup | Eliminates zombie processes on server shutdown. | Small |

### Long-Term Vision (Roadmap)

| # | What | Why | Effort |
|---|------|-----|--------|
| LT1 | **Migrate `orchestra-serve` to a proper ASGI framework** (FastAPI/Starlette) | stdlib `http.server` is not production-grade. FastAPI gives async, OpenAPI docs, dependency injection, and middleware for free. | Large |
| LT2 | **Add persistent storage backend** (SQLite or PostgreSQL) | File-based JSON state doesn't support queries, concurrent writes, or historical analytics. SQLite is zero-config and would support pagination, filtering, and aggregation. | Large |
| LT3 | **Add task retry with exponential backoff** | Transient Claude API failures currently fail the entire task. Retry logic would improve reliability significantly. | Medium |
| LT4 | **Containerize with Docker** and add `docker-compose.yml` | Simplifies deployment, isolates dependencies, enables reproducible environments. | Medium |
| LT5 | **Add OpenTelemetry instrumentation** | Structured tracing across task execution, API requests, and subprocess calls. Enables debugging complex pipeline failures. | Large |
| LT6 | **Support distributed execution** — run tasks across multiple machines | Current model is single-machine. A queue-based architecture (Redis/NATS) would enable horizontal scaling for large task sets. | Large |

---

## Summary

claude-orchestra is a well-crafted tool for its intended use case — a **local developer utility** for parallelizing Claude Code sessions. The Bash orchestrator core is clean, the ECC adapter system is elegantly designed with proper input validation, and the overall architecture is pragmatic.

**Strengths**:
- Clean Unix-style process management with proper signal handling
- Smart ECC integration that degrades gracefully when unavailable
- Good input validation on identifiers (regex-based) and paths (resolve + boundary check)
- Atomic file writes prevent corruption
- Well-documented in README and CLAUDE.md

**Primary risks**:
- The Python API layer (`orchestra-serve`) is a 3,127-line monolith with no tests, no auth enforcement, and no structured logging
- Several temp file handling vulnerabilities (predictable paths, no cleanup traps)
- The tool is designed for trusted local use but exposes an HTTP API that could be accessed by any local process

**Recommended priority**: Start with the quick wins (QW1-QW8) to close security gaps, then invest in MT1-MT2 to make the Python layer maintainable and testable.
