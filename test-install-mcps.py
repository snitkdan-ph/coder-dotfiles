"""Check that repeated startup preserves personal Codex settings."""

import importlib.util
import os
from pathlib import Path
import tempfile
import tomllib
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("install_mcps", Path(__file__).with_name("install-mcps.py"))
assert spec and spec.loader
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTest(unittest.TestCase):
    def test_preserves_settings_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            path = Path(directory) / "config.toml"
            original = 'model = "example"\n[mcp_servers.custom]\nurl = "https://example.com/mcp"\n'
            path.write_text(original)
            installer.install(path)
            first = path.read_text()
            installer.install(path)
            self.assertEqual(path.read_text(), first)
            parsed = tomllib.loads(first)
            self.assertEqual(parsed["model"], "example")
            self.assertIn("custom", parsed["mcp_servers"])
            self.assertFalse(parsed["mcp_servers"]["github"]["enabled"])
            self.assertEqual(path.with_name("config.toml.before-coder-mcps").read_text(), original)
            with patch.dict(os.environ, {"GH_TOKEN": "test-secret-never-serialize"}):
                installer.install(path)
            self.assertTrue(tomllib.loads(path.read_text())["mcp_servers"]["github"]["enabled"])
            self.assertNotIn("test-secret-never-serialize", path.read_text())

    def test_rejects_conflict_without_changes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.toml"
            original = '[mcp_servers.github]\nurl = "https://example.com/mcp"\n'
            path.write_text(original)
            with self.assertRaises(ValueError):
                installer.install(path)
            self.assertEqual(path.read_text(), original)


if __name__ == "__main__":
    unittest.main()
