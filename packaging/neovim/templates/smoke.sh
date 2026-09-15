#!/usr/bin/env bash
set -euo pipefail

bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
sample_file="${1:-$bundle_dir/samples/basic.ast}"

if ! command -v nvim >/dev/null 2>&1; then
  echo "Missing nvim in PATH. Install Neovim 0.10 or newer." >&2
  exit 1
fi

nvim --headless "$sample_file" +"luafile $bundle_dir/smoke/smoke.lua"
nvim --headless "$sample_file" +"luafile $bundle_dir/smoke/guard-smoke.lua"
