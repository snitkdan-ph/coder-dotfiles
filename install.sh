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
else
  echo "coder-dotfiles: gh missing or GH_TOKEN secret unset; HTTPS git will prompt"
fi

# --- Commit signing safety net ---
# The template configures signing from POSTHOG_GIT_SIGNING_KEY at boot, but its bootstrap can
# race and leave the box unsigned. Reapply if that happened. No-op when the secret is unset.
if [ -n "${POSTHOG_GIT_SIGNING_KEY:-}" ]; then
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$SCRIPT_DIR/ssh-sign.sh" "$HOME/.local/bin/devbox-ssh-sign"
  git config --global gpg.format ssh
  git config --global gpg.ssh.program "$HOME/.local/bin/devbox-ssh-sign"
  git config --global user.signingkey "key::${POSTHOG_GIT_SIGNING_KEY#key::}"
  git config --global commit.gpgsign true
  git config --global tag.gpgsign true
  # Verification needs an allowed-signers file; without it `git log --show-signature` reports N for our own commits.
  mkdir -p "$HOME/.config/git"
  printf '%s namespaces="git" %s\n' "$(git config --global --get user.email || echo daniel.s@posthog.com)" "${POSTHOG_GIT_SIGNING_KEY#key::}" > "$HOME/.config/git/allowed_signers"
  git config --global gpg.ssh.allowedSignersFile "$HOME/.config/git/allowed_signers"
  echo "coder-dotfiles: reapplied git signing config"
else
  echo "coder-dotfiles: POSTHOG_GIT_SIGNING_KEY secret unset; commits will not be signed"
fi

# --- Claude Code token hygiene ---
# A token pasted into `hogli devbox:setup --configure-claude` from a wrapped terminal line once
# landed in the secret with a line break in the middle. Claude then fails every call with
# "Invalid Authorization header value ... contains a line break". Flag it loudly here, and have
# login shells export a whitespace-stripped copy so the box still works until the secret is fixed.
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ "$(printf %s "$CLAUDE_CODE_OAUTH_TOKEN" | tr -d '[:space:]')" != "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  echo "coder-dotfiles: WARNING CLAUDE_CODE_OAUTH_TOKEN contains whitespace; fix the secret (claude setup-token + hogli devbox:setup --configure-claude)"
fi

# --- Shell (managed block in ~/.bash_aliases, which Ubuntu's ~/.bashrc sources) ---
# Rewritten on every start so changes here reach existing boxes; anything outside the markers is kept.
touch "$HOME/.bash_aliases"
sed -i '/# >>> coder-dotfiles >>>/,/# <<< coder-dotfiles <<</d' "$HOME/.bash_aliases"
cat >> "$HOME/.bash_aliases" <<'BLOCK'
# >>> coder-dotfiles >>>
# Strip stray whitespace from the Claude token secret (see install.sh "token hygiene").
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  export CLAUDE_CODE_OAUTH_TOKEN="$(printf %s "$CLAUDE_CODE_OAUTH_TOKEN" | tr -d '[:space:]')"
fi
# Shells spawned by T3 Code's remote server (and tmux) inherit no SSH_AUTH_SOCK even though the
# SSH tunnel forwards the Mac's agent. Adopt the newest live forwarded socket so ssh-add, git over
# SSH and signing all just work. devbox-ssh-sign does its own search, so signing never depended on this.
if ! { [ -S "${SSH_AUTH_SOCK:-}" ] && SSH_AUTH_SOCK="$SSH_AUTH_SOCK" timeout 2 ssh-add -l >/dev/null 2>&1; }; then
  for _sock in $(ls -t /tmp/auth-agent*/listener.sock /tmp/ssh-*/agent.* 2>/dev/null); do
    if [ -O "$_sock" ] && SSH_AUTH_SOCK="$_sock" timeout 2 ssh-add -l >/dev/null 2>&1; then
      export SSH_AUTH_SOCK="$_sock"; break
    fi
  done
  unset _sock
fi
# Ghostty's TERM has no terminfo on the box, which breaks clear/less/vim.
[ "${TERM:-}" = xterm-ghostty ] && export TERM=xterm-256color
alias gcmm='git checkout main'
alias gpp='git pull'
# <<< coder-dotfiles <<<
BLOCK

# --- tmux (managed block) ---
# Agents run inside tmux to survive a laptop sleep; the defaults have no mouse scrolling and a 2000-line scrollback.
if ! grep -q '# >>> coder-dotfiles >>>' "$HOME/.tmux.conf" 2>/dev/null; then
  cat >> "$HOME/.tmux.conf" <<'BLOCK'
# >>> coder-dotfiles >>>
set -g mouse on
set -g history-limit 50000
# <<< coder-dotfiles <<<
BLOCK
fi

# --- vim ---
# Coder skips its own dotfile symlinking when install.sh exists, so link .vimrc ourselves.
ln -sfn "$SCRIPT_DIR/.vimrc" "$HOME/.vimrc"

# --- Background work (logs in ~) ---
nohup bash "$SCRIPT_DIR/bootstrap-billing.sh"  >> "$HOME/.coder-dotfiles-billing.log"    2>&1 &
billing_pid=$!
nohup bash "$SCRIPT_DIR/install-tools.sh"      >> "$HOME/.coder-dotfiles-tools.log"      2>&1 &
tools_pid=$!
nohup bash "$SCRIPT_DIR/install-bubblewrap.sh" >> "$HOME/.coder-dotfiles-bubblewrap.log" 2>&1 &
bubblewrap_pid=$!

echo "coder-dotfiles: install.sh done (billing -> ~/.coder-dotfiles-billing.log, tools -> ~/.coder-dotfiles-tools.log, bubblewrap -> ~/.coder-dotfiles-bubblewrap.log)"
if [ "${1:-}" = "--wait" ]; then
  result=0
  wait "$billing_pid" || result=1
  wait "$tools_pid" || result=1
  wait "$bubblewrap_pid" || result=1
  exit "$result"
fi
