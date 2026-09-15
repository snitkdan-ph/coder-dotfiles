#!/usr/bin/env bash
# Install the OpenAI Codex CLI into ~/.local/bin. Backgrounded by install.sh; skips when present.
# Login is not handled here: ~/.codex/auth.json arrives as the CODEX_AUTH_JSON Coder file secret.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

if ! command -v codex >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) echo "coder-dotfiles: unsupported arch $(uname -m) for codex"; exit 0 ;;
  esac
  asset="codex-${arch}-unknown-linux-musl"
  url="https://github.com/openai/codex/releases/latest/download/${asset}.tar.gz"
  tmp="$(mktemp -d)"
  if curl -fsSL "$url" | tar -xz -C "$tmp"; then
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$tmp/${asset}" "$HOME/.local/bin/codex"
    echo "coder-dotfiles: codex installed: $("$HOME/.local/bin/codex" --version 2>&1)"
  else
    echo "coder-dotfiles: codex download FAILED (will retry next start)"
  fi
  rm -rf "$tmp"
fi

# Report whether the file secret landed (never prints the token).
if command -v codex >/dev/null 2>&1; then
  chmod 600 "$HOME/.codex/auth.json" 2>/dev/null || true
  echo "coder-dotfiles: codex login status: $(codex login status 2>&1 | head -1)"
fi
