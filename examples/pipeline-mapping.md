# Pipeline Mapping Walkthrough

This example demonstrates how to use pipeline mapping to control task-to-stage assignment and execute tasks in batches via the REST API.

## Scenario

You have a feature development pipeline with 3 stages (Plan → Implement → Review) and 3 tasks:
- **plan-task**: Plan the feature architecture
- **impl-task**: Implement the feature code
- **review-task**: Review and test the implementation

Instead of running all tasks at once, you want to:
1. Execute the Plan task and review output before proceeding
2. Execute the Implement task
3. Execute the Review task

## Step 1: Start Orchestra Serve

First, start the orchestra-serve API server:

```bash
orchestra-serve --port 8080 --log-dir /tmp/orchestra-logs &
```

This launches the REST API that manages pipeline sessions and batches.

## Step 2: Create Base Pipeline

Create a pipeline JSON with the 3 stages:

```bash
cat > pipeline-feature.json <<'EOF'
{
  "name": "Feature Development",
  "stages": [
    {
      "name": "Plan",
      "tasks": [
        {"file": "tasks-plan.json", "max_parallel": 1}
      ],
      "pass_outputs_to_next": true
    },
    {
      "name": "Implement",
      "tasks": [
        {"file": "tasks-impl.json", "max_parallel": 2}
      ],
      "pass_outputs_to_next": true
    },
    {
      "name": "Review",
      "tasks": [
        {"file": "tasks-review.json", "max_parallel": 1}
      ],
      "pass_outputs_to_next": false
    }
  ],
  "aggregate": true
}
EOF
```

## Step 3: Create Mapping Session

Initialize a pipeline mapping session:

```bash
curl -X POST http://localhost:8080/api/pipeline-mapping/create \
  -H "Content-Type: application/json" \
  -d '{
    "pipeline_file": "pipeline-feature.json",
    "name": "Feature: User Authentication"
  }' \
  | jq .
```

Response:
```json
{
  "session_id": "feature-user-authentication-abc123",
  "status": "created",
  "pipeline_name": "Feature Development",
  "stages": [
    {"name": "Plan", "stage_index": 0},
    {"name": "Implement", "stage_index": 1},
    {"name": "Review", "stage_index": 2}
  ],
  "mappings": []
}
```

Save the `session_id` for subsequent API calls.

## Step 4: Assign Tasks to Stages

Assign the 3 tasks to their respective stages:

### Assign Plan Task

```bash
curl -X PUT http://localhost:8080/api/pipeline-mapping/feature-user-authentication-abc123/assign \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "plan-task",
    "task_name": "Plan Architecture",
    "stage_name": "Plan",
    "batch": 1
  }' \
  | jq .
```

### Assign Implement Task

```bash
curl -X PUT http://localhost:8080/api/pipeline-mapping/feature-user-authentication-abc123/assign \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "impl-task",
    "task_name": "Implement Feature",
    "stage_name": "Implement",
    "batch": 2
  }' \
  | jq .
```

### Assign Review Task

```bash
curl -X PUT http://localhost:8080/api/pipeline-mapping/feature-user-authentication-abc123/assign \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "review-task",
    "task_name": "Review & Test",
    "stage_name": "Review",
    "batch": 3
  }' \
  | jq .
```

After all assignments, get the full mapping state:

```bash
curl http://localhost:8080/api/pipeline-mapping/feature-user-authentication-abc123 | jq .
```

Response:
```json
{
  "session_id": "feature-user-authentication-abc123",
  "status": "mapped",
  "pipeline_name": "Feature Development",
  "mappings": [
    {
      "task_id": "plan-task",
      "task_name": "Plan Architecture",
      "stage_name": "Plan",
      "batch": 1
    },
    {
      "task_id": "impl-task",
      "task_name": "Implement Feature",
      "stage_name": "Implement",
      "batch": 2
    },
    {
      "task_id": "review-task",
      "task_name": "Review & Test",
      "stage_name": "Review",
      "batch": 3
    }
  ]
}
```

## Step 5: Execute Batch 1 (Plan)

Execute only the Plan task:

```bash
curl -X POST http://localhost:8080/api/pipeline-mapping/feature-user-authentication-abc123/execute \
  -H "Content-Type: application/json" \
  -d '{
    "batch": 1,
    "poll": true
  }' \
  | jq .
```

This internally calls:
```bash
orchestra-pipeline pipeline-feature.json --filter-tasks "plan-task"
```

Monitor progress:
```bash
watch -n 2 'curl http://localhost:8080/api/pipeline-mapping/feature-user-authentication-abc123/status | jq .'
```

Expected output after Plan completes:
```json
{
  "session_id": "feature-user-authentication-abc123",
  "batch_results": {
    "1": {
      "status": "done",
      "tasks_done": 1,
      "tasks_failed": 0,
      "log_dir": "/tmp/orchestra-logs/feature-plan"
    }
  }
}
```

### Review Plan Output

Before proceeding, review the Plan task output:

```bash
cat /tmp/orchestra-logs/feature-plan/plan-task.output.md
```

If satisfied with the plan, proceed to Batch 2. Otherwise, modify the task and re-execute Batch 1.

## Step 6: Execute Batch 2 (Implement)

Once the plan is approved, execute the Implement task:

```bash
curl -X POST http://localhost:8080/api/pipeline-mapping/feature-user-authentication-abc123/execute \
  -H "Content-Type: application/json" \
  -d '{
    "batch": 2,
    "poll": true
  }' \
  | jq .
```

This injects prior outputs from the Plan stage and runs:
```bash
orchestra-pipeline pipeline-feature.json --filter-tasks "impl-task"
```

The Plan stage output is automatically appended as context to the Implement task prompt.

Monitor until complete:
```bash
tail -f /tmp/orchestra-logs/feature-impl/impl-task.output.md
```

## Step 7: Execute Batch 3 (Review)

After implementation, run the Review task:

```bash
curl -X POST http://localhost:8080/api/pipeline-mapping/feature-user-authentication-abc123/execute \
  -H "Content-Type: application/json" \
  -d '{
    "batch": 3,
    "poll": true
  }' \
  | jq .
```

This runs:
```bash
orchestra-pipeline pipeline-feature.json --filter-tasks "review-task"
```

With context from both Plan and Implement stages available to the Review task.

## Step 8: View Final Report

Once all batches complete, view the aggregate report:

```bash
cat /tmp/orchestra-logs/feature-user-authentication-abc123/report.md
```

Or retrieve via API:

```bash
curl http://localhost:8080/api/pipeline-mapping/feature-user-authentication-abc123/report | jq .
```

## Command-Line Equivalent (Without API)

If you prefer not to use the API, you can run batches directly from the CLI:

```bash
# Execute only plan-task
orchestra-pipeline pipeline-feature.json --filter-tasks "plan-task"

# Review output...

# Execute only impl-task (plan outputs are auto-injected if pass_outputs_to_next: true)
orchestra-pipeline pipeline-feature.json --filter-tasks "impl-task"

# Execute only review-task
orchestra-pipeline pipeline-feature.json --filter-tasks "review-task"
```

## Key Features

| Feature | Benefit |
|---------|---------|
| **Task Filtering** | Execute subset of pipeline in controlled batches |
| **Output Injection** | Later stages receive prior stage outputs as context |
| **Session State** | API tracks all batches and mappings for audit trail |
| **Polling** | Monitor progress via API without CLI polling |
| **Batch Grouping** | Logical grouping of related tasks across stages |

## Advanced: Multiple Sessions

Run multiple feature pipelines in parallel with different mappings:

```bash
# Session 1: Feature A
curl -X POST http://localhost:8080/api/pipeline-mapping/create \
  -d '{"pipeline_file": "pipeline-feature.json", "name": "Feature: Auth"}' | jq -r .session_id

# Session 2: Feature B
curl -X POST http://localhost:8080/api/pipeline-mapping/create \
  -d '{"pipeline_file": "pipeline-feature.json", "name": "Feature: API"}' | jq -r .session_id

# Execute each session independently
orchestra-pipeline pipeline-feature.json --filter-tasks "auth-plan"  # Session 1 Batch 1
orchestra-pipeline pipeline-feature.json --filter-tasks "api-plan"   # Session 2 Batch 1
```
