#!/usr/bin/env bash
# Codex CLI sandboxes commands with bubblewrap, which the Ubuntu 24.04 image does not ship.
# Ubuntu also leaves its AppArmor profile inactive, so a bare install still fails with
# "setting up uid map: Permission denied". Install both, then verify.
set -uo pipefail

if bwrap --dev-bind / / true 2>/dev/null; then
  echo "coder-dotfiles: bubblewrap sandbox already OK"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
# The image ships empty apt lists. The lock timeout waits out unattended-upgrades.
APT="sudo -n apt-get -qq -o DPkg::Lock::Timeout=600"
$APT update || { echo "coder-dotfiles: apt update FAILED (will retry next start)"; exit 0; }
$APT install -y bubblewrap apparmor-profiles apparmor-utils \
  || { echo "coder-dotfiles: bubblewrap install FAILED (will retry next start)"; exit 0; }

sudo -n install -m 0644 /usr/share/apparmor/extra-profiles/bwrap-userns-restrict /etc/apparmor.d/bwrap-userns-restrict \
  && sudo -n apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict \
  || { echo "coder-dotfiles: bwrap AppArmor profile FAILED (will retry next start)"; exit 0; }

if bwrap --dev-bind / / true; then
  echo "coder-dotfiles: bubblewrap sandbox OK ($(bwrap --version))"
else
  echo "coder-dotfiles: bubblewrap installed but the sandbox check still FAILS"
fi
