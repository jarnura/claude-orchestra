"""Shared pytest fixtures for orchestra-serve tests."""

import pytest
from pathlib import Path


@pytest.fixture
def tmp_git_repo(tmp_path: Path) -> Path:
    """Create a temp directory with a .git subfolder (bare enough to satisfy path validation)."""
    git_dir = tmp_path / ".git"
    git_dir.mkdir()
    return tmp_path
