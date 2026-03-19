# UI Refactor: Workspace & Runs Screen Improvements

## Task 1: Backend - Add Active Runs API with Repo Filter
- workdir: /home/jarnura/projects/claude-orchestra
- model: sonnet
- effort: medium

Add API endpoints for active runs and filtering:

1. `GET /api/runs/active` - Return currently running tasks across all runs
```json
{
  "active_tasks": [
    {
      "run_id": "2026-03-20_04-21-13",
      "task_id": "backend-api",
      "task_name": "Backend API",
      "repo": "/home/jarnura/projects/claude-orchestra",
      "status": "running",
      "started_at": 1234567890
    }
  ]
}
```

2. `GET /api/runs?repo=/path/to/repo` - Filter runs by repo path

3. `GET /api/runs/active?repo=/path/to/repo` - Filter active tasks by repo

Implementation:
- Parse state.json files in logs directory
- Filter tasks where status is "running"
- Extract repo from task workdir or run metadata
- Cache results briefly (5 seconds) to avoid repeated file reads

---

## Task 2: Backend - Add Pipeline Templates API
- workdir: /home/jarnura/projects/claude-orchestra
- model: sonnet
- effort: medium

Add API endpoint to list available pipeline templates:

`GET /api/pipelines/templates`
```json
{
  "templates": [
    {
      "name": "feature",
      "description": "Plan → Implement → Verify pipeline for new features",
      "stages": ["plan", "implement", "verify"],
      "file": "pipelines/feature.json"
    },
    {
      "name": "bugfix", 
      "description": "Investigate → Fix → Test pipeline for bug fixes",
      "stages": ["investigate", "fix", "test"],
      "file": "pipelines/bugfix.json"
    }
  ]
}
```

Also add pipeline documentation:
`GET /api/pipelines/docs`
```json
{
  "how_to_write": "## Pipeline Format\n\nPipelines are JSON files in the `pipelines/` directory...",
  "example": "{\"name\": \"my-pipeline\", \"stages\": [...]}"
}
```

Check templates/ directory for existing pipeline templates and include them.

---

## Task 3: Frontend - Add Active Runs Section to Workspace
- workdir: /home/jarnura/projects/claude-orchestra
- model: sonnet
- effort: high

Add "Active Runs" section to Workspace screen that shows:
- Currently running tasks for the selected repo
- Progress indicator (running spinner)
- Link to the full run details
- Cancel button (if implementable)

UI structure after repo selection:
```html
<div class="ws-section">
  <h3>Active Runs</h3>
  <div id="ws-active-runs">
    <!-- Show running tasks or "No active runs" message -->
  </div>
</div>

<div class="ws-section">
  <h3>Brainstorm</h3>
  <!-- Existing brainstorm panel -->
</div>
```

Add JavaScript:
- `wsLoadActiveRuns()` - Fetch active runs for selected repo
- `wsRenderActiveRuns(activeTasks)` - Render running tasks list
- Poll every 5 seconds when runs are active
- Show task name, run ID, elapsed time

---

## Task 4: Frontend - Add Pipeline Guide to Workspace
- workdir: /home/jarnura/projects/claude-orchestra
- model: sonnet
- effort: medium

Add "Pipeline Guide" section to Workspace screen:

```html
<div class="ws-section ws-pipeline-guide">
  <h3>Pipeline Guide</h3>
  <details>
    <summary>How to write pipelines</summary>
    <div class="pipeline-docs">
      <!-- Documentation loaded from API -->
    </div>
  </details>
  <div class="pipeline-templates">
    <label>Quick Start:</label>
    <select id="ws-pipeline-template">
      <option value="">Choose a template...</option>
      <!-- Templates from API -->
    </select>
    <button class="btn" onclick="wsUseTemplate()">Use Template</button>
  </div>
</div>
```

The guide should show:
1. Pipeline JSON format explanation
2. Stage configuration options
3. Available templates dropdown
4. Button to create new pipeline from template

---

## Task 5: Frontend - Add Repo Filter to Runs Screen
- workdir: /home/jarnura/projects/claude-orchestra
- model: sonnet
- effort: medium

Add repo filter dropdown to Runs screen:

```html
<div class="runs-filter">
  <label>Filter by repo:</label>
  <select id="runs-repo-filter" onchange="filterRuns()">
    <option value="">All repos</option>
    <!-- Populated from API -->
  </select>
</div>
```

Implementation:
- Fetch repos on Runs screen load
- Store filter value in URL param `?repo=/path`
- Filter the runs list based on selected repo
- Update URL when filter changes
- Read filter from URL on page load

---

## Task 6: Frontend - CSS for Workspace Sections
- workdir: /home/jarnura/projects/claude-orchestra
- model: haiku
- effort: low

Add CSS for new workspace sections:

```css
.ws-section {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 20px;
}

.ws-section h3 {
  margin: 0 0 12px 0;
  font-size: 1rem;
  color: var(--text);
}

.ws-active-run {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  background: var(--bg);
  border-radius: 4px;
  margin-bottom: 8px;
}

.ws-active-run .spinner {
  width: 16px;
  height: 16px;
  border: 2px solid var(--border);
  border-top-color: var(--blue);
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.ws-pipeline-guide details {
  margin-bottom: 12px;
}

.ws-pipeline-guide summary {
  cursor: pointer;
  color: var(--blue);
}

.ws-pipeline-guide pre {
  background: var(--bg);
  padding: 12px;
  border-radius: 4px;
  overflow-x: auto;
  font-size: 0.8rem;
}

.runs-filter {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 16px;
}
```

---

## Task 7: Backend - Add Run Metadata for Repo Tracking
- workdir: /home/jarnura/projects/claude-orchestra
- model: haiku
- effort: low

Modify the orchestra run API to include repo metadata:

`POST /api/workspace/orchestra/run` should also save a `metadata.json` in the log dir:
```json
{
  "repo_path": "/home/jarnura/projects/claude-orchestra",
  "tasks_file": "/home/jarnura/projects/claude-orchestra/tasks.json",
  "started_at": "2026-03-20T04:21:13Z",
  "triggered_from": "workspace"
}
```

This allows filtering runs by repo in the Runs screen.

Also update `_api_runs()` to read this metadata and include it in the response:
```json
{
  "id": "2026-03-20_04-21-13",
  "repo_path": "/home/jarnura/projects/claude-orchestra",
  ...
}
```
