#!/usr/bin/env bash
# Register the PostHog and Grafana MCP servers with Claude Code at user scope (every project on the box).
# Called from install-tools.sh once `claude` is on PATH. Idempotent: a server is rewritten only when its
# desired config differs from ~/.claude.json, so an OAuth-authenticated posthog entry is left alone.
# Credentials arrive as Coder user secrets (env vars at workspace start), never from this repo:
# Same secrets as the Codex setup in install-mcps.py, so each is set once:
#   POSTHOG_API_KEY                personal API key, "MCP Server" preset (phx_...). Unset -> OAuth: `claude mcp login posthog` per box.
#   GRAFANA_URL                    Grafana instance; defaults to prod-us when unset.
#   GRAFANA_SERVICE_ACCOUNT_TOKEN  service account token for GRAFANA_URL. Unset -> registered, but every call is unauthenticated.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

GRAFANA_URL="${GRAFANA_URL:-https://grafana.prod-us.posthog.dev/}"
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

# --- Grafana (official image over stdio) ---
# The image's entrypoint defaults to SSE on :8000; without `-t stdio` Claude waits 30s and gives up.
# Pull ahead of time for the same reason: a first-use pull also blows Claude's connection timeout.
if docker pull -q "$GRAFANA_IMAGE" >/dev/null 2>&1; then
  echo "coder-dotfiles: $GRAFANA_IMAGE image ready"
else
  echo "coder-dotfiles: $GRAFANA_IMAGE pull FAILED (first Grafana MCP connection may time out; retried next start)"
fi
[ -n "${GRAFANA_SERVICE_ACCOUNT_TOKEN:-}" ] || echo "coder-dotfiles: GRAFANA_SERVICE_ACCOUNT_TOKEN secret unset; grafana MCP will not authenticate"
register grafana "$(jq -cn --arg url "$GRAFANA_URL" --arg token "${GRAFANA_SERVICE_ACCOUNT_TOKEN:-}" --arg image "$GRAFANA_IMAGE" \
  '{type:"stdio", command:"docker",
    args:["run","--rm","-i","-e","GRAFANA_URL","-e","GRAFANA_SERVICE_ACCOUNT_TOKEN",$image,"-t","stdio","--disable-write"],
    env:({GRAFANA_URL:$url} + (if $token != "" then {GRAFANA_SERVICE_ACCOUNT_TOKEN:$token} else {} end))}')"
