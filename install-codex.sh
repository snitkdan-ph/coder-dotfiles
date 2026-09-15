#!/usr/bin/env bash
# Resolve latest on every workspace start, including when a baked CLI already exists.
# Authentication is supplied separately by the CODEX_AUTH_JSON Coder file secret.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

npm install --global --prefix "$HOME/.local/opt/codex-cli" @openai/codex@latest
mkdir -p "$HOME/.local/bin"
ln -sfn "$HOME/.local/opt/codex-cli/bin/codex" "$HOME/.local/bin/codex"
codex --version
if [ -f "$HOME/.codex/auth.json" ]; then
  chmod 600 "$HOME/.codex/auth.json"
fi
codex login status || echo "Codex needs login: codex login --device-auth"
