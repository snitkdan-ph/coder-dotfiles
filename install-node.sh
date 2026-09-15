#!/usr/bin/env bash
# Install the latest Node 24 release outside Flox so T3's SSH launcher can find it.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

case "$(uname -m)" in
  x86_64) arch=x64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "Unsupported Node architecture: $(uname -m)" >&2; exit 1 ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base_url=https://nodejs.org/dist/latest-v24.x
curl --fail --silent --show-error --location --retry 3 "$base_url/SHASUMS256.txt" -o "$tmp/SHASUMS256.txt"
archive=$(awk -v arch="$arch" '$2 ~ "^node-v24\\.[0-9]+\\.[0-9]+-linux-" arch "\\.tar\\.xz$" {print $2}' "$tmp/SHASUMS256.txt")
test -n "$archive"
destination="$HOME/.local/opt/${archive%.tar.xz}"

if [ ! -x "$destination/bin/node" ]; then
  curl --fail --silent --show-error --location --retry 3 "$base_url/$archive" -o "$tmp/$archive"
  (cd "$tmp"; awk -v archive="$archive" '$2 == archive' SHASUMS256.txt | sha256sum -c -)
  tar -xJf "$tmp/$archive" -C "$tmp"
  mkdir -p "$HOME/.local/opt"
  mv "$tmp/${archive%.tar.xz}" "$destination"
fi

mkdir -p "$HOME/.local/bin"
for tool in node npm npx; do
  ln -sfn "$destination/bin/$tool" "$HOME/.local/bin/$tool"
done
node --version
