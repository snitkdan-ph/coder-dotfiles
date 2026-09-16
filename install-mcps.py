#!/usr/bin/env python3
"""Install personal Codex MCP definitions without replacing other configuration."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import tempfile
import tomllib

START = "# >>> coder-dotfiles MCP >>>"
END = "# <<< coder-dotfiles MCP <<<"


def configuration() -> str:
    entries: list[str] = []
    for name, url, token in (
        ("posthog", "https://mcp.posthog.com/mcp", "POSTHOG_API_KEY"),
        ("github", "https://api.githubcopilot.com/mcp/", "GH_TOKEN"),
        ("slack", "https://mcp.slack.com/mcp", "SLACK_MCP_TOKEN"),
        ("granola", "https://mcp.granola.ai/mcp", None),
    ):
        enabled = token is None or bool(os.environ.get(token))
        lines = [f"[mcp_servers.{name}]", f"url = {json.dumps(url)}",
                 f"enabled = {str(enabled).lower()}"]
        if token:
            lines.append(f"bearer_token_env_var = {json.dumps(token)}")
        entries.append("\n".join(lines))
    grafana_enabled = bool(os.environ.get("GRAFANA_URL") and os.environ.get("GRAFANA_SERVICE_ACCOUNT_TOKEN"))
    entries.append("\n".join([
        "[mcp_servers.grafana]",
        'command = "docker"',
        'args = ["run", "--rm", "-i", "--env", "GRAFANA_URL", "--env", '
        '"GRAFANA_SERVICE_ACCOUNT_TOKEN", "grafana/mcp-grafana:latest", "-t", "stdio", "--disable-write"]',
        'env_vars = ["GRAFANA_URL", "GRAFANA_SERVICE_ACCOUNT_TOKEN"]',
        "startup_timeout_sec = 120",
        f"enabled = {str(grafana_enabled).lower()}",
    ]))
    return "\n\n".join(entries)


def install(destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with (destination.parent / ".coder-dotfiles-mcp.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        original = destination.read_text() if destination.exists() else ""
        if original.count(START) != original.count(END) or original.count(START) > 1:
            raise ValueError("Invalid managed MCP markers; config was not changed")
        remaining = original
        if START in original:
            before, rest = original.split(START, 1)
            _, after = rest.split(END, 1)
            remaining = before + after
        existing = tomllib.loads(remaining)
        block = configuration()
        managed = tomllib.loads(block)["mcp_servers"]
        conflicts = set(existing.get("mcp_servers", {})) & set(managed)
        if conflicts:
            raise ValueError("Existing unmanaged MCP definitions: " + ", ".join(sorted(conflicts)))
        updated = remaining.rstrip() + "\n\n" + START + "\n" + block + "\n" + END + "\n"
        tomllib.loads(updated)
        if updated != original:
            # Keep the original file for recovery and replace atomically.
            backup = destination.with_name("config.toml.before-coder-mcps")
            if destination.exists() and not backup.exists():
                with open(backup, "x", opener=lambda path, flags: os.open(path, flags, 0o600)) as handle:
                    handle.write(original)
            with tempfile.NamedTemporaryFile(mode="w", dir=destination.parent, delete=False) as handle:
                temporary = Path(handle.name)
                handle.write(updated)
            try:
                temporary.replace(destination)
            finally:
                temporary.unlink(missing_ok=True)
        for name, settings in managed.items():
            print(f"{name}: {'configured' if settings['enabled'] else 'disabled (missing environment credentials/URL)'}")
        print("Granola needs OAuth on each box: codex mcp login granola")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))) / "config.toml")
    install(parser.parse_args().config)
