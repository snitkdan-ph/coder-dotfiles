#!/usr/bin/env bash
# Run grafana/mcp-grafana against PostHog Grafana over Tailscale. Installed to ~/.local/bin/mcp-grafana-tailscale.
# The public grafana.prod-<region>.posthog.dev URLs sit behind Cognito, which 302s service-account
# requests, so this uses the tailnet hostnames instead.
# Token: ~/.config/grafana/token-<region> (mode 600), written by install-mcp.sh from the
# GRAFANA_TOKEN_<REGION> Coder secret. A file (not an env var) because T3 starts Claude and Codex
# from systemd, which never sees the Coder secrets.
set -euo pipefail
region="${1:?usage: mcp-grafana-tailscale <us|eu> [mcp-grafana args...]}"
shift
token_file="$HOME/.config/grafana/token-$region"
if [ ! -s "$token_file" ]; then
  echo "mcp-grafana-tailscale: missing $token_file (set the GRAFANA_TOKEN_${region^^} Coder secret and restart the box)" >&2
  exit 1
fi
GRAFANA_SERVICE_ACCOUNT_TOKEN="$(cat "$token_file")"
export GRAFANA_SERVICE_ACCOUNT_TOKEN
export GRAFANA_URL="http://grafana-prod-$region"
# --network host: the container needs the box's tailnet DNS and routes.
exec docker run --rm -i --network host -e GRAFANA_URL -e GRAFANA_SERVICE_ACCOUNT_TOKEN \
  grafana/mcp-grafana -t stdio "$@"
