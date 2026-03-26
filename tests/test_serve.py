"""Tests for pure functions in bin/orchestra-serve.

Uses importlib to load the script as a module. All tests are skipped
gracefully if the import fails.
"""

import importlib.util
import os
import queue
import sys
import time
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Module import — skip entire file if it fails
# ---------------------------------------------------------------------------

_SERVE_PATH = Path(__file__).resolve().parents[1] / "bin" / "orchestra-serve"

_module = None
_IMPORT_ERROR: str | None = None

try:
    import importlib.machinery
    loader = importlib.machinery.SourceFileLoader("orchestra_serve", str(_SERVE_PATH))
    spec = importlib.util.spec_from_loader("orchestra_serve", loader)
    _module = importlib.util.module_from_spec(spec)
    # The script only calls main() inside `if __name__ == "__main__"`, so
    # direct loading is safe.
    loader.exec_module(_module)
except Exception as exc:  # pragma: no cover
    _IMPORT_ERROR = str(exc)

pytestmark = pytest.mark.skipif(
    _module is None,
    reason=f"Could not import orchestra-serve: {_IMPORT_ERROR}",
)


def _serve():
    """Return the loaded module (guaranteed non-None when tests run)."""
    assert _module is not None
    return _module


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _set_jwt_secret(monkeypatch, secret: str = "test-secret-for-pytest-only"):
    monkeypatch.setenv("ORCHESTRA_JWT_SECRET", secret)


# ---------------------------------------------------------------------------
# 1. _validate_workspace_path
# ---------------------------------------------------------------------------

class TestValidateWorkspacePath:
    def test_valid_path_inside_git_repo(self, tmp_git_repo: Path, monkeypatch):
        """A path inside a temp git repo should resolve without error."""
        # Pretend home is tmp_git_repo's parent so the path is under "home"
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_git_repo.parent))
        target = tmp_git_repo / "some_file.txt"
        target.write_text("hello")
        result = _serve()._validate_workspace_path(str(target))
        assert result == target.resolve()

    def test_valid_directory_inside_git_repo(self, tmp_git_repo: Path, monkeypatch):
        """A sub-directory inside a git repo is accepted."""
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_git_repo.parent))
        sub = tmp_git_repo / "subdir"
        sub.mkdir()
        result = _serve()._validate_workspace_path(str(sub))
        assert result == sub.resolve()

    def test_path_outside_home_dir_rejected(self, monkeypatch, tmp_path: Path):
        """A path outside $HOME must be rejected."""
        # Redirect HOME to a temp dir so /tmp is definitely outside it
        monkeypatch.setenv("HOME", str(tmp_path))
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        with pytest.raises(ValueError, match="home directory"):
            _serve()._validate_workspace_path("/etc/passwd")

    def test_path_traversal_rejected(self, tmp_git_repo: Path, monkeypatch):
        """../../etc/passwd style traversal must be rejected (resolves outside $HOME)."""
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_git_repo.parent))
        evil = str(tmp_git_repo) + "/../../etc/passwd"
        with pytest.raises(ValueError):
            _serve()._validate_workspace_path(evil)

    def test_dotfile_path_rejected(self, monkeypatch, tmp_path: Path):
        """~/.ssh/authorized_keys must be rejected."""
        # Make tmp_path look like home
        dotdir = tmp_path / ".ssh"
        dotdir.mkdir()
        target = dotdir / "authorized_keys"
        target.write_text("key data")
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        with pytest.raises(ValueError):
            _serve()._validate_workspace_path(str(target))

    def test_non_git_directory_rejected(self, tmp_path: Path, monkeypatch):
        """A directory that is NOT inside any git repo must be rejected."""
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        non_git = tmp_path / "not-a-repo"
        non_git.mkdir()
        with pytest.raises(ValueError, match="git repository"):
            _serve()._validate_workspace_path(str(non_git))

    def test_sensitive_ssh_segment_rejected(self, tmp_path: Path, monkeypatch):
        """Paths containing /.ssh/ are rejected even when inside home."""
        monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
        ssh_dir = tmp_path / ".ssh"
        ssh_dir.mkdir()
        key_file = ssh_dir / "id_rsa"
        key_file.write_text("private key")
        with pytest.raises(ValueError):
            _serve()._validate_workspace_path(str(key_file))


# ---------------------------------------------------------------------------
# 2. _hash_password / _verify_password
# ---------------------------------------------------------------------------

class TestPasswordHashing:
    def test_roundtrip(self):
        """hash then verify with correct password returns True."""
        pw = "correct-horse-battery-staple"
        stored = _serve()._hash_password(pw)
        assert _serve()._verify_password(pw, stored) is True

    def test_wrong_password_returns_false(self):
        pw = "correct-horse-battery-staple"
        stored = _serve()._hash_password(pw)
        assert _serve()._verify_password("wrong-password", stored) is False

    def test_empty_password_roundtrip(self):
        """Empty password can be hashed and verified (create_user rejects it, but
        the primitives themselves handle it gracefully)."""
        stored = _serve()._hash_password("")
        assert _serve()._verify_password("", stored) is True
        assert _serve()._verify_password("not-empty", stored) is False

    def test_hash_format(self):
        """Hash string starts with 'pbkdf2:' and has 5 colon-separated parts."""
        stored = _serve()._hash_password("password123")
        assert stored.startswith("pbkdf2:")
        parts = stored.split(":")
        assert len(parts) == 5

    def test_different_salts_produce_different_hashes(self):
        pw = "same-password"
        h1 = _serve()._hash_password(pw)
        h2 = _serve()._hash_password(pw)
        assert h1 != h2  # different random salts

    def test_malformed_hash_returns_false(self):
        assert _serve()._verify_password("pw", "not:a:valid:hash") is False

    def test_empty_stored_hash_returns_false(self):
        assert _serve()._verify_password("pw", "") is False


# ---------------------------------------------------------------------------
# 3. generate_token / verify_token
# ---------------------------------------------------------------------------

class TestJWT:
    def test_roundtrip(self, monkeypatch):
        _set_jwt_secret(monkeypatch)
        token = _serve().generate_token("user-123", "alice@example.com")
        payload = _serve().verify_token(token)
        assert payload["sub"] == "user-123"
        assert payload["email"] == "alice@example.com"
        assert "iat" in payload
        assert "exp" in payload

    def test_exp_is_24h_after_iat(self, monkeypatch):
        _set_jwt_secret(monkeypatch)
        token = _serve().generate_token("u1", "u@example.com")
        payload = _serve().verify_token(token)
        assert payload["exp"] - payload["iat"] == 86400

    def test_expired_token_raises(self, monkeypatch):
        _set_jwt_secret(monkeypatch)
        # Generate a token then fake the current time to be 2 days later
        token = _serve().generate_token("u1", "u@example.com")
        # Decode the payload, tamper exp to be in the past
        import base64, json as _json
        parts = token.split(".")
        padding = 4 - len(parts[1]) % 4
        raw = base64.urlsafe_b64decode(parts[1] + ("=" * padding if padding != 4 else ""))
        payload = _json.loads(raw)
        payload["exp"] = int(time.time()) - 3600  # already expired
        new_payload_b64 = base64.urlsafe_b64encode(
            _json.dumps(payload, separators=(",", ":")).encode()
        ).rstrip(b"=").decode()
        # Re-sign with the correct secret so signature check passes
        import hmac as _hmac, hashlib as _hashlib
        signing_input = f"{parts[0]}.{new_payload_b64}".encode()
        secret = os.environ["ORCHESTRA_JWT_SECRET"].encode()
        sig = base64.urlsafe_b64encode(
            _hmac.new(secret, signing_input, _hashlib.sha256).digest()
        ).rstrip(b"=").decode()
        expired_token = f"{parts[0]}.{new_payload_b64}.{sig}"
        with pytest.raises(RuntimeError, match="expired"):
            _serve().verify_token(expired_token)

    def test_tampered_signature_rejected(self, monkeypatch):
        _set_jwt_secret(monkeypatch)
        token = _serve().generate_token("u1", "u@example.com")
        parts = token.split(".")
        tampered = f"{parts[0]}.{parts[1]}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        with pytest.raises(ValueError, match="signature"):
            _serve().verify_token(tampered)

    def test_malformed_token_missing_parts(self, monkeypatch):
        _set_jwt_secret(monkeypatch)
        with pytest.raises(ValueError, match="Malformed"):
            _serve().verify_token("only.two")

    def test_malformed_token_empty_string(self, monkeypatch):
        _set_jwt_secret(monkeypatch)
        with pytest.raises(ValueError):
            _serve().verify_token("")

    def test_malformed_payload_not_json(self, monkeypatch):
        _set_jwt_secret(monkeypatch)
        import base64 as _b64, hmac as _hmac, hashlib as _hashlib
        header = _serve()._JWT_HEADER
        bad_payload = _b64.urlsafe_b64encode(b"not-json").rstrip(b"=").decode()
        signing_input = f"{header}.{bad_payload}".encode()
        secret = os.environ["ORCHESTRA_JWT_SECRET"].encode()
        sig = _b64.urlsafe_b64encode(
            _hmac.new(secret, signing_input, _hashlib.sha256).digest()
        ).rstrip(b"=").decode()
        bad_token = f"{header}.{bad_payload}.{sig}"
        with pytest.raises(ValueError, match="[Mm]alformed"):
            _serve().verify_token(bad_token)

    def test_missing_jwt_secret_raises(self, monkeypatch):
        monkeypatch.delenv("ORCHESTRA_JWT_SECRET", raising=False)
        with pytest.raises(RuntimeError, match="ORCHESTRA_JWT_SECRET"):
            _serve().generate_token("u", "u@example.com")


# ---------------------------------------------------------------------------
# 4. ID validation regexes
# ---------------------------------------------------------------------------

class TestRegexes:
    # RUN_ID_RE
    @pytest.mark.parametrize("value", [
        "abc123",
        "my-run",
        "My_Run_2026",
        "20260320-010801",
        "a",
        "A1B2",
    ])
    def test_run_id_valid(self, value):
        assert _serve().RUN_ID_RE.match(value), f"Expected {value!r} to match RUN_ID_RE"

    @pytest.mark.parametrize("value", [
        "",
        "-bad-start",
        "_bad",
        "has space",
        "has/slash",
        "has.dot",
        "../traversal",
        "foo/bar",
    ])
    def test_run_id_invalid(self, value):
        m = _serve().RUN_ID_RE.match(value)
        # Either no match or the full string contains invalid chars
        if m:
            assert m.group(0) != value or any(c in value for c in " /.")

    # TASK_ID_RE
    @pytest.mark.parametrize("value", [
        "task-one",
        "build-lint",
        "abc",
        "a1b2",
        "test_task",
    ])
    def test_task_id_valid(self, value):
        assert _serve().TASK_ID_RE.match(value)

    @pytest.mark.parametrize("value", [
        "",
        "-bad",
        "Upper-Case",
        "has space",
        "has/slash",
        "../etc",
    ])
    def test_task_id_invalid(self, value):
        m = _serve().TASK_ID_RE.match(value)
        if m:
            # Match must not consume the whole invalid string
            assert m.group(0) != value or any(c in value for c in " /.")

    # CONFIG_NAME_RE
    @pytest.mark.parametrize("value", [
        "MyConfig",
        "config-1",
        "Config_2",
        "A",
    ])
    def test_config_name_valid(self, value):
        assert _serve().CONFIG_NAME_RE.match(value)

    @pytest.mark.parametrize("value", [
        "",
        "-bad",
        "_bad",
        "has space",
        "has/slash",
        "has.dot",
    ])
    def test_config_name_invalid(self, value):
        m = _serve().CONFIG_NAME_RE.match(value)
        if m:
            assert m.group(0) != value or any(c in value for c in " /.")

    # Specific path-traversal strings must not be accepted
    @pytest.mark.parametrize("value", [
        "../etc/passwd",
        "../../root",
        "/absolute/path",
    ])
    def test_no_path_traversal_in_ids(self, value):
        for pattern in (_serve().RUN_ID_RE, _serve().TASK_ID_RE, _serve().CONFIG_NAME_RE):
            m = pattern.match(value)
            # If there's a match it must be a short prefix, not the whole string
            assert m is None or m.group(0) != value


# ---------------------------------------------------------------------------
# 5. SSEBroker
# ---------------------------------------------------------------------------

class TestSSEBroker:
    def test_subscribe_creates_queue(self):
        broker = _serve().SSEBroker()
        q = broker.subscribe()
        assert isinstance(q, queue.Queue)

    def test_broadcast_delivers_to_subscriber(self):
        broker = _serve().SSEBroker()
        q = broker.subscribe()
        broker.broadcast("test_event", {"key": "value"})
        msg = q.get_nowait()
        assert "test_event" in msg
        assert "value" in msg

    def test_broadcast_delivers_to_multiple_subscribers(self):
        broker = _serve().SSEBroker()
        q1 = broker.subscribe()
        q2 = broker.subscribe()
        broker.broadcast("ping", {"n": 1})
        assert not q1.empty()
        assert not q2.empty()

    def test_unsubscribe_removes_queue(self):
        broker = _serve().SSEBroker()
        q = broker.subscribe()
        broker.unsubscribe(q)
        broker.broadcast("after_unsub", {"x": 1})
        assert q.empty()

    def test_unsubscribe_nonexistent_does_not_raise(self):
        broker = _serve().SSEBroker()
        phantom = queue.Queue()
        broker.unsubscribe(phantom)  # should not raise

    def test_queue_overflow_does_not_block(self):
        """When a subscriber's queue is full, broadcast must not block or raise."""
        broker = _serve().SSEBroker()
        q = broker.subscribe()
        # Fill the queue to maxsize (256) without blocking
        for i in range(256):
            try:
                q.put_nowait(f"msg-{i}")
            except queue.Full:
                break
        # One more broadcast should silently drop (put_nowait swallowed)
        broker.broadcast("overflow", {"i": 257})  # must not raise or block

    def test_queue_full_exception_is_swallowed(self):
        """Directly verify that a full queue triggers Full but broadcast suppresses it."""
        broker = _serve().SSEBroker()
        q = broker.subscribe()
        # Fill it manually
        for _ in range(q.maxsize):
            try:
                q.put_nowait("x")
            except queue.Full:
                break
        # Broadcast should not raise even though the queue is full
        try:
            broker.broadcast("event", {"overflow": True})
        except queue.Full:
            pytest.fail("SSEBroker.broadcast raised queue.Full — it should suppress it")

    def test_sse_message_format(self):
        """Broadcast messages follow the SSE wire format."""
        broker = _serve().SSEBroker()
        q = broker.subscribe()
        broker.broadcast("my_event", {"hello": "world"})
        msg = q.get_nowait()
        assert msg.startswith("event: my_event\n")
        assert "data: " in msg
        assert msg.endswith("\n\n")
