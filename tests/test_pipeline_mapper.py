"""Tests for Pipeline Mapper: server-side API helpers and UI integration.

Covers:
- _save_mapping / _load_mapping round-trip
- MAPPING_ID_RE validation
- mapperState / mapperRenderMappingArea / mapperRenderBatchBar (via DOM test)
- Drag-and-drop event handler wiring
- Batch selection and execute flow
- Tab integration in viewer
"""

import importlib.util
import importlib.machinery
import json
import os
import re
import textwrap
import threading
import uuid
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Module import — skip entire file if it fails
# ---------------------------------------------------------------------------

_SERVE_PATH = Path(__file__).resolve().parents[1] / "bin" / "orchestra-serve"
_VIEWER_PATH = Path(__file__).resolve().parents[1] / "viewer" / "index.html"

_module = None
_IMPORT_ERROR: str | None = None

try:
    loader = importlib.machinery.SourceFileLoader("orchestra_serve", str(_SERVE_PATH))
    spec = importlib.util.spec_from_loader("orchestra_serve", loader)
    _module = importlib.util.module_from_spec(spec)
    loader.exec_module(_module)
except Exception as exc:
    _IMPORT_ERROR = str(exc)

pytestmark = pytest.mark.skipif(
    _module is None,
    reason=f"Could not import orchestra-serve: {_IMPORT_ERROR}",
)


def _serve():
    assert _module is not None
    return _module


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def mappings_dir(tmp_path, monkeypatch):
    """Override ORCHESTRA_DIR so _mappings_dir() uses a temp directory."""
    monkeypatch.setattr(_serve(), "ORCHESTRA_DIR", tmp_path)
    return tmp_path / "data" / "mappings"


@pytest.fixture
def sample_mapping():
    """Return a valid mapping state dict."""
    return {
        "mapping_id": str(uuid.uuid4()),
        "tasks_file": "/tmp/tasks.json",
        "pipeline_template": "feature",
        "assignments": {},
        "batches": [],
    }


@pytest.fixture
def viewer_html():
    """Load viewer/index.html content."""
    return _VIEWER_PATH.read_text()


# ---------------------------------------------------------------------------
# 1. MAPPING_ID_RE validation
# ---------------------------------------------------------------------------

class TestMappingIdRegex:
    @pytest.mark.parametrize("valid_id", [
        "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "00000000-0000-0000-0000-000000000000",
        "abcdef12-3456-7890-abcd-ef1234567890",
    ])
    def test_valid_mapping_ids(self, valid_id):
        assert _serve().MAPPING_ID_RE.match(valid_id), f"{valid_id} should match"

    @pytest.mark.parametrize("invalid_id", [
        "",
        "not-a-uuid",
        "a1b2c3d4-e5f6-7890-abcd",
        "../traversal",
        "a1b2c3d4-e5f6-7890-abcd-ef1234567890-extra",
        "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",  # uppercase not allowed
        "a1b2c3d4_e5f6_7890_abcd_ef1234567890",  # underscores not dashes
    ])
    def test_invalid_mapping_ids(self, invalid_id):
        assert not _serve().MAPPING_ID_RE.match(invalid_id), f"{invalid_id} should NOT match"


# ---------------------------------------------------------------------------
# 2. _save_mapping / _load_mapping round-trip
# ---------------------------------------------------------------------------

class TestMappingPersistence:
    def test_save_and_load_roundtrip(self, mappings_dir, sample_mapping):
        mid = sample_mapping["mapping_id"]
        _serve()._save_mapping(mid, sample_mapping)

        loaded, err = _serve()._load_mapping(mid)
        assert err is None
        assert loaded is not None
        assert loaded["mapping_id"] == mid
        assert loaded["tasks_file"] == sample_mapping["tasks_file"]
        assert loaded["pipeline_template"] == "feature"
        assert loaded["assignments"] == {}
        assert loaded["batches"] == []

    def test_load_nonexistent_returns_error(self, mappings_dir):
        loaded, err = _serve()._load_mapping("00000000-0000-0000-0000-000000000000")
        assert loaded is None
        assert err == "Mapping not found"

    def test_load_corrupt_returns_error(self, mappings_dir):
        mid = str(uuid.uuid4())
        mapping_file = mappings_dir / f"{mid}.json"
        mappings_dir.mkdir(parents=True, exist_ok=True)
        mapping_file.write_text("not valid json {{{")

        loaded, err = _serve()._load_mapping(mid)
        assert loaded is None
        assert "Corrupt" in err

    def test_save_creates_parent_directories(self, mappings_dir, sample_mapping):
        """_save_mapping should create data/mappings/ if it doesn't exist."""
        assert not mappings_dir.exists()
        mid = sample_mapping["mapping_id"]
        _serve()._save_mapping(mid, sample_mapping)
        assert mappings_dir.exists()
        assert (mappings_dir / f"{mid}.json").exists()

    def test_save_with_assignments(self, mappings_dir, sample_mapping):
        mid = sample_mapping["mapping_id"]
        sample_mapping["assignments"] = {"task-1": 0, "task-2": 1, "task-3": 0}
        _serve()._save_mapping(mid, sample_mapping)

        loaded, err = _serve()._load_mapping(mid)
        assert err is None
        assert loaded["assignments"] == {"task-1": 0, "task-2": 1, "task-3": 0}

    def test_save_overwrites_existing(self, mappings_dir, sample_mapping):
        mid = sample_mapping["mapping_id"]
        _serve()._save_mapping(mid, sample_mapping)

        sample_mapping["assignments"] = {"task-1": 2}
        _serve()._save_mapping(mid, sample_mapping)

        loaded, err = _serve()._load_mapping(mid)
        assert err is None
        assert loaded["assignments"] == {"task-1": 2}

    def test_save_with_batch_history(self, mappings_dir, sample_mapping):
        mid = sample_mapping["mapping_id"]
        sample_mapping["batches"] = [
            {"batch_id": "b1", "task_ids": ["t1", "t2"], "status": "completed"},
            {"batch_id": "b2", "task_ids": ["t3"], "status": "running"},
        ]
        _serve()._save_mapping(mid, sample_mapping)

        loaded, err = _serve()._load_mapping(mid)
        assert err is None
        assert len(loaded["batches"]) == 2
        assert loaded["batches"][0]["status"] == "completed"
        assert loaded["batches"][1]["status"] == "running"


# ---------------------------------------------------------------------------
# 3. VALID_PIPELINE_TEMPLATES
# ---------------------------------------------------------------------------

class TestPipelineTemplates:
    def test_expected_templates(self):
        templates = _serve().VALID_PIPELINE_TEMPLATES
        assert "feature" in templates
        assert "bugfix" in templates
        assert "audit" in templates
        assert "refactor" in templates
        assert "release" in templates

    def test_invalid_template_rejected(self):
        templates = _serve().VALID_PIPELINE_TEMPLATES
        assert "nonexistent" not in templates
        assert "" not in templates


# ---------------------------------------------------------------------------
# 4. Viewer HTML — Tab integration
# ---------------------------------------------------------------------------

class TestViewerMapperTab:
    def test_mapper_tab_in_tab_bar(self, viewer_html):
        """The Mapper tab link should be in the tab bar."""
        assert '<a href="#/mapper">Pipeline Mapper</a>' in viewer_html

    def test_mapper_tab_active_highlighting(self, viewer_html):
        """The route function should set Mapper tab active on #/mapper."""
        assert "href === '#/mapper' && hash.startsWith('#/mapper')" in viewer_html

    def test_mapper_route_exists(self, viewer_html):
        """The router should handle #/mapper."""
        assert "hash === '#/mapper'" in viewer_html
        assert "renderMapperScreen()" in viewer_html


# ---------------------------------------------------------------------------
# 5. Viewer HTML — Mapper CSS
# ---------------------------------------------------------------------------

class TestViewerMapperCSS:
    def test_mapper_setup_class(self, viewer_html):
        assert ".mapper-setup " in viewer_html or ".mapper-setup{" in viewer_html

    def test_mapper_columns_class(self, viewer_html):
        assert ".mapper-columns" in viewer_html

    def test_mapper_task_class(self, viewer_html):
        assert ".mapper-task " in viewer_html or ".mapper-task{" in viewer_html

    def test_mapper_drop_zone_class(self, viewer_html):
        assert ".mapper-drop-zone " in viewer_html or ".mapper-drop-zone{" in viewer_html

    def test_mapper_drop_zone_drag_over(self, viewer_html):
        """Drop zone should have a drag-over visual highlight class."""
        assert ".mapper-drop-zone.drag-over" in viewer_html

    def test_mapper_batch_bar_class(self, viewer_html):
        assert ".mapper-batch-bar" in viewer_html

    def test_mapper_history_class(self, viewer_html):
        assert ".mapper-history " in viewer_html or ".mapper-history{" in viewer_html

    def test_mapper_task_dragging_class(self, viewer_html):
        """Dragging tasks should have a visual indicator."""
        assert ".mapper-task.dragging" in viewer_html

    def test_mapper_task_mapped_ghost_class(self, viewer_html):
        """Mapped tasks in left column should be grayed out."""
        assert ".mapper-task.mapped-ghost" in viewer_html

    def test_mapper_task_executed_class(self, viewer_html):
        """Executed tasks should have green left border."""
        assert ".mapper-task.executed" in viewer_html

    def test_mapper_responsive_layout(self, viewer_html):
        """Mapper columns should collapse on small screens."""
        assert "768px" in viewer_html
        assert "mapper-columns" in viewer_html


# ---------------------------------------------------------------------------
# 6. Viewer HTML — Mapper JavaScript functions exist
# ---------------------------------------------------------------------------

class TestViewerMapperJS:
    def test_render_mapper_screen_function(self, viewer_html):
        assert "async function renderMapperScreen()" in viewer_html

    def test_mapper_state_object(self, viewer_html):
        assert "const mapperState = {" in viewer_html

    def test_mapper_state_has_required_fields(self, viewer_html):
        for field in ["repos", "selectedRepo", "taskFiles", "selectedTasksFile",
                       "pipelineTemplates", "selectedTemplate", "mappingId",
                       "tasks", "stages", "assignments", "executedTasks",
                       "selectedBatch", "history", "selectAllMapped"]:
            assert field in viewer_html, f"mapperState should have '{field}' field"

    def test_mapper_select_repo_function(self, viewer_html):
        assert "async function mapperSelectRepo(" in viewer_html

    def test_mapper_select_tasks_file_function(self, viewer_html):
        assert "function mapperSelectTasksFile(" in viewer_html

    def test_mapper_create_mapping_function(self, viewer_html):
        assert "async function mapperCreateMapping()" in viewer_html

    def test_mapper_render_mapping_area(self, viewer_html):
        assert "function mapperRenderMappingArea()" in viewer_html

    def test_mapper_render_batch_bar(self, viewer_html):
        assert "function mapperRenderBatchBar()" in viewer_html

    def test_mapper_render_history(self, viewer_html):
        assert "function mapperRenderHistory()" in viewer_html


# ---------------------------------------------------------------------------
# 7. Viewer HTML — Drag and Drop implementation
# ---------------------------------------------------------------------------

class TestViewerDragDrop:
    def test_attach_drag_drop_function(self, viewer_html):
        assert "function mapperAttachDragDrop()" in viewer_html

    def test_drag_start_handler(self, viewer_html):
        assert "function mapperDragStart(e)" in viewer_html

    def test_drag_end_handler(self, viewer_html):
        assert "function mapperDragEnd(e)" in viewer_html

    def test_drag_over_handler(self, viewer_html):
        assert "function mapperDragOver(e)" in viewer_html

    def test_drag_leave_handler(self, viewer_html):
        assert "function mapperDragLeave(e)" in viewer_html

    def test_drop_handler(self, viewer_html):
        assert "async function mapperDrop(e)" in viewer_html

    def test_drag_start_sets_data_transfer(self, viewer_html):
        """dragstart should set dataTransfer with task_id."""
        assert "e.dataTransfer.setData(" in viewer_html

    def test_drag_start_sets_effect(self, viewer_html):
        assert "e.dataTransfer.effectAllowed" in viewer_html

    def test_drag_start_adds_dragging_class(self, viewer_html):
        assert "classList.add('dragging')" in viewer_html

    def test_drag_end_removes_dragging_class(self, viewer_html):
        assert "classList.remove('dragging')" in viewer_html

    def test_drag_over_prevents_default(self, viewer_html):
        """dragover handler must preventDefault to allow drop."""
        # The function body includes e.preventDefault()
        assert "mapperDragOver" in viewer_html
        # Check for preventDefault in the general context
        assert "e.preventDefault();" in viewer_html

    def test_drag_over_adds_drag_over_class(self, viewer_html):
        assert "classList.add('drag-over')" in viewer_html

    def test_drag_leave_removes_drag_over_class(self, viewer_html):
        assert "classList.remove('drag-over')" in viewer_html

    def test_drop_reads_data_transfer(self, viewer_html):
        assert "e.dataTransfer.getData(" in viewer_html

    def test_drop_reads_stage_index(self, viewer_html):
        assert "dataset.stageIndex" in viewer_html

    def test_drop_calls_assign_api(self, viewer_html):
        assert "api.assignTask(mapperState.mappingId, taskId, stageIndex)" in viewer_html

    def test_drop_updates_assignments(self, viewer_html):
        assert "mapperState.assignments[taskId] = stageIndex" in viewer_html

    def test_available_tasks_have_draggable_attribute(self, viewer_html):
        """Available (unmapped) tasks should get draggable='true'."""
        assert 'draggable="true"' in viewer_html

    def test_draggable_attached_to_available_tasks(self, viewer_html):
        """Drag listeners should be attached to tasks in the available column."""
        assert "mapper-available-tasks" in viewer_html
        assert "addEventListener('dragstart'" in viewer_html
        assert "addEventListener('dragend'" in viewer_html

    def test_drop_zones_have_event_listeners(self, viewer_html):
        """Drop zones should have dragover, dragleave, drop listeners."""
        assert "addEventListener('dragover'" in viewer_html
        assert "addEventListener('dragleave'" in viewer_html
        assert "addEventListener('drop'" in viewer_html


# ---------------------------------------------------------------------------
# 8. Viewer HTML — Batch selection and execution
# ---------------------------------------------------------------------------

class TestViewerBatchControls:
    def test_toggle_batch_task_function(self, viewer_html):
        assert "function mapperToggleBatchTask(taskId, checked)" in viewer_html

    def test_toggle_adds_to_selected(self, viewer_html):
        assert "mapperState.selectedBatch.add(taskId)" in viewer_html

    def test_toggle_removes_from_selected(self, viewer_html):
        assert "mapperState.selectedBatch.delete(taskId)" in viewer_html

    def test_select_all_mapped_function(self, viewer_html):
        assert "function mapperSelectAllMapped()" in viewer_html

    def test_select_all_mapped_toggle(self, viewer_html):
        """Clicking Select All again should deselect all."""
        assert "mapperState.selectAllMapped = !mapperState.selectAllMapped" in viewer_html

    def test_execute_batch_function(self, viewer_html):
        assert "async function mapperExecuteBatch()" in viewer_html

    def test_execute_calls_api(self, viewer_html):
        assert "api.executeMapping(mapperState.mappingId, taskIds)" in viewer_html

    def test_execute_marks_tasks_executed(self, viewer_html):
        assert "mapperState.executedTasks.add(id)" in viewer_html

    def test_execute_clears_selection(self, viewer_html):
        assert "mapperState.selectedBatch.clear()" in viewer_html

    def test_execute_button_disabled_when_no_selection(self, viewer_html):
        """Execute Batch button should be disabled when nothing selected."""
        assert "selectedCount === 0 ? 'disabled" in viewer_html

    def test_batch_bar_shows_count(self, viewer_html):
        """Batch bar should show count of selected tasks."""
        assert "tasks selected for this batch" in viewer_html

    def test_clear_mapping_function(self, viewer_html):
        assert "async function mapperClearMapping()" in viewer_html

    def test_clear_calls_unassign_for_all(self, viewer_html):
        """Clear mapping should call unassign for each task."""
        assert "api.unassignTask(mapperState.mappingId, taskId)" in viewer_html


# ---------------------------------------------------------------------------
# 9. Viewer HTML — Unassign (x button)
# ---------------------------------------------------------------------------

class TestViewerUnassign:
    def test_unassign_function(self, viewer_html):
        assert "async function mapperUnassignTask(taskId)" in viewer_html

    def test_unassign_calls_api(self, viewer_html):
        assert "api.unassignTask(mapperState.mappingId, taskId)" in viewer_html

    def test_unassign_removes_from_assignments(self, viewer_html):
        assert "delete mapperState.assignments[taskId]" in viewer_html

    def test_unassign_button_in_stage_tasks(self, viewer_html):
        """Tasks in stages should have an x button to unassign."""
        assert "mapper-task-remove" in viewer_html
        assert "&times;" in viewer_html


# ---------------------------------------------------------------------------
# 10. Viewer HTML — SSE integration
# ---------------------------------------------------------------------------

class TestViewerMapperSSE:
    def test_connect_sse_function(self, viewer_html):
        assert "function mapperConnectSSE()" in viewer_html

    def test_listens_for_batch_started(self, viewer_html):
        assert "addEventListener('batch_started'" in viewer_html

    def test_listens_for_batch_completed(self, viewer_html):
        assert "addEventListener('batch_completed'" in viewer_html

    def test_sse_filters_by_mapping_id(self, viewer_html):
        assert "data.mapping_id !== mapperState.mappingId" in viewer_html

    def test_sse_cleanup_on_navigate(self, viewer_html):
        """SSE connection should close when leaving mapper."""
        assert "mapperEventSource.close()" in viewer_html

    def test_sse_reconnect_on_error(self, viewer_html):
        """SSE should close on error (cleanup)."""
        assert "mapperEventSource.onerror" in viewer_html


# ---------------------------------------------------------------------------
# 11. Viewer HTML — Batch History Panel
# ---------------------------------------------------------------------------

class TestViewerBatchHistory:
    def test_load_history_function(self, viewer_html):
        assert "async function mapperLoadHistory()" in viewer_html

    def test_load_history_calls_api(self, viewer_html):
        assert "api.getMappingHistory(mapperState.mappingId)" in viewer_html

    def test_history_has_status_badges(self, viewer_html):
        """History items should show status badges."""
        assert "badge-done" in viewer_html
        assert "badge-running" in viewer_html
        assert "badge-failed" in viewer_html

    def test_history_has_run_links(self, viewer_html):
        """History items should link to run detail view."""
        assert 'href="#/run/' in viewer_html

    def test_history_is_collapsible(self, viewer_html):
        assert "mapper-history" in viewer_html
        assert "<details" in viewer_html
        assert "Batch History" in viewer_html

    def test_history_marks_executed_tasks(self, viewer_html):
        """Completed batch tasks should be marked as executed."""
        assert "executedTasks.add(id)" in viewer_html


# ---------------------------------------------------------------------------
# 12. Viewer HTML — Setup Panel
# ---------------------------------------------------------------------------

class TestViewerSetupPanel:
    def test_setup_has_repo_dropdown(self, viewer_html):
        assert 'id="mapper-repo"' in viewer_html

    def test_setup_has_tasks_file_dropdown(self, viewer_html):
        assert 'id="mapper-tasks-file"' in viewer_html

    def test_setup_has_template_dropdown(self, viewer_html):
        assert 'id="mapper-template"' in viewer_html

    def test_setup_has_create_button(self, viewer_html):
        assert "mapperCreateMapping()" in viewer_html
        assert "Create Mapping" in viewer_html

    def test_create_button_disabled_without_selections(self, viewer_html):
        """Create button should be disabled when file or template not selected."""
        assert "mapperState.selectedTaskFiles.length === 0" in viewer_html

    def test_tasks_file_disabled_without_repo(self, viewer_html):
        """Tasks file dropdown disabled when no task files loaded."""
        assert "availableTaskFiles.length === 0" in viewer_html


# ---------------------------------------------------------------------------
# 13. Viewer HTML — Mapping Area (two-column layout)
# ---------------------------------------------------------------------------

class TestViewerMappingArea:
    def test_available_tasks_column(self, viewer_html):
        assert "Available Tasks" in viewer_html
        assert "mapper-col" in viewer_html

    def test_pipeline_stages_column(self, viewer_html):
        assert "Pipeline Stages" in viewer_html

    def test_unmapped_count_shown(self, viewer_html):
        assert "unmapped" in viewer_html

    def test_mapped_count_shown(self, viewer_html):
        assert "mapped" in viewer_html

    def test_task_cards_show_name(self, viewer_html):
        assert "mapper-task-name" in viewer_html

    def test_task_cards_show_model_badge(self, viewer_html):
        assert "modelBadge(task.model)" in viewer_html or "modelBadge(t.model)" in viewer_html

    def test_task_cards_show_agent_tags(self, viewer_html):
        """Available tasks should show agent tags."""
        assert "task.agents" in viewer_html

    def test_mapped_badge_on_left_column(self, viewer_html):
        """Mapped tasks in left column get a 'mapped' badge."""
        assert ">mapped</span>" in viewer_html

    def test_executed_badge_on_left_column(self, viewer_html):
        """Executed tasks in left column get an 'executed' badge."""
        assert "executed</span>" in viewer_html

    def test_drop_zones_have_data_stage_index(self, viewer_html):
        assert "data-stage-index" in viewer_html

    def test_empty_drop_zone_placeholder(self, viewer_html):
        assert "Drop tasks here" in viewer_html

    def test_stage_header_shows_number(self, viewer_html):
        assert "Stage ${i + 1}" in viewer_html

    def test_stage_header_shows_task_count(self, viewer_html):
        assert "stageTasks.length" in viewer_html

    def test_checkboxes_on_staged_tasks(self, viewer_html):
        """Tasks in stages should have checkboxes for batch selection."""
        assert 'type="checkbox"' in viewer_html
        assert "mapperToggleBatchTask" in viewer_html


# ---------------------------------------------------------------------------
# 14. API client — all mapping endpoints defined
# ---------------------------------------------------------------------------

class TestViewerMapperAPI:
    def test_create_mapping_api(self, viewer_html):
        assert "/api/pipeline-mapping/create" in viewer_html

    def test_assign_task_api(self, viewer_html):
        assert "/assign" in viewer_html
        assert "method: 'PUT'" in viewer_html

    def test_unassign_task_api(self, viewer_html):
        assert "method: 'DELETE'" in viewer_html

    def test_execute_mapping_api(self, viewer_html):
        assert "/execute" in viewer_html

    def test_get_mapping_history_api(self, viewer_html):
        assert "/history" in viewer_html

    def test_api_uses_mapping_id(self, viewer_html):
        assert "encodeURIComponent(mappingId)" in viewer_html


# ---------------------------------------------------------------------------
# 15. DOM refresh without full re-render
# ---------------------------------------------------------------------------

class TestViewerRefreshDOM:
    def test_refresh_dom_function(self, viewer_html):
        assert "function mapperRefreshDOM()" in viewer_html

    def test_refresh_updates_columns(self, viewer_html):
        """mapperRefreshDOM should surgically update columns."""
        assert "querySelector('.mapper-columns')" in viewer_html

    def test_refresh_updates_batch_bar(self, viewer_html):
        assert "querySelector('.mapper-batch-bar')" in viewer_html

    def test_refresh_updates_history(self, viewer_html):
        assert "querySelector('.mapper-history')" in viewer_html

    def test_refresh_reattaches_drag_drop(self, viewer_html):
        """After DOM refresh, drag-drop listeners must be reattached."""
        # mapperRefreshDOM calls mapperAttachDragDrop at the end
        assert "mapperAttachDragDrop()" in viewer_html

    def test_toggle_batch_task_updates_bar_only(self, viewer_html):
        """Toggling a batch checkbox should update batch bar without full re-render."""
        # mapperToggleBatchTask does a targeted batch bar update
        assert "batchBar.replaceWith(newBar.firstElementChild)" in viewer_html


# ---------------------------------------------------------------------------
# 16. End-to-end data flow tests (assignment round-trip)
# ---------------------------------------------------------------------------

class TestE2EAssignmentFlow:
    """Verify the complete assign/unassign/batch-execute data flow using
    _save_mapping / _load_mapping to simulate API calls."""

    def test_full_assign_unassign_cycle(self, mappings_dir, sample_mapping):
        """Simulate: create mapping → assign 3 tasks → unassign 1 → verify state."""
        mid = sample_mapping["mapping_id"]
        _serve()._save_mapping(mid, sample_mapping)

        # Assign 3 tasks to different stages
        loaded, _ = _serve()._load_mapping(mid)
        loaded["assignments"]["task-plan"] = 0
        loaded["assignments"]["task-impl"] = 1
        loaded["assignments"]["task-review"] = 2
        _serve()._save_mapping(mid, loaded)

        # Verify 3 assignments persisted
        loaded, _ = _serve()._load_mapping(mid)
        assert len(loaded["assignments"]) == 3
        assert loaded["assignments"]["task-plan"] == 0
        assert loaded["assignments"]["task-impl"] == 1
        assert loaded["assignments"]["task-review"] == 2

        # Unassign task-impl
        del loaded["assignments"]["task-impl"]
        _serve()._save_mapping(mid, loaded)

        loaded, _ = _serve()._load_mapping(mid)
        assert len(loaded["assignments"]) == 2
        assert "task-impl" not in loaded["assignments"]
        assert loaded["assignments"]["task-plan"] == 0

    def test_reassign_after_unassign(self, mappings_dir, sample_mapping):
        """Task unassigned from stage 0 should be reassignable to stage 2."""
        mid = sample_mapping["mapping_id"]
        sample_mapping["assignments"]["task-1"] = 0
        _serve()._save_mapping(mid, sample_mapping)

        # Unassign from stage 0
        loaded, _ = _serve()._load_mapping(mid)
        del loaded["assignments"]["task-1"]
        _serve()._save_mapping(mid, loaded)

        # Reassign to stage 2
        loaded, _ = _serve()._load_mapping(mid)
        loaded["assignments"]["task-1"] = 2
        _serve()._save_mapping(mid, loaded)

        loaded, _ = _serve()._load_mapping(mid)
        assert loaded["assignments"]["task-1"] == 2

    def test_batch_execution_records_history(self, mappings_dir, sample_mapping):
        """Batch execution should create a batch entry in history."""
        mid = sample_mapping["mapping_id"]
        sample_mapping["assignments"] = {"task-a": 0, "task-b": 0, "task-c": 1}
        _serve()._save_mapping(mid, sample_mapping)

        # Simulate batch 1: execute tasks a and b
        loaded, _ = _serve()._load_mapping(mid)
        loaded["batches"].append({
            "run_id": "2026-03-27_20-00-00-batch1",
            "pipeline_id": f"mapping-{mid}-batch1",
            "task_ids": ["task-a", "task-b"],
            "status": "running",
            "started_at": "2026-03-27T20:00:00+00:00",
        })
        _serve()._save_mapping(mid, loaded)

        # Verify batch recorded
        loaded, _ = _serve()._load_mapping(mid)
        assert len(loaded["batches"]) == 1
        assert loaded["batches"][0]["task_ids"] == ["task-a", "task-b"]
        assert loaded["batches"][0]["status"] == "running"

        # Simulate batch completion
        loaded["batches"][0]["status"] = "completed"
        loaded["batches"][0]["exit_code"] = 0
        loaded["batches"][0]["completed_at"] = "2026-03-27T20:05:00+00:00"
        _serve()._save_mapping(mid, loaded)

        loaded, _ = _serve()._load_mapping(mid)
        assert loaded["batches"][0]["status"] == "completed"
        assert loaded["batches"][0]["exit_code"] == 0

    def test_multiple_batches(self, mappings_dir, sample_mapping):
        """Multiple batch executions accumulate in history."""
        mid = sample_mapping["mapping_id"]
        sample_mapping["assignments"] = {"t1": 0, "t2": 0, "t3": 1, "t4": 1}
        sample_mapping["batches"] = [
            {"run_id": "run-1", "task_ids": ["t1", "t2"], "status": "completed"},
        ]
        _serve()._save_mapping(mid, sample_mapping)

        # Execute batch 2
        loaded, _ = _serve()._load_mapping(mid)
        loaded["batches"].append({
            "run_id": "run-2", "task_ids": ["t3", "t4"], "status": "completed",
        })
        _serve()._save_mapping(mid, loaded)

        loaded, _ = _serve()._load_mapping(mid)
        assert len(loaded["batches"]) == 2
        assert loaded["batches"][0]["task_ids"] == ["t1", "t2"]
        assert loaded["batches"][1]["task_ids"] == ["t3", "t4"]

    def test_concurrent_save_load_safety(self, mappings_dir, sample_mapping):
        """Rapid save/load should not corrupt data (basic thread safety check)."""
        mid = sample_mapping["mapping_id"]
        _serve()._save_mapping(mid, sample_mapping)

        errors = []

        def worker(task_id, stage_idx):
            try:
                loaded, err = _serve()._load_mapping(mid)
                if err:
                    errors.append(err)
                    return
                loaded["assignments"][task_id] = stage_idx
                _serve()._save_mapping(mid, loaded)
            except Exception as e:
                errors.append(str(e))

        threads = [threading.Thread(target=worker, args=(f"task-{i}", i % 3)) for i in range(10)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert not errors, f"Thread errors: {errors}"

        # At least some assignments should have persisted
        loaded, _ = _serve()._load_mapping(mid)
        assert len(loaded["assignments"]) > 0


# ---------------------------------------------------------------------------
# 17. Bug fix verifications
# ---------------------------------------------------------------------------

class TestBugFixes:
    def test_dragleave_handles_null_related_target(self, viewer_html):
        """mapperDragLeave should handle null relatedTarget (drag outside window)."""
        assert "!e.relatedTarget || !e.currentTarget.contains(e.relatedTarget)" in viewer_html

    def test_drop_validates_task_exists(self, viewer_html):
        """mapperDrop should validate taskId exists in mapperState.tasks."""
        assert "mapperState.tasks.find(t => t.id === taskId)" in viewer_html

    def test_drop_rejects_already_assigned(self, viewer_html):
        """mapperDrop should reject tasks that are already assigned."""
        assert "mapperState.assignments.hasOwnProperty(taskId)" in viewer_html

    def test_select_all_syncs_on_individual_toggle(self, viewer_html):
        """Selecting all tasks individually should sync selectAllMapped state."""
        assert "mapperState.selectAllMapped = true" in viewer_html
