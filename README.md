# coder-dotfiles

Personal setup for PostHog Coder devboxes, focused on the `billing` repo. Coder clones this repo and runs `install.sh` on every workspace start.

Registered once with `hogli devbox:setup --configure-dotfiles`. Borrows the bubblewrap, tmux and shell-block ideas from [sortafreel/coder-dotfiles](https://github.com/sortafreel/coder-dotfiles).

## What it does

- Registers `gh` as git's HTTPS credential helper so clone/fetch/push never prompt (uses the `GH_TOKEN` Coder secret)
- Configures automatic SSH commit/tag signing from the public `POSTHOG_GIT_SIGNING_KEY` Coder secret. The private key never leaves the Mac: it lives in Secretive's Secure Enclave and reaches the box through SSH agent forwarding. `ssh-sign.sh` finds a live forwarded agent even if T3 retained a socket from an earlier connection. An allowed-signers file is written alongside so `git log --show-signature` verifies your own commits on the box.
- Warns in the dotfiles log when the `CLAUDE_CODE_OAUTH_TOKEN` secret contains whitespace (a pasted token that wrapped once broke every Claude call), and has login shells export a stripped copy so Claude keeps working until the secret is fixed
- Managed block in `~/.bash_aliases` (rewritten every start): the token guard above, adoption of the newest live forwarded SSH agent socket when the shell has none (T3 Code's remote server and tmux spawn shells without `SSH_AUTH_SOCK`), a Ghostty `TERM` fix, and the `gcmm` / `gpp` aliases
- Managed block in `~/.tmux.conf`: `mouse on` and a 50000-line scrollback, for agents that run inside tmux (a running tmux server needs `tmux source ~/.tmux.conf` once)
- Symlinks `.vimrc` to `~/.vimrc` (syntax highlighting on by default)
- `bootstrap-billing.sh` (backgrounded): installs `uv`, clones `PostHog/billing` to `~/billing`, runs `uv sync --dev`, starts the `db` and `redis` containers from `docker-compose.dev.yml`
- `install-tools.sh` (backgrounded and locked against concurrent runs): installs the latest Node 24 release, the latest Codex release from npm, and the latest native Claude Code release on every workspace start. Existing installations are updated too. Node downloads are checked against the official SHA-256 manifest.
- `install-mcp.sh` (run by `install-tools.sh` once Claude is on PATH): registers the PostHog (`https://mcp.posthog.com/mcp`) and Grafana (`grafana/mcp-grafana` in Docker over stdio, pointed at `grafana.prod-us.posthog.dev`) MCP servers with Claude Code at user scope, so they show up in every project on the box. Credentials come from the same `POSTHOG_API_KEY`, `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN` secrets as the Codex setup and are re-applied on every start, so rotating a secret and restarting the box is enough. Grafana runs with `--disable-write`. Without the PostHog key the server is registered for OAuth and needs `claude mcp login posthog` once per box. The Grafana image is pulled up front, and `-t stdio` is passed explicitly: the image defaults to SSE on :8000, and either a cold pull or the wrong transport makes Claude give up after 30s.
- `install-bubblewrap.sh` (backgrounded, passwordless sudo + apt): installs bubblewrap and activates its AppArmor profile so the Codex CLI sandbox works. Without it Codex warns on every run and falls back to a bundled bubblewrap; Ubuntu 24.04 ships neither the package nor an active profile. Skipped once `bwrap --dev-bind / / true` passes.

Logs: `~/.coder-dotfiles-billing.log`, `~/.coder-dotfiles-tools.log`, `~/.coder-dotfiles-bubblewrap.log`. Tool installation runs in the background; on a fresh provision, wait for `tool setup complete` before connecting T3. A failed download is reported in the log and retried on the next start; rerun `bash ~/.config/coderv2/dotfiles/install-tools.sh` to retry immediately.

## Where things live

| Location | Purpose |
| --- | --- |
| This repository, cloned to `~/.config/coderv2/dotfiles` | Personal startup scripts and Vim configuration |
| `~/.local/bin` | Node/npm/npx, Codex, Claude, uv and the Git signing helper on the SSH PATH |
| `~/.local/opt/node-v24.*` | Verified Node installations |
| `~/.local/opt/codex-cli` | npm-managed Codex installation |
| `~/.local/share/claude/versions` | Claude's native installations |
| `~/.gitconfig` | GitHub HTTPS credential helper and automatic signing configuration |
| `~/.codex/auth.json` | Codex login injected from the `CODEX_AUTH_JSON` Coder file secret |
| `~/.claude.json` | Claude Code user config, including the MCP servers registered by `install-mcp.sh` (mode 600; holds copies of the MCP credentials) |
| `~/billing` | Billing checkout and `.venv`; its `.env` is separate |
| `~/posthog` | Template-provided PostHog checkout and Docker stack |

The shared `posthog-linux` template owns the base machine, code-server, AgentAPI, hostname/Git identity setup, and the PostHog Docker startup. Those are not defined here. Billing's PostgreSQL and Redis containers are separate from the PostHog containers; the larger stack is useful for frontend integration work but is not required for Billing backend work.

## Secrets (Coder user secrets, set from the Mac)

| Secret | Lands as | Purpose |
| --- | --- | --- |
| `GH_TOKEN` | env var | `gh` auth and HTTPS git pushes (`gh auth setup-git`) |
| `POSTHOG_GIT_SIGNING_KEY` | env var | Public half of the Secretive signing key; pushed by `hogli devbox:setup --configure-git-signing` from `git config user.signingkey` |
| `CLAUDE_CODE_OAUTH_TOKEN` | env var | Claude Code auth; from `claude setup-token` via `hogli devbox:setup --configure-claude` |
| `CODEX_AUTH_JSON` | `~/.codex/auth.json` | Codex ChatGPT login; a copy of the Mac's `~/.codex/auth.json` |
| `POSTHOG_API_KEY` | env var (Codex); copied into `~/.claude.json` (Claude) | PostHog MCP auth for both agents; a personal API key created with the **MCP Server** preset (`phx_...`). Claude falls back to OAuth (`claude mcp login posthog` per box) when unset |
| `GRAFANA_URL` | env var (Codex); copied into `~/.claude.json` (Claude) | Grafana instance for the MCP, e.g. `https://grafana.prod-us.posthog.dev/`. Required for Codex; Claude defaults to prod-us when unset |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | env var (Codex); copied into `~/.claude.json` (Claude) | Grafana MCP auth for both agents; a service account token (Administration → Service accounts; Viewer is enough, both agents run read-only) |
| `SLACK_MCP_TOKEN` | env var | Slack MCP for Codex; from an approved Slack app with MCP access |

This public repository contains no tokens or private keys.

## Commit signing over a forwarded agent

The Mac's `~/.ssh/config` must forward the **Secretive** agent to Coder hosts, since that agent holds the signing key GitHub knows about. `hogli devbox:setup` writes `ForwardAgent yes` plus an `IdentityAgent` into its managed `Host coder.*` block, but ssh keeps the first value it sees, so any earlier `Host *` block with a different `IdentityAgent` (for example 1Password) wins. Put this above `Host *`:

```
Host coder.* *.coder coder.dev.posthog.dev
  IdentityAgent ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
```

`hogli devbox:doctor` confirms the agent it forwards holds the key (`Commit signing agent: SHA256:... via ...`). Keep a T3 SSH connection or `ssh -A` session open when signing; Secretive shows a notification per signature.

## Creating PRs from T3

Open `~/billing` in the remote environment. Normal `git commit` signs automatically, `git push` authenticates through `gh`, and `gh pr create` creates the PR. Git signs the commits, not the PR object. The signing public key must be registered with GitHub as a signing key and the commit email must be verified on that account.

## MCPs across devboxes (Codex and Claude)

Claude Code: `install-tools.sh` runs `install-mcp.sh` after installing Claude. It registers `posthog` and `grafana` at Claude's user scope (`~/.claude.json`) with `claude mcp add-json`, reading the same `POSTHOG_API_KEY`, `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN` secrets as below, and pre-pulls the Grafana image. Unlike the Codex block, Claude has no env-var indirection for HTTP headers, so the token values are copied into `~/.claude.json` (mode 600) and refreshed on every start. Retry by hand with `bash ~/.config/coderv2/dotfiles/install-mcp.sh && claude mcp list`.

Codex: `install-tools.sh` runs `install-mcps.py` after installing Codex. It adds a managed
block to `~/.codex/config.toml`, preserves other settings, and keeps an initial
backup at `~/.codex/config.toml.before-coder-mcps`. Existing definitions with the
same names outside the managed block cause an error instead of being overwritten.

| MCP | Authentication on each box |
| --- | --- |
| GitHub | Existing `GH_TOKEN` Coder secret |
| PostHog | `POSTHOG_API_KEY` Coder secret, using a personal key with the needed project access |
| Slack | `SLACK_MCP_TOKEN` Coder secret from an approved Slack app with MCP access and the required user scopes |
| Grafana | `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN` Coder secrets |
| Granola | Browser OAuth through `codex mcp login granola` on each box |

From the Mac's authenticated PostHog checkout, set missing secrets with the
hidden interactive prompts:

```bash
hogli devbox:secret:set POSTHOG_API_KEY
hogli devbox:secret:set SLACK_MCP_TOKEN
hogli devbox:secret:set GRAFANA_URL
hogli devbox:secret:set GRAFANA_SERVICE_ACCOUNT_TOKEN
```

These are per-user secrets. Restart your workspaces to inject them and run the
updated dotfiles. Each box must be configured to use this repository. The setup
does not modify other users' boxes or the shared Coder template. Restart the
Codex/T3 session after configuration changes. To retry only MCP configuration:

```bash
python3 ~/.config/coderv2/dotfiles/install-mcps.py
codex mcp list
```

Token-based servers stay disabled until their environment variables are present
when the installer runs. Token values are never written into the generated
config. The Codex host process must also inherit those variables at runtime.
Granola is registered for OAuth; registration alone does not authenticate it.
Do not distribute a shared copy of rotating OAuth refresh credentials to boxes.

Grafana runs the official `grafana/mcp-grafana:latest` Docker image with
`--disable-write`. Docker must be available and the configured Grafana URL must
be reachable from the box. The first connection pulls the image. Use a Grafana
API URL appropriate to the remote network; a browser URL behind interactive SSO
may not work with a service-account token. No image is pulled by the installer.

Slack's official MCP requires a registered app; an arbitrary Slack token is not
enough. Granola MCP supports browser OAuth or enterprise-managed authorization,
not API keys. Provisioning their definitions cannot bypass these requirements.

Sources: [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp),
[PostHog MCP](https://posthog.com/docs/model-context-protocol),
[GitHub Codex setup](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-codex.md),
[Slack MCP](https://docs.slack.dev/ai/slack-mcp-server/),
[Granola MCP](https://docs.granola.ai/help-center/sharing/integrations/mcp),
[Grafana MCP](https://github.com/grafana/mcp-grafana).

## Other manual setup on a new box

- `~/billing/.env` from the 1Password item "Local billing environment vars", then `source .env && ./billy migrate && ./billy start`
- Codex auth ships as the `CODEX_AUTH_JSON` Coder file secret (lands at `~/.codex/auth.json`); check with `codex login status`
- MCP servers for Codex and Claude come from the secrets in the section above; a box started before they existed shows Claude's `posthog` as needing auth (`claude mcp login posthog` works meanwhile) and `grafana` as connected but unauthenticated. Check with `codex mcp list` and `claude mcp list`.
- Claude uses `CLAUDE_CODE_OAUTH_TOKEN`; GitHub uses `GH_TOKEN`. Renew expired credentials in Coder secrets (`hogli devbox:secret:set`), then restart the box: secrets only land at workspace start. Verify Claude with a real call (`claude -p "reply with exactly: ok"`), since a set env var proves nothing. The Codex file secret is reapplied on startup, so update it if you reauthenticate on the devbox.

## Verify a box in one shot

```bash
hogli devbox:exec -n <label> -- bash -lc '
gh api user --jq .login
git config --global --get user.signingkey | cut -c1-40
bwrap --dev-bind / / true && echo bwrap ok
codex login status
cd ~/billing && claude -p "reply with exactly: ok"
claude mcp list
tail -1 ~/.coder-dotfiles-tools.log ~/.coder-dotfiles-billing.log ~/.coder-dotfiles-bubblewrap.log'
```

## Rules

- Keep `install.sh` idempotent: it runs on every start
- No secrets in this repo (it is public); secrets go in `hogli devbox:secret:set` / `coder secret create`
- Anything slow or network-bound gets backgrounded from `install.sh` so workspace start isn't blocked
