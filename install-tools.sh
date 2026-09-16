#!/usr/bin/env bash
# Serialized so repeated dotfiles runs cannot race while replacing launchers.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/.cache"
exec 9>"$HOME/.cache/coder-dotfiles-tools.lock"
flock 9

bash "$SCRIPT_DIR/install-node.sh"
bash "$SCRIPT_DIR/install-codex.sh"
python3 "$SCRIPT_DIR/install-mcps.py"

# Use Anthropic's native installer, which also supports fresh machines.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl --fail --silent --show-error --location --retry 3 https://claude.ai/install.sh -o "$tmp/install-claude.sh"
bash "$tmp/install-claude.sh" latest
claude --version
echo "coder-dotfiles: tool setup complete"
