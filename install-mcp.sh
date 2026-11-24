#!/usr/bin/env bash
# Register the PostHog and Grafana MCP servers with Claude Code at user scope (every project on the box).
# Called from install-tools.sh once `claude` is on PATH. Idempotent: a server is rewritten only when its
# desired config differs from ~/.claude.json, so an OAuth-authenticated posthog entry is left alone.
# Credentials arrive as Coder user secrets (env vars at workspace start), never from this repo:
# Same secrets as the Codex setup in install-mcps.py, so each is set once:
#   POSTHOG_API_KEY                personal API key, "MCP Server" preset (phx_...). Unset -> OAuth: `claude mcp login posthog` per box.
#   GRAFANA_TOKEN_US, GRAFANA_TOKEN_EU  service account tokens for prod-us / prod-eu Grafana, reached over Tailscale.
#                                       Written to ~/.config/grafana/token-<region>; unset -> an existing file is kept.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

GRAFANA_IMAGE="grafana/mcp-grafana"
CLAUDE_CONFIG="$HOME/.claude.json"

for tool in claude jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "coder-dotfiles: $tool missing; skipped MCP registration"; exit 0; }
done

current() { jq -cS --arg n "$1" '.mcpServers[$n] // empty' "$CLAUDE_CONFIG" 2>/dev/null; }

register() { # name desired-json
  local name=$1 desired
  desired=$(jq -cS . <<<"$2")
  if [ "$(current "$name")" = "$desired" ]; then
    echo "coder-dotfiles: MCP '$name' already registered"
    return
  fi
  claude mcp remove --scope user "$name" >/dev/null 2>&1 || true
  if claude mcp add-json --scope user "$name" "$desired" >/dev/null 2>&1; then
    echo "coder-dotfiles: MCP '$name' registered"
  else
    echo "coder-dotfiles: MCP '$name' registration FAILED (retried next start)"
  fi
}

# --- PostHog (hosted, HTTP; routes to the US/EU region of the account behind the key) ---
if [ -n "${POSTHOG_API_KEY:-}" ]; then
  register posthog "$(jq -cn --arg key "$POSTHOG_API_KEY" \
    '{type:"http", url:"https://mcp.posthog.com/mcp", headers:{Authorization:("Bearer "+$key)}}')"
else
  echo "coder-dotfiles: POSTHOG_API_KEY secret unset; posthog MCP needs 'claude mcp login posthog' on this box"
  register posthog '{"type":"http","url":"https://mcp.posthog.com/mcp"}'
fi

# --- Grafana (official image over stdio, via ~/.local/bin/mcp-grafana-tailscale) ---
# The wrapper talks to http://grafana-prod-<region> over Tailscale. The public posthog.dev URLs are behind
# Cognito and redirect every service-account request. Tokens live in files, not ~/.claude.json, so the
# config holds no secrets and works when T3 starts Claude from systemd without the Coder env.
# Pull ahead of time: a first-use pull blows Claude's 30s connection timeout.
if docker pull -q "$GRAFANA_IMAGE" >/dev/null 2>&1; then
  echo "coder-dotfiles: $GRAFANA_IMAGE image ready"
else
  echo "coder-dotfiles: $GRAFANA_IMAGE pull FAILED (first Grafana MCP connection may time out; retried next start)"
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/.local/bin"
install -m 755 "$SCRIPT_DIR/mcp-grafana-tailscale.sh" "$HOME/.local/bin/mcp-grafana-tailscale"
install -d -m 700 "$HOME/.config/grafana"
for region in us eu; do
  var="GRAFANA_TOKEN_${region^^}"
  file="$HOME/.config/grafana/token-$region"
  if [ -n "${!var:-}" ]; then
    (umask 077; printf %s "${!var}" | tr -d '[:space:]' > "$file")
  elif [ ! -s "$file" ]; then
    echo "coder-dotfiles: $var secret unset and $file missing; grafana MCP ($region) will fail to start"
  fi
done
register grafana "$(jq -cn --arg cmd "$HOME/.local/bin/mcp-grafana-tailscale" '{type:"stdio", command:$cmd, args:["us","--disable-write"], env:{}}')"
register grafana-eu "$(jq -cn --arg cmd "$HOME/.local/bin/mcp-grafana-tailscale" '{type:"stdio", command:$cmd, args:["eu","--disable-write"], env:{}}')"
