# coder-dotfiles

Personal setup for PostHog Coder devboxes, focused on the `billing` repo. Coder clones this repo and runs `install.sh` on every workspace start.

Registered once with `hogli devbox:setup --configure-dotfiles`. Borrows the bubblewrap, tmux and shell-block ideas from [sortafreel/coder-dotfiles](https://github.com/sortafreel/coder-dotfiles).

## What it does

- Registers `gh` as git's HTTPS credential helper so clone/fetch/push never prompt (uses the `GH_TOKEN` Coder secret)
- Configures automatic SSH commit/tag signing from the public `POSTHOG_GIT_SIGNING_KEY` Coder secret. The private key never leaves the Mac: it lives in Secretive's Secure Enclave and reaches the box through SSH agent forwarding. `ssh-sign.sh` finds a live forwarded agent even if T3 retained a socket from an earlier connection.
- Warns in the dotfiles log when the `CLAUDE_CODE_OAUTH_TOKEN` secret contains whitespace (a pasted token that wrapped once broke every Claude call), and has login shells export a stripped copy so Claude keeps working until the secret is fixed
- Managed block in `~/.bash_aliases`: the token guard above, a Ghostty `TERM` fix, and the `gcmm` / `gpp` aliases
- Managed block in `~/.tmux.conf`: `mouse on` and a 50000-line scrollback, for agents that run inside tmux (a running tmux server needs `tmux source ~/.tmux.conf` once)
- Symlinks `.vimrc` to `~/.vimrc` (syntax highlighting on by default)
- `bootstrap-billing.sh` (backgrounded): installs `uv`, clones `PostHog/billing` to `~/billing`, runs `uv sync --dev`, starts the `db` and `redis` containers from `docker-compose.dev.yml`
- `install-tools.sh` (backgrounded and locked against concurrent runs): installs the latest Node 24 release, the latest Codex release from npm, and the latest native Claude Code release on every workspace start. Existing installations are updated too. Node downloads are checked against the official SHA-256 manifest.
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

## Still manual on a new box

- `~/billing/.env` from the 1Password item "Local billing environment vars", then `source .env && ./billy migrate && ./billy start`
- Codex auth ships as the `CODEX_AUTH_JSON` Coder file secret (lands at `~/.codex/auth.json`); check with `codex login status`
- Claude uses `CLAUDE_CODE_OAUTH_TOKEN`; GitHub uses `GH_TOKEN`. Renew expired credentials in Coder secrets (`hogli devbox:secret:set`), then restart the box: secrets only land at workspace start. Verify Claude with a real call (`claude -p "reply with exactly: ok"`), since a set env var proves nothing. The Codex file secret is reapplied on startup, so update it if you reauthenticate on the devbox.

## Verify a box in one shot

```bash
hogli devbox:exec -n <label> -- bash -lc '
gh api user --jq .login
git config --global --get user.signingkey | cut -c1-40
bwrap --dev-bind / / true && echo bwrap ok
codex login status
cd ~/billing && claude -p "reply with exactly: ok"
tail -1 ~/.coder-dotfiles-tools.log ~/.coder-dotfiles-billing.log ~/.coder-dotfiles-bubblewrap.log'
```

## Rules

- Keep `install.sh` idempotent: it runs on every start
- No secrets in this repo (it is public); secrets go in `hogli devbox:secret:set` / `coder secret create`
- Anything slow or network-bound gets backgrounded from `install.sh` so workspace start isn't blocked
