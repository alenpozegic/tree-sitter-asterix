#!/usr/bin/env bash
set -euo pipefail

bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
nvim_data_home="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
nvim_site="${NVIM_SITE_DIR:-$nvim_data_home/site}"
bundle_manifest="$bundle_dir/runtime-manifest.sha256"
installed_manifest="$nvim_site/asterix-spec-runtime-manifest.sha256"
installed_marker="$nvim_site/asterix-spec-runtime-installed.txt"
legacy_manifest="$nvim_site/asterix-runtime-manifest.sha256"
legacy_marker="$nvim_site/asterix-runtime-installed.txt"
legacy_upgrade=0

legacy_paths=(
  "parser/asterix.so"
  "queries/asterix/highlights.scm"
  "queries/asterix/folds.scm"
  "queries/asterix/indents.scm"
  "queries/asterix/locals.scm"
  "queries/asterix/tags.scm"
  "ftdetect/asterix.vim"
  "ftplugin/asterix.lua"
  "indent/asterix.lua"
  "after/ftplugin/asterix.lua"
  "after/indent/asterix.lua"
  "lua/asterix_indent.lua"
  "lua/asterix_runtime.lua"
  "plugin/asterix.lua"
)

fail() {
  echo "tree-sitter-asterix install failed: $*" >&2
  exit 1
}

is_current_managed_path() {
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

is_legacy_managed_path() {
  case "$1" in
    parser/asterix.so \
      | queries/asterix/highlights.scm \
      | queries/asterix/folds.scm \
      | queries/asterix/indents.scm \
      | queries/asterix/locals.scm \
      | queries/asterix/tags.scm \
      | ftdetect/asterix.vim \
      | ftplugin/asterix.lua \
      | indent/asterix.lua \
      | after/ftplugin/asterix.lua \
      | after/indent/asterix.lua \
      | lua/asterix_indent.lua \
      | lua/asterix_runtime.lua \
      | plugin/asterix.lua)
      return 0 ;;
    *) return 1 ;;
  esac
}

validate_manifest() {
  local manifest="$1"
  local kind="$2"
  local expected_hash relative_path
  local -A seen=()

  [[ -f "$manifest" ]] || fail "missing manifest $manifest"
  while read -r expected_hash relative_path; do
    [[ "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || fail "invalid checksum in $manifest"
    [[ -n "$relative_path" ]] || fail "missing path in $manifest"
    [[ -z "${seen[$relative_path]+x}" ]] || fail "duplicate path in $manifest: $relative_path"
    seen["$relative_path"]=1
    if [[ "$kind" == "current" ]]; then
      is_current_managed_path "$relative_path" || fail "unmanaged current path in $manifest: $relative_path"
    else
      is_legacy_managed_path "$relative_path" || fail "unmanaged legacy path in $manifest: $relative_path"
    fi
  done < "$manifest"
}

manifest_hash_for() {
  local manifest="$1"
  local relative_path="$2"
  awk -v path="$relative_path" '$2 == path { print $1; exit }' "$manifest"
}

validate_site_path() {
  [[ "$nvim_site" == /* ]] || fail "NVIM_SITE_DIR must resolve to an absolute path"
  [[ "$nvim_site" != "/" ]] || fail "refusing to use the filesystem root as NVIM_SITE_DIR"
  [[ "$nvim_site" != *"/../"* && "$nvim_site" != */.. ]] || fail "NVIM_SITE_DIR must not contain parent-directory traversal"
}

validate_site_directories() {
  local directory
  for directory in \
    "$nvim_site" \
    "$nvim_site/parser" \
    "$nvim_site/queries" \
    "$nvim_site/queries/asterix_spec" \
    "$nvim_site/queries/asterix" \
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
    [[ ! -L "$directory" ]] || fail "refusing symlinked runtime directory: $directory"
    [[ ! -e "$directory" || -d "$directory" ]] || fail "runtime directory path is not a directory: $directory"
  done
}

validate_metadata_paths() {
  local metadata_file
  for metadata_file in "$installed_manifest" "$installed_marker" "$legacy_manifest" "$legacy_marker"; do
    [[ ! -L "$metadata_file" ]] || fail "refusing symlinked installer metadata: $metadata_file"
    [[ ! -e "$metadata_file" || -f "$metadata_file" ]] || fail "installer metadata path is not a regular file: $metadata_file"
  done

  if [[ ! -f "$installed_manifest" && -e "$installed_marker" ]]; then
    fail "refusing current installer marker without ownership manifest"
  fi
  if [[ ! -f "$legacy_manifest" && -e "$legacy_marker" ]]; then
    fail "refusing legacy installer marker without ownership manifest"
  fi
}

check_neovim_version() {
  local version_line major minor
  command -v nvim >/dev/null 2>&1 || fail "missing nvim in PATH; install Neovim 0.10 or newer"
  version_line="$(nvim --version | head -n 1)"
  if [[ ! "$version_line" =~ ^NVIM[[:space:]]v([0-9]+)\.([0-9]+)(\.[0-9]+)? ]]; then
    fail "cannot parse Neovim version from: $version_line"
  fi
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  if (( major == 0 && minor < 10 )); then
    fail "Neovim 0.10 or newer is required; found $version_line"
  fi
}

preflight_current_targets() {
  local expected_hash relative_path target previous_hash actual_hash
  local conflict=0

  if [[ -f "$installed_manifest" ]]; then
    validate_manifest "$installed_manifest" current
  fi

  while read -r expected_hash relative_path; do
    target="$nvim_site/$relative_path"
    if [[ -L "$target" ]]; then
      echo "Refusing to replace symlink: $target" >&2
      conflict=1
      continue
    fi
    [[ -e "$target" ]] || continue

    if [[ ! -f "$installed_manifest" ]]; then
      echo "Refusing to replace unowned file: $target" >&2
      conflict=1
      continue
    fi

    previous_hash="$(manifest_hash_for "$installed_manifest" "$relative_path")"
    if [[ -z "$previous_hash" ]]; then
      echo "Refusing to replace file not owned by the current manifest: $target" >&2
      conflict=1
      continue
    fi

    actual_hash="$(sha256sum "$target" | cut -d ' ' -f 1)"
    if [[ "$actual_hash" != "$previous_hash" ]]; then
      echo "Refusing to replace modified file: $target" >&2
      conflict=1
    fi
  done < "$bundle_manifest"

  (( conflict == 0 )) || fail "resolve the reported current-runtime conflicts before installing"
}

legacy_state_present() {
  local path
  [[ -e "$legacy_manifest" || -L "$legacy_manifest" || -e "$legacy_marker" || -L "$legacy_marker" ]] && return 0
  for path in "${legacy_paths[@]}"; do
    [[ -e "$nvim_site/$path" || -L "$nvim_site/$path" ]] && return 0
  done
  return 1
}

preflight_legacy_upgrade() {
  local path target expected_hash actual_hash relative
  local manifest_count

  legacy_state_present || return 0

  [[ ! -e "$installed_manifest" && ! -L "$installed_manifest" && ! -e "$installed_marker" && ! -L "$installed_marker" ]] \
    || fail "refusing ambiguous install containing both current and legacy ownership metadata"

  [[ -f "$legacy_manifest" ]] || fail "legacy runtime detected without the 0.1.0 ownership manifest"
  [[ -f "$legacy_marker" ]] || fail "legacy runtime detected without the 0.1.0 install marker"
  validate_manifest "$legacy_manifest" legacy

  manifest_count="$(wc -l < "$legacy_manifest")"
  [[ "$manifest_count" -eq "${#legacy_paths[@]}" ]] \
    || fail "legacy ownership manifest is not the exact 0.1.0 managed path set"

  for path in "${legacy_paths[@]}"; do
    expected_hash="$(manifest_hash_for "$legacy_manifest" "$path")"
    [[ -n "$expected_hash" ]] || fail "legacy manifest does not own required 0.1.0 path: $path"
    target="$nvim_site/$path"
    [[ ! -L "$target" ]] || fail "refusing symlinked legacy managed file: $target"
    [[ -f "$target" ]] || fail "legacy manifest path is missing or not a regular file: $target"
    actual_hash="$(sha256sum "$target" | cut -d ' ' -f 1)"
    [[ "$actual_hash" == "$expected_hash" ]] \
      || fail "legacy managed file was modified: $target"
  done

  [[ "$(head -n 1 "$legacy_marker")" == "tree-sitter-asterix Neovim runtime" ]] \
    || fail "legacy install marker is not recognized as the 0.1.0 tree-sitter-asterix runtime"

  if [[ -d "$nvim_site/queries/asterix" ]]; then
    while IFS= read -r relative; do
      path="queries/asterix/$relative"
      is_legacy_managed_path "$path" \
        || fail "foreign file or directory exists inside legacy query runtime: $path"
    done < <(cd "$nvim_site/queries/asterix" && find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort)
  fi

  legacy_upgrade=1
}

remove_legacy_runtime() {
  local path
  (( legacy_upgrade == 1 )) || return 0

  for path in "${legacy_paths[@]}"; do
    rm -f -- "$nvim_site/$path"
  done
  rm -f -- "$legacy_manifest" "$legacy_marker"
  rmdir "$nvim_site/queries/asterix" 2>/dev/null || true
}

install_runtime() {
  local expected_hash relative_path source target mode
  while read -r expected_hash relative_path; do
    source="$bundle_dir/runtime/$relative_path"
    target="$nvim_site/$relative_path"
    mode="0644"
    [[ "$relative_path" == "parser/asterix_spec.so" ]] && mode="0755"
    mkdir -p "$(dirname -- "$target")"
    install -m "$mode" "$source" "$target"
  done < "$bundle_manifest"
}

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  fail "this bundle contains a Linux x86_64 Neovim parser binary; current platform is $(uname -s) $(uname -m)"
fi
command -v sha256sum >/dev/null 2>&1 || fail "missing sha256sum in PATH"
check_neovim_version
validate_manifest "$bundle_manifest" current
(
  cd "$bundle_dir/runtime"
  sha256sum --check "$bundle_manifest" >/dev/null
) || fail "bundled runtime checksum verification failed"

validate_site_path
validate_site_directories
validate_metadata_paths
preflight_current_targets
preflight_legacy_upgrade

remove_legacy_runtime
install_runtime

mkdir -p "$nvim_site"
install -m 0644 "$bundle_manifest" "$installed_manifest"
cat > "$installed_marker" <<MARKER
tree-sitter-asterix Neovim runtime
language=asterix-spec
parser_id=asterix_spec
parser=$nvim_site/parser/asterix_spec.so
queries=$nvim_site/queries/asterix_spec
MARKER

echo "Installed tree-sitter-asterix Neovim runtime:"
echo "  language: asterix-spec"
echo "  parser:   $nvim_site/parser/asterix_spec.so"
echo "  queries:  $nvim_site/queries/asterix_spec"
echo "  ftdetect: $nvim_site/ftdetect/asterix-spec.vim"
echo "  ftplugin: $nvim_site/ftplugin/asterix-spec.lua"
echo "  indent:   $nvim_site/indent/asterix-spec.lua"
echo "  guard:    $nvim_site/plugin/asterix_spec.lua"
echo
echo "Run smoke test:"
echo "  $bundle_dir/smoke.sh"
