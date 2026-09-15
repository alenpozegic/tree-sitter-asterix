#!/usr/bin/env bash
set -euo pipefail

bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
nvim_data_home="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
nvim_site="${NVIM_SITE_DIR:-$nvim_data_home/site}"
bundle_manifest="$bundle_dir/runtime-manifest.sha256"
installed_manifest="$nvim_site/asterix-runtime-manifest.sha256"
installed_marker="$nvim_site/asterix-runtime-installed.txt"

fail() {
  echo "tree-sitter-asterix install failed: $*" >&2
  exit 1
}

is_managed_path() {
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
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_manifest() {
  local manifest="$1"
  local expected_hash
  local relative_path

  [[ -f "$manifest" ]] || fail "missing manifest $manifest"

  while read -r expected_hash relative_path; do
    [[ "$expected_hash" =~ ^[0-9a-f]{64}$ ]] \
      || fail "invalid checksum in $manifest"
    is_managed_path "$relative_path" \
      || fail "unmanaged path in $manifest: $relative_path"
  done < "$manifest"
}

validate_site_directories() {
  local directory

  for directory in \
    "$nvim_site" \
    "$nvim_site/parser" \
    "$nvim_site/queries" \
    "$nvim_site/queries/asterix" \
    "$nvim_site/ftdetect" \
    "$nvim_site/ftplugin" \
    "$nvim_site/indent" \
    "$nvim_site/after" \
    "$nvim_site/after/ftplugin" \
    "$nvim_site/after/indent" \
    "$nvim_site/lua" \
    "$nvim_site/plugin"; do
    [[ ! -L "$directory" ]] \
      || fail "refusing symlinked runtime directory: $directory"
    [[ ! -e "$directory" || -d "$directory" ]] \
      || fail "runtime directory path is not a directory: $directory"
  done
}

validate_site_path() {
  [[ "$nvim_site" == /* ]] \
    || fail "NVIM_SITE_DIR must resolve to an absolute path"
  [[ "$nvim_site" != "/" ]] \
    || fail "refusing to use the filesystem root as NVIM_SITE_DIR"
  [[ "$nvim_site" != *"/../"* && "$nvim_site" != */.. ]] \
    || fail "NVIM_SITE_DIR must not contain parent-directory traversal"
}

validate_install_metadata() {
  for metadata_file in "$installed_manifest" "$installed_marker"; do
    [[ ! -L "$metadata_file" ]] \
      || fail "refusing symlinked installer metadata: $metadata_file"
    [[ ! -e "$metadata_file" || -f "$metadata_file" ]] \
      || fail "installer metadata path is not a regular file: $metadata_file"
  done

  if [[ ! -f "$installed_manifest" && -e "$installed_marker" ]]; then
    fail "refusing to replace an unowned installer marker: $installed_marker"
  fi
}

installed_hash_for() {
  local relative_path="$1"

  awk -v path="$relative_path" '$2 == path { print $1; exit }' "$installed_manifest"
}

check_neovim_version() {
  local version_line
  local major
  local minor

  command -v nvim >/dev/null 2>&1 \
    || fail "missing nvim in PATH; install Neovim 0.10 or newer"

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

preflight_targets() {
  local expected_hash
  local relative_path
  local target
  local previous_hash
  local actual_hash
  local conflict=0

  if [[ -f "$installed_manifest" ]]; then
    validate_manifest "$installed_manifest"
  fi

  while read -r expected_hash relative_path; do
    target="$nvim_site/$relative_path"
    if [[ -L "$target" ]]; then
      echo "Refusing to replace symlink: $target" >&2
      conflict=1
      continue
    fi

    if [[ ! -e "$target" ]]; then
      continue
    fi

    if [[ ! -f "$installed_manifest" ]]; then
      echo "Refusing to replace unowned file: $target" >&2
      conflict=1
      continue
    fi

    previous_hash="$(installed_hash_for "$relative_path")"
    if [[ -z "$previous_hash" ]]; then
      echo "Refusing to replace file not owned by the previous manifest: $target" >&2
      conflict=1
      continue
    fi

    actual_hash="$(sha256sum "$target" | cut -d ' ' -f 1)"
    if [[ "$actual_hash" != "$previous_hash" ]]; then
      echo "Refusing to replace modified file: $target" >&2
      conflict=1
    fi
  done < "$bundle_manifest"

  (( conflict == 0 )) \
    || fail "resolve the reported file conflicts before installing"
}

install_runtime() {
  local expected_hash
  local relative_path
  local source
  local target
  local mode

  while read -r expected_hash relative_path; do
    source="$bundle_dir/runtime/$relative_path"
    target="$nvim_site/$relative_path"
    mode="0644"
    if [[ "$relative_path" == "parser/asterix.so" ]]; then
      mode="0755"
    fi

    mkdir -p "$(dirname -- "$target")"
    install -m "$mode" "$source" "$target"
  done < "$bundle_manifest"
}

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  fail "this bundle contains a Linux x86_64 Neovim parser binary; current platform is $(uname -s) $(uname -m)"
fi

command -v sha256sum >/dev/null 2>&1 \
  || fail "missing sha256sum in PATH"
check_neovim_version
validate_manifest "$bundle_manifest"
(
  cd "$bundle_dir/runtime"
  sha256sum --check "$bundle_manifest" >/dev/null
) || fail "bundled runtime checksum verification failed"

validate_site_path
validate_site_directories
validate_install_metadata
preflight_targets
install_runtime

mkdir -p "$nvim_site"
install -m 0644 "$bundle_manifest" "$installed_manifest"
cat > "$installed_marker" <<MARKER
tree-sitter-asterix Neovim runtime
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
bundle=$bundle_dir
parser=$nvim_site/parser/asterix.so
queries=$nvim_site/queries/asterix
MARKER

echo "Installed tree-sitter-asterix Neovim runtime:"
echo "  parser:  $nvim_site/parser/asterix.so"
echo "  queries: $nvim_site/queries/asterix"
echo "  ftdetect: $nvim_site/ftdetect/asterix.vim"
echo "  ftplugin: $nvim_site/ftplugin/asterix.lua"
echo "  indent:   $nvim_site/indent/asterix.lua"
echo "  guard:    $nvim_site/plugin/asterix.lua"
echo
echo "Run smoke test:"
echo "  $bundle_dir/smoke.sh"
