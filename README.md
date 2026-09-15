# coder-dotfiles

Personal setup for PostHog Coder devboxes, focused on the `billing` repo. Coder clones this repo and runs `install.sh` on every workspace start.

Registered once with `hogli devbox:setup --configure-dotfiles`.

## What it does

- Registers `gh` as git's HTTPS credential helper so clone/fetch/push never prompt (uses the `GH_TOKEN` Coder secret)
- Configures automatic SSH commit/tag signing from the public `POSTHOG_GIT_SIGNING_KEY` Coder secret. The private key stays in your Mac's 1Password SSH agent. `ssh-sign.sh` finds a live forwarded agent even if T3 retained a socket from an earlier connection.
- Symlinks `.vimrc` to `~/.vimrc` (syntax highlighting on by default)
- `bootstrap-billing.sh` (backgrounded): installs `uv`, clones `PostHog/billing` to `~/billing`, runs `uv sync --dev`, starts the `db` and `redis` containers from `docker-compose.dev.yml`
- `install-tools.sh` (backgrounded and locked against concurrent runs): installs the latest Node 24 release, the latest Codex release from npm, and the latest native Claude Code release on every workspace start. Existing installations are updated too. Node downloads are checked against the official SHA-256 manifest.

Logs: `~/.coder-dotfiles-billing.log`, `~/.coder-dotfiles-tools.log`. Tool installation runs in the background; on a fresh provision, wait for `tool setup complete` before connecting T3. A failed download is reported in the log and retried on the next start; rerun `bash ~/.config/coderv2/dotfiles/install-tools.sh` to retry immediately.

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
| `~/billing` | Billing checkout and `.venv`; its `.env` is separate |
| `~/posthog` | Template-provided PostHog checkout and Docker stack |

The shared `posthog-linux` template owns the base machine, code-server, AgentAPI, hostname/Git identity setup, and the PostHog Docker startup. Those are not defined here. Billing's PostgreSQL and Redis containers are separate from the PostHog containers; the larger stack is useful for frontend integration work but is not required for Billing backend work.

Coder user secrets hold authentication; this public repository contains no tokens or private keys. The Mac's `~/.ssh/config` must enable `ForwardAgent yes` and select the 1Password agent for the Coder host. Keep a T3 SSH connection or `ssh -A` session open when signing. 1Password may ask you to unlock or approve key use.

## Creating PRs from T3

Open `~/billing` in the remote environment. Normal `git commit` signs automatically, `git push` authenticates through `gh`, and `gh pr create` creates the PR. Git signs the commits, not the PR object. The signing public key must be registered with GitHub and the commit email must be verified on that account.

## Still manual on a new box

- `~/billing/.env` from the 1Password item "Local billing environment vars", then `source .env && ./billy migrate && ./billy start`
- Codex auth ships as the `CODEX_AUTH_JSON` Coder file secret (lands at `~/.codex/auth.json`); check with `codex login status`
- Claude uses `CLAUDE_CODE_OAUTH_TOKEN`; GitHub uses `GH_TOKEN`. Renew expired credentials in Coder secrets. The Codex file secret is reapplied on startup, so update it if you reauthenticate on the devbox.

## Rules

- Keep `install.sh` idempotent: it runs on every start
- No secrets in this repo (it is public); secrets go in `hogli devbox:secret:set` / `coder secret create`
