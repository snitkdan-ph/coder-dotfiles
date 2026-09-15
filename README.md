# coder-dotfiles

Personal setup for PostHog Coder devboxes, focused on the `billing` repo. Coder clones this repo and runs `install.sh` on every workspace start.

Registered once with `hogli devbox:setup --configure-dotfiles`.

## What it does

- Registers `gh` as git's HTTPS credential helper so clone/fetch/push never prompt (uses the `GH_TOKEN` Coder secret)
- Reapplies commit-signing config from `POSTHOG_GIT_SIGNING_KEY` if the template's boot bootstrap raced
- Symlinks `.vimrc` to `~/.vimrc` (syntax highlighting on by default)
- `bootstrap-billing.sh` (backgrounded): installs `uv`, clones `PostHog/billing` to `~/billing`, runs `uv sync --dev`, starts the `db` and `redis` containers from `docker-compose.dev.yml`
- `install-codex.sh` (backgrounded): installs the Codex CLI to `~/.local/bin/codex`

Logs: `~/.coder-dotfiles-billing.log`, `~/.coder-dotfiles-codex.log`.

## Still manual on a new box

- `~/billing/.env` from the 1Password item "Local billing environment vars", then `source .env && ./billy migrate && ./billy start`
- Codex auth ships as the `CODEX_AUTH_JSON` Coder file secret (lands at `~/.codex/auth.json`); check with `codex login status`

## Rules

- Keep `install.sh` idempotent: it runs on every start
- No secrets in this repo (it is public); secrets go in `hogli devbox:secret:set` / `coder secret create`
