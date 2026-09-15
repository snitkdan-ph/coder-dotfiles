#!/usr/bin/env bash
# Applied by Coder on every devbox start (registered via `hogli devbox:setup --configure-dotfiles`).
# Must stay idempotent. Anything slow or network-bound is backgrounded so workspace start isn't blocked.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Coder runs dotfiles before the login-shell PATH exists.
export PATH="$HOME/.local/bin:$PATH"

# --- GitHub: make git over HTTPS non-interactive ---
# The template sets GIT_ASKPASS to Coder's external-auth helper, which can hang when that
# auth isn't linked. Registering gh as the credential helper makes git use GH_TOKEN instead.
if command -v gh >/dev/null 2>&1 && [ -n "${GH_TOKEN:-}" ]; then
  gh auth setup-git >/dev/null 2>&1 || echo "coder-dotfiles: gh auth setup-git FAILED"
fi

# --- Commit signing safety net ---
# The template configures signing from POSTHOG_GIT_SIGNING_KEY at boot, but its bootstrap can
# race and leave the box unsigned. Reapply if that happened. No-op when the secret is unset.
if [ -n "${POSTHOG_GIT_SIGNING_KEY:-}" ] && [ "$(git config --global --get commit.gpgsign || true)" != "true" ]; then
  git config --global gpg.format ssh
  git config --global user.signingkey "key::${POSTHOG_GIT_SIGNING_KEY#key::}"
  git config --global commit.gpgsign true
  git config --global tag.gpgsign true
  echo "coder-dotfiles: reapplied git signing config"
fi

# --- vim ---
# Coder skips its own dotfile symlinking when install.sh exists, so link .vimrc ourselves.
ln -sfn "$SCRIPT_DIR/.vimrc" "$HOME/.vimrc"

# --- Background work (logs in ~) ---
nohup bash "$SCRIPT_DIR/bootstrap-billing.sh" >> "$HOME/.coder-dotfiles-billing.log" 2>&1 &
nohup bash "$SCRIPT_DIR/install-codex.sh"     >> "$HOME/.coder-dotfiles-codex.log"   2>&1 &

echo "coder-dotfiles: install.sh done (billing -> ~/.coder-dotfiles-billing.log, codex -> ~/.coder-dotfiles-codex.log)"
