from __future__ import annotations

import json
import shutil
import sqlite3
import unittest
from uuid import uuid4
from pathlib import Path

import sync_backend


THREADS_TABLE_SQL = """
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    model_provider TEXT NOT NULL,
    updated_at INTEGER NOT NULL
)
"""

TEMP_ROOT = Path(__file__).resolve().parent / ".tmp-tests"
TEMP_ROOT.mkdir(parents=True, exist_ok=True)


class CurrentIdentityTests(unittest.TestCase):
    def test_prefers_config_provider_when_present(self) -> None:
        temp_dir = self._make_temp_dir()
        try:
            paths = sync_backend.resolve_paths(str(temp_dir))
            paths.codex_home.mkdir(parents=True, exist_ok=True)
            paths.config_path.write_text('model_provider = "micu"\n', encoding="utf-8")
            paths.auth_path.write_text(
                json.dumps({"auth_mode": "chatgpt"}, ensure_ascii=False),
                encoding="utf-8",
            )

            identity = sync_backend.resolve_current_identity(
                paths,
                sync_backend.read_text(paths.config_path),
            )

            self.assertEqual(identity.provider, "micu")
            self.assertEqual(identity.provider_source, "config.toml:model_provider")
            self.assertEqual(identity.auth_mode, "chatgpt")
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_falls_back_to_openai_for_chatgpt_auth(self) -> None:
        temp_dir = self._make_temp_dir()
        try:
            paths = sync_backend.resolve_paths(str(temp_dir))
            paths.codex_home.mkdir(parents=True, exist_ok=True)
            paths.config_path.write_text('model = "gpt-5.4"\n', encoding="utf-8")
            paths.auth_path.write_text(
                json.dumps({"auth_mode": "chatgpt"}, ensure_ascii=False),
                encoding="utf-8",
            )

            identity = sync_backend.resolve_current_identity(
                paths,
                sync_backend.read_text(paths.config_path),
            )

            self.assertEqual(identity.provider, "openai")
            self.assertEqual(identity.provider_source, "auth.json:auth_mode=chatgpt")
            self.assertEqual(identity.auth_mode, "chatgpt")
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def _make_temp_dir(self) -> Path:
        temp_dir = TEMP_ROOT / f"current-identity-{uuid4().hex}"
        temp_dir.mkdir(parents=True, exist_ok=False)
        return temp_dir


class StatusTests(unittest.TestCase):
    def test_status_uses_chatgpt_fallback_provider(self) -> None:
        temp_dir = self._make_temp_dir()
        try:
            paths = sync_backend.resolve_paths(str(temp_dir))
            self._prepare_codex_home(paths)
            paths.config_path.write_text('model = "gpt-5.4"\n', encoding="utf-8")
            paths.auth_path.write_text(
                json.dumps({"auth_mode": "chatgpt"}, ensure_ascii=False),
                encoding="utf-8",
            )

            with sqlite3.connect(paths.db_path) as conn:
                conn.execute(THREADS_TABLE_SQL)
                conn.execute(
                    "INSERT INTO threads (id, model_provider, updated_at) VALUES (?, ?, ?)",
                    ("thread-api", "micu", 1),
                )
                conn.commit()

            status = sync_backend.get_status(paths)

            self.assertEqual(status["current_provider"], "openai")
            self.assertEqual(status["current_provider_source"], "auth.json:auth_mode=chatgpt")
            self.assertEqual(status["current_auth_mode"], "chatgpt")
            self.assertEqual(status["movable_database_threads"], 1)
            self.assertEqual(status["movable_threads"], 1)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def _prepare_codex_home(self, paths: sync_backend.Paths) -> None:
        paths.codex_home.mkdir(parents=True, exist_ok=True)
        paths.sessions_dir.mkdir(parents=True, exist_ok=True)
        paths.session_index_path.write_text("", encoding="utf-8")

    def _make_temp_dir(self) -> Path:
        temp_dir = TEMP_ROOT / f"status-{uuid4().hex}"
        temp_dir.mkdir(parents=True, exist_ok=False)
        return temp_dir


if __name__ == "__main__":
    unittest.main()
