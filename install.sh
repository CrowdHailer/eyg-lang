#!/usr/bin/env bash

set -euo pipefail

# Self-contained installer for the eyg CLI.
#
# Downloads a prebuilt binary for the host platform from the GitHub
# releases, verifies its checksum and installs it onto your PATH.
#
# Run it directly:
#
#   curl -fsSL https://raw.githubusercontent.com/CrowdHailer/eyg-lang/main/install.sh | bash
#
# Or install a specific release:
#
#   curl -fsSL https://raw.githubusercontent.com/CrowdHailer/eyg-lang/main/install.sh | bash -s -- gleam_cli-v0.0.0

REPO="CrowdHailer/eyg-lang"
VERSION="${1:-latest}"
install_dir="$HOME/.local/bin"

if [ "$#" -gt 1 ]; then
  echo "usage: install.sh [release-tag]" >&2
  exit 1
fi

# Detect the host platform and map it to a release asset name.
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Linux) os_name="linux" ;;
  Darwin) os_name="macos" ;;
  *) echo "unsupported operating system: $os" >&2; exit 1 ;;
esac
case "$arch" in
  x86_64 | amd64) arch_name="x64" ;;
  aarch64 | arm64) arch_name="arm64" ;;
  *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
esac

if [ "$os_name" = "macos" ] && [ "$arch_name" = "x64" ]; then
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    arch_name="arm64"
  fi
fi

asset="eyg-${os_name}-${arch_name}"

if [ "$VERSION" = "latest" ]; then
  base="https://github.com/$REPO/releases/latest/download"
else
  base="https://github.com/$REPO/releases/download/$VERSION"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "downloading $asset from $base"
curl -fsSL "$base/$asset" -o "$tmp/$asset"
curl -fsSL "$base/SHA256SUMS" -o "$tmp/SHA256SUMS"

# sha256sum on Linux, shasum on macOS.
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
fi
expected="$(awk -v f="$asset" '$2 == f {print $1}' "$tmp/SHA256SUMS")"

if [ -z "$expected" ]; then
  echo "no checksum listed for $asset" >&2
  exit 1
fi
if [ "$expected" != "$actual" ]; then
  echo "checksum mismatch for $asset" >&2
  echo "  expected $expected" >&2
  echo "  actual   $actual" >&2
  exit 1
fi
echo "checksum verified"

chmod +x "$tmp/$asset"

if ! mkdir -p "$install_dir"; then
  echo "could not create install directory: $install_dir" >&2
  exit 1
fi
if [ ! -w "$install_dir" ]; then
  echo "install directory is not writable: $install_dir" >&2
  exit 1
fi
mv "$tmp/$asset" "$install_dir/eyg"

echo "installed eyg to $install_dir/eyg"
case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    shell_name="$(basename "${SHELL:-}")"
    echo
    echo "$install_dir is not on your PATH."
    case "$shell_name" in
      fish)
        echo "Add it for fish with:"
        echo "  fish_add_path $install_dir"
        ;;
      zsh)
        echo "Add it for zsh with:"
        echo "  echo 'export PATH=\"$install_dir:\$PATH\"' >> ~/.zshrc"
        echo "  exec zsh"
        ;;
      *)
        echo "Add it for bash/sh with:"
        echo "  echo 'export PATH=\"$install_dir:\$PATH\"' >> ~/.profile"
        echo "  . ~/.profile"
        ;;
    esac
    ;;
esac
