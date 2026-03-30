# Workspace Refactor: Brainstorm → Edit → Orchestra Flow

## Overview

Refactor the Workspace "Quick Run" section into a proper workflow:
1. **Brainstorm** → Generate tasks.md via Claude
2. **Edit** → Manual editing of tasks.md
3. **Orchestra** → Convert tasks.md → tasks.json and run parallel execution

---

## Task 1: Backend - Brainstorm API Endpoint

- workdir: /home/jarnura/projects/claude-orchestra
- model: sonnet
- effort: high

### Prompt

Add a new API endpoint `POST /api/workspace/brainstorm` to `bin/orchestra-serve`:

```python
# Request body:
{
  "repo_path": "/path/to/repo",
  "prompt": "User's brainstorming prompt",
  "model": "sonnet"  # optional, default sonnet
}

# Response:
{
  "tasks_md": "## Task 1\n- workdir: /path\n- model: opus\n\nPrompt here...\n\n## Task 2\n...",
  "tasks_file": "/path/to/repo/tasks.md",
  "task_count": 3
}
```

Implementation details:
1. The endpoint should call Claude CLI with a metis/planner-like system prompt
2. System prompt should instruct Claude to generate tasks in the markdown format (compatible with orchestra-convert)
3. Save the generated tasks.md to the repo path
4. Return both the content and the file path

Use subprocess to call claude CLI:
```python
cmd = ["claude", "--print", "--model", model, "--append-system-prompt", BRAINSTORM_SYSTEM_PROMPT]
result = subprocess.run(cmd, input=prompt, capture_output=True, text=True)
```

BRAINSTORM_SYSTEM_PROMPT should instruct:
- Generate tasks in markdown format compatible with orchestra-convert
- Each task should have: name, workdir, model, prompt
- Optionally include: agents, skills, hooks if relevant
- Split complex requests into parallelizable tasks
- Output ONLY the markdown, no explanations

---

## Task 2: Backend - Convert & Orchestra API Endpoint

- workdir: /home/jarnura/projects/claude-orchestra
- model: sonnet
- effort: medium

### Prompt

Add API endpoints for tasks.md conversion and orchestra execution:

1. `POST /api/workspace/tasks-md/convert` - Convert tasks.md to tasks.json
```python
# Request:
{
  "tasks_md_path": "/path/to/repo/tasks.md",
  "tasks_json_path": "/path/to/repo/tasks.json"  # optional, defaults to same name
}

# Response:
{
  "tasks_json_path": "/path/to/repo/tasks.json",
  "task_count": 3,
  "tasks": [
    {"id": "task-1", "name": "Task 1", ...},
    ...
  ]
}
```

2. `POST /api/workspace/orchestra/run` - Run orchestra on tasks.json
```python
# Request:
{
  "tasks_json_path": "/path/to/repo/tasks.json",
  "max_parallel": 5  # optional
}

# Response:
{
  "run_id": "run-20260320-123456",
  "log_dir": "/path/to/logs/run-20260320-123456",
  "task_count": 3
}
```

Implementation:
- For convert: Call orchestra-convert script via subprocess
- For orchestra run: Call orchestra script via subprocess, capture run_id from log dir

---

## Task 3: Backend - Tasks.md Read/Write API

- workdir: /home/jarnura/projects/claude-orchestra
- model: sonnet
- effort: low

### Prompt

Add API endpoints for tasks.md file operations:

1. `GET /api/workspace/tasks-md?path=/path/to/tasks.md` - Read tasks.md content
```python
# Response:
{
  "path": "/path/to/tasks.md",
  "content": "## Task 1\n...",
  "exists": true
}
```

2. `PUT /api/workspace/tasks-md` - Save tasks.md content
```python
# Request:
{
  "path": "/path/to/tasks.md",
  "content": "## Task 1\n..."
}

# Response:
{
  "path": "/path/to/tasks.md",
  "bytes_written": 1234
}
```

These endpoints allow the UI to load and save the tasks.md file.

---

## Task 4: Frontend - Replace Quick Run with Brainstorm Panel

- workdir: /home/jarnura/projects/claude-orchestra
- model: sonnet
- effort: high

### Prompt

Replace the "Quick Run" panel in `viewer/index.html` with a "Brainstorm" panel:

1. Rename "Quick Run" → "Brainstorm"
2. Change the button from "Run" to "Brainstorm"
3. Add a textarea below to show/edit the generated tasks.md
4. Add an "Orchestra" button that:
   - Saves the tasks.md
   - Converts to tasks.json
   - Runs orchestra
   - Shows run_id and links to Runs tab

New UI structure:
```html
<div class="ws-brainstorm">
  <h3>Brainstorm</h3>
  <div class="form-group">
    <textarea id="ws-brainstorm-prompt" placeholder="Describe what you want to build..."></textarea>
  </div>
  <div class="ws-brainstorm-row">
    <select id="ws-brainstorm-model">...</select>
    <button class="btn btn-primary" onclick="wsBrainstorm()">Brainstorm</button>
  </div>
  
  <!-- Generated tasks.md editor -->
  <div id="ws-tasks-md-container" style="display:none">
    <div class="ws-tasks-md-header">
      <h4>tasks.md</h4>
      <span id="ws-task-count"></span>
    </div>
    <textarea id="ws-tasks-md" class="code-editor"></textarea>
    <div class="ws-tasks-md-actions">
      <button class="btn" onclick="wsSaveTasksMd()">Save</button>
      <button class="btn btn-success" onclick="wsRunOrchestra()">Orchestra</button>
    </div>
  </div>
</div>
```

Add JavaScript functions:
- `wsBrainstorm()` - Call brainstorm API, show result in textarea
- `wsSaveTasksMd()` - Save tasks.md content
- `wsRunOrchestra()` - Convert + run orchestra

---

## Task 5: Frontend - Add API Helper Functions

- workdir: /home/jarnura/projects/claude-orchestra
- model: haiku
- effort: low

### Prompt

Add new API helper functions to the `api` object in `viewer/index.html`:

```javascript
// Brainstorm API
api.brainstorm = async (repoPath, prompt, model = 'sonnet') => {
  const res = await fetch(`${API_BASE}/api/workspace/brainstorm`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ repo_path: repoPath, prompt, model })
  });
  if (!res.ok) throw new Error(`Brainstorm failed: ${res.statusText}`);
  return res.json();
};

// Tasks.md operations
api.getTasksMd = async (path) => {
  const res = await fetch(`${API_BASE}/api/workspace/tasks-md?path=${encodeURIComponent(path)}`);
  if (!res.ok) throw new Error(`Failed to read tasks.md: ${res.statusText}`);
  return res.json();
};

api.saveTasksMd = async (path, content) => {
  const res = await fetch(`${API_BASE}/api/workspace/tasks-md`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path, content })
  });
  if (!res.ok) throw new Error(`Failed to save tasks.md: ${res.statusText}`);
  return res.json();
};

// Convert & Orchestra
api.convertTasksMd = async (tasksMdPath, tasksJsonPath) => {
  const res = await fetch(`${API_BASE}/api/workspace/tasks-md/convert`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tasks_md_path: tasksMdPath, tasks_json_path: tasksJsonPath })
  });
  if (!res.ok) throw new Error(`Convert failed: ${res.statusText}`);
  return res.json();
};

api.runOrchestra = async (tasksJsonPath, maxParallel = 5) => {
  const res = await fetch(`${API_BASE}/api/workspace/orchestra/run`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tasks_json_path: tasksJsonPath, max_parallel: maxParallel })
  });
  if (!res.ok) throw new Error(`Orchestra run failed: ${res.statusText}`);
  return res.json();
};
```

---

## Task 6: Frontend - CSS Styling for Brainstorm Panel

- workdir: /home/jarnura/projects/claude-orchestra
- model: haiku
- effort: low

### Prompt

Add CSS styles for the new Brainstorm panel in `viewer/index.html`:

```css
/* Brainstorm panel */
.ws-brainstorm {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 20px;
}

.ws-brainstorm h3 {
  margin: 0 0 12px 0;
  font-size: 1rem;
  color: var(--text);
}

.ws-brainstorm-row {
  display: flex;
  gap: 12px;
  align-items: center;
}

.ws-brainstorm-row select {
  padding: 8px 12px;
  border-radius: 4px;
  border: 1px solid var(--border);
  background: var(--bg);
  color: var(--text);
}

/* Tasks.md editor */
#ws-tasks-md-container {
  margin-top: 16px;
  border-top: 1px solid var(--border);
  padding-top: 16px;
}

.ws-tasks-md-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.ws-tasks-md-header h4 {
  margin: 0;
  font-size: 0.875rem;
  color: var(--text);
}

#ws-tasks-md {
  width: 100%;
  min-height: 200px;
  max-height: 400px;
  font-family: var(--mono);
  font-size: 0.8rem;
  padding: 12px;
  border: 1px solid var(--border);
  border-radius: 4px;
  background: var(--bg);
  color: var(--text);
  resize: vertical;
}

.ws-tasks-md-actions {
  display: flex;
  gap: 8px;
  margin-top: 8px;
}

/* Loading state */
.ws-brainstorm.loading button {
  opacity: 0.6;
  pointer-events: none;
}
```

---

## Task 7: Backend - Load Existing tasks.md

- workdir: /home/jarnura/projects/claude-orchestra
- model: haiku
- effort: low

### Prompt

When loading repo tasks in `_api_workspace_repo_tasks()`, also check for tasks.md file:

```python
def _api_workspace_repo_tasks(self, repo_path):
    # ... existing code ...
    
    # Also check for tasks.md
    tasks_md_path = Path(repo_path) / "tasks.md"
    tasks_md_exists = tasks_md_path.exists()
    tasks_md_content = None
    if tasks_md_exists:
        tasks_md_content = tasks_md_path.read_text()
    
    # Include in response
    self._json({
        "task_files": task_files,
        "tasks_md": {
            "exists": tasks_md_exists,
            "path": str(tasks_md_path),
            "content": tasks_md_content
        }
    })
```

This allows the UI to load existing tasks.md when selecting a repo.

---

## Execution Order

1. Task 1 (Backend - Brainstorm API)
2. Task 3 (Backend - Tasks.md Read/Write)
3. Task 7 (Backend - Load existing tasks.md)
4. Task 2 (Backend - Convert & Orchestra)
5. Task 5 (Frontend - API helpers)
6. Task 4 (Frontend - Brainstorm Panel)
7. Task 6 (Frontend - CSS)

---

## Notes

- The brainstorm endpoint uses Claude CLI directly, not orchestra-spawn
- The tasks.md format is compatible with orchestra-convert (see CLAUDE.md)
- Orchestra button should show a confirmation with task count before running
- After orchestra starts, redirect user to Runs tab with the new run highlighted
