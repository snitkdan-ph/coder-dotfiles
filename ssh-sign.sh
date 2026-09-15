#!/usr/bin/env bash
# A long-lived T3 server may retain an SSH_AUTH_SOCK from a disconnected launch.
# Find a live, same-user forwarded agent holding the configured public key.
set -euo pipefail

if [[ " $* " != *" -Y sign "* ]]; then
  exec ssh-keygen "$@"
fi

key=$(git config --get user.signingkey)
key=${key#key::}
if [ -f "$key" ]; then
  key=$(cat "$key")
fi
key=$(printf '%s\n' "$key" | awk '{print $1 " " $2}')

has_key() {
  [ -S "$1" ] && SSH_AUTH_SOCK="$1" timeout 3 ssh-add -L 2>/dev/null |
    awk '{print $1 " " $2}' | grep -Fxq "$key"
}

if [ -n "${SSH_AUTH_SOCK:-}" ] && has_key "$SSH_AUTH_SOCK"; then
  exec ssh-keygen "$@"
fi

while IFS= read -r socket; do
  if has_key "$socket"; then
    export SSH_AUTH_SOCK="$socket"
    exec ssh-keygen "$@"
  fi
done < <(find /tmp -maxdepth 2 -type s -user "$(id -un)" \
  \( -path '/tmp/auth-agent*/listener.sock' -o -path '/tmp/ssh-*/agent.*' \) 2>/dev/null)

echo "Signing key unavailable. Connect through T3 SSH or ssh -A, and unlock 1Password on your Mac." >&2
exit 1
