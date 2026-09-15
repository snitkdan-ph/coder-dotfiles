#!/usr/bin/env bash
# Bring the PostHog/billing repo to a runnable state: uv, clone, deps, db + redis containers.
# Backgrounded by install.sh. Idempotent: every step skips or no-ops when already done.
# Does NOT create .env: that holds secrets and comes from 1Password ("Local billing environment vars").
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
echo "=== $(date -Is) bootstrap-billing start"

# uv (billing uses uv, not flox)
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 \
    && echo "uv installed: $(uv --version)" || echo "uv install FAILED"
fi

# clone (HTTPS; relies on gh credential helper set up by install.sh)
if [ ! -d "$HOME/billing/.git" ]; then
  gh repo clone PostHog/billing "$HOME/billing" 2>&1 && echo "billing cloned" || echo "billing clone FAILED"
fi

if [ -d "$HOME/billing/.git" ]; then
  cd "$HOME/billing"
  uv sync --dev 2>&1 | tail -1 && echo "uv sync done" || echo "uv sync FAILED"

  # docker daemon may still be coming up at workspace start
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
  if docker info >/dev/null 2>&1; then
    docker compose -f docker-compose.dev.yml up db redis -d 2>&1 | grep -v "obsolete" || true
    docker compose -f docker-compose.dev.yml ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
  else
    echo "docker daemon not ready; skipped db/redis"
  fi

  [ -f .env ] || echo "NOTE: ~/billing/.env missing. Create it from 1Password item 'Local billing environment vars', then: source .env && ./billy migrate && ./billy start"
fi
echo "=== $(date -Is) bootstrap-billing done"
