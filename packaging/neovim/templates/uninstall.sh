#!/usr/bin/env bash
set -euo pipefail

nvim_data_home="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
nvim_site="${NVIM_SITE_DIR:-$nvim_data_home/site}"
installed_manifest="$nvim_site/asterix-spec-runtime-manifest.sha256"
installed_marker="$nvim_site/asterix-spec-runtime-installed.txt"

fail() {
  echo "tree-sitter-asterix uninstall failed: $*" >&2
  exit 1
}

is_managed_path() {
  case "$1" in
    parser/asterix_spec.so \
      | queries/asterix_spec/highlights.scm \
      | queries/asterix_spec/folds.scm \
      | queries/asterix_spec/indents.scm \
      | queries/asterix_spec/locals.scm \
      | queries/asterix_spec/tags.scm \
      | ftdetect/asterix-spec.vim \
      | ftplugin/asterix-spec.lua \
      | indent/asterix-spec.lua \
      | after/ftplugin/asterix-spec.lua \
      | after/indent/asterix-spec.lua \
      | after/queries/markdown/injections.scm \
      | lua/asterix_spec_indent.lua \
      | lua/asterix_spec_runtime.lua \
      | plugin/asterix_spec.lua)
      return 0 ;;
    *) return 1 ;;
  esac
}

validate_site_path() {
  [[ "$nvim_site" == /* ]] || fail "NVIM_SITE_DIR must resolve to an absolute path; no files were removed"
  [[ "$nvim_site" != "/" ]] || fail "refusing to use the filesystem root as NVIM_SITE_DIR; no files were removed"
  [[ "$nvim_site" != *"/../"* && "$nvim_site" != */.. ]] || fail "NVIM_SITE_DIR must not contain parent-directory traversal; no files were removed"
}

validate_site_directories() {
  local directory
  for directory in \
    "$nvim_site" \
    "$nvim_site/parser" \
    "$nvim_site/queries" \
    "$nvim_site/queries/asterix_spec" \
    "$nvim_site/ftdetect" \
    "$nvim_site/ftplugin" \
    "$nvim_site/indent" \
    "$nvim_site/after" \
    "$nvim_site/after/ftplugin" \
    "$nvim_site/after/indent" \
    "$nvim_site/after/queries" \
    "$nvim_site/after/queries/markdown" \
    "$nvim_site/lua" \
    "$nvim_site/plugin"; do
    [[ ! -L "$directory" ]] || fail "refusing symlinked runtime directory: $directory; no files were removed"
    [[ ! -e "$directory" || -d "$directory" ]] || fail "runtime directory path is not a directory: $directory; no files were removed"
  done
}

validate_metadata() {
  [[ ! -L "$installed_manifest" ]] || fail "refusing symlinked ownership manifest; no files were removed"
  [[ ! -L "$installed_marker" ]] || fail "refusing symlinked installer marker; no files were removed"
  [[ -f "$installed_manifest" ]] || fail "ownership manifest is missing; no files were removed"
  [[ ! -e "$installed_marker" || -f "$installed_marker" ]] || fail "installer marker is not a regular file; no files were removed"
}

validate_manifest() {
  local expected_hash relative_path
  local -A seen=()
  while read -r expected_hash relative_path; do
    [[ "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || fail "invalid checksum in ownership manifest; no files were removed"
    is_managed_path "$relative_path" || fail "unmanaged path in ownership manifest: $relative_path; no files were removed"
    [[ -z "${seen[$relative_path]+x}" ]] || fail "duplicate path in ownership manifest: $relative_path; no files were removed"
    seen["$relative_path"]=1
  done < "$installed_manifest"
}

command -v sha256sum >/dev/null 2>&1 || fail "missing sha256sum in PATH"
validate_site_path
validate_site_directories
validate_metadata
validate_manifest

remaining_manifest="$(mktemp "$nvim_site/.asterix-spec-runtime-manifest.XXXXXX")"
cleanup() { rm -f "$remaining_manifest"; }
trap cleanup EXIT

preserved=0
while read -r expected_hash relative_path; do
  target="$nvim_site/$relative_path"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    continue
  fi
  if [[ -L "$target" ]]; then
    echo "Preserving symlink not created by this installer: $target" >&2
    printf '%s  %s\n' "$expected_hash" "$relative_path" >> "$remaining_manifest"
    preserved=1
    continue
  fi

  actual_hash="$(sha256sum "$target" | cut -d ' ' -f 1)"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "Preserving modified file: $target" >&2
    printf '%s  %s\n' "$expected_hash" "$relative_path" >> "$remaining_manifest"
    preserved=1
    continue
  fi
  rm -f -- "$target"
done < "$installed_manifest"

for directory in \
  "$nvim_site/queries/asterix_spec" \
  "$nvim_site/after/queries/markdown" \
  "$nvim_site/after/queries" \
  "$nvim_site/after/ftplugin" \
  "$nvim_site/after/indent" \
  "$nvim_site/after" \
  "$nvim_site/parser" \
  "$nvim_site/ftdetect" \
  "$nvim_site/ftplugin" \
  "$nvim_site/indent" \
  "$nvim_site/lua" \
  "$nvim_site/plugin"; do
  rmdir "$directory" 2>/dev/null || true
done

if (( preserved != 0 )); then
  install -m 0644 "$remaining_manifest" "$installed_manifest"
  fail "modified or foreign files were preserved; review them and rerun uninstall"
fi

rm -f -- "$installed_manifest" "$installed_marker"
echo "Removed tree-sitter-asterix Neovim asterix-spec runtime from $nvim_site"
