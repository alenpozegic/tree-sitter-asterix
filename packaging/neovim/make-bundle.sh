#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
grammar_dir="$repo_root"
editor_dir="$repo_root/editors/neovim"
templates_dir="$script_dir/templates"
dist_dir="$repo_root/dist"
build_dir="$grammar_dir/.bundle-build/neovim"
generated_dir="$build_dir/generated-abi14"
tree_sitter_cli="$grammar_dir/node_modules/tree-sitter-cli/tree-sitter"
bundle_cc="${ASTERIX_CC:-cc}"
abi="14"
platform="linux-x86_64"
allow_dirty="${ASTERIX_ALLOW_DIRTY:-0}"

fail() {
  echo "tree-sitter-asterix bundle build failed: $*" >&2
  exit 1
}

for command in node npm sha256sum tar gzip git readelf; do
  command -v "$command" >/dev/null 2>&1 \
    || fail "missing $command in PATH"
done
command -v "$bundle_cc" >/dev/null 2>&1 \
  || fail "missing configured C compiler in PATH: $bundle_cc"

if [[ "$allow_dirty" != "0" && "$allow_dirty" != "1" ]]; then
  fail "ASTERIX_ALLOW_DIRTY must be 0 or 1"
fi

version="${ASTERIX_BUNDLE_VERSION:-$(node -p "require('$grammar_dir/package.json').version")}"
if [[ ! "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]]; then
  fail "invalid bundle version: $version"
fi

bundle_name="tree-sitter-asterix-neovim-${platform}-v${version}"
staging_dir="$dist_dir/$bundle_name"
archive_path="$dist_dir/${bundle_name}.tar.gz"
checksum_path="$archive_path.sha256"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  fail "this builder targets Linux x86_64; current platform is $(uname -s) $(uname -m)"
fi

[[ -x "$tree_sitter_cli" ]] \
  || fail "missing project-local tree-sitter CLI; run npm ci in $grammar_dir first"

for template in install.sh uninstall.sh smoke.sh; do
  [[ -f "$templates_dir/$template" ]] \
    || fail "missing bundle template: $templates_dir/$template"
done
[[ -f "$repo_root/examples/basic.ast" ]] \
  || fail "missing public smoke sample: $repo_root/examples/basic.ast"

if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  source_commit="$(git -C "$repo_root" rev-parse HEAD)"
  source_date_epoch="${ASTERIX_SOURCE_DATE_EPOCH:-$(git -C "$repo_root" log -1 --format=%ct)}"
  if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    source_state="modified"
  else
    source_state="clean"
  fi
else
  source_commit="unavailable"
  source_date_epoch="${ASTERIX_SOURCE_DATE_EPOCH:-0}"
  source_state="unversioned"
fi

if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  fail "ASTERIX_SOURCE_DATE_EPOCH must be a non-negative integer"
fi

if [[ "$source_state" != "clean" && "$allow_dirty" != "1" ]]; then
  fail "source state is $source_state; commit the reviewed source or set ASTERIX_ALLOW_DIRTY=1 for a non-release test build"
fi

build_timestamp="$(date --utc --date="@$source_date_epoch" +"%Y-%m-%dT%H:%M:%SZ")"

rm -rf "$build_dir" "$staging_dir" "$archive_path" "$checksum_path"
mkdir -p \
  "$generated_dir" \
  "$staging_dir/runtime/parser" \
  "$staging_dir/runtime/queries/asterix_spec" \
  "$staging_dir/runtime/ftdetect" \
  "$staging_dir/runtime/ftplugin" \
  "$staging_dir/runtime/indent" \
  "$staging_dir/runtime/after/ftplugin" \
  "$staging_dir/runtime/after/indent" \
  "$staging_dir/runtime/after/queries/markdown" \
  "$staging_dir/runtime/lua" \
  "$staging_dir/runtime/plugin" \
  "$staging_dir/samples" \
  "$staging_dir/smoke"

"$tree_sitter_cli" generate --abi "$abi" --output "$generated_dir" "$grammar_dir/grammar.js"

"$bundle_cc" -fPIC -I"$generated_dir" -I"$grammar_dir/src" -c "$generated_dir/parser.c" -o "$build_dir/parser.o"
"$bundle_cc" -fPIC -I"$generated_dir" -I"$grammar_dir/src" -c "$grammar_dir/src/scanner.c" -o "$build_dir/scanner.o"
"$bundle_cc" -shared "$build_dir/parser.o" "$build_dir/scanner.o" -o "$staging_dir/runtime/parser/asterix_spec.so"

parser_dynamic_section="$(readelf -d "$staging_dir/runtime/parser/asterix_spec.so")"
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$parser_dynamic_section"; then
  fail "parser contains an embedded RPATH or RUNPATH; select a portable compiler with ASTERIX_CC"
fi
while IFS= read -r needed_library; do
  [[ "$needed_library" == "libc.so.6" ]] \
    || fail "parser has an unexpected runtime dependency: $needed_library"
done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' <<< "$parser_dynamic_section")

mapfile -t parser_glibc_symbols < <(
  readelf --version-info "$staging_dir/runtime/parser/asterix_spec.so" \
    | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)*' \
    | LC_ALL=C sort -Vu
)
if (( ${#parser_glibc_symbols[@]} == 0 )); then
  parser_glibc_symbol_versions="none"
  maximum_required_glibc_symbol="none"
else
  parser_glibc_symbol_versions="$(IFS=,; echo "${parser_glibc_symbols[*]}")"
  maximum_required_glibc_symbol="${parser_glibc_symbols[$((${#parser_glibc_symbols[@]} - 1))]}"
fi

for query in highlights folds indents locals tags; do
  cp "$grammar_dir/queries/$query.scm" "$staging_dir/runtime/queries/asterix_spec/$query.scm"
done

cat > "$staging_dir/runtime/ftdetect/asterix-spec.vim" <<'EOF'
augroup tree_sitter_asterix_spec_filetype
  autocmd!
  autocmd BufRead,BufNewFile *.ast setfiletype asterix-spec
augroup END
EOF

cat > "$staging_dir/runtime/ftplugin/asterix-spec.lua" <<'EOF'
vim.bo.commentstring = "// %s"
vim.bo.comments = "://"
vim.bo.shiftwidth = 4
vim.bo.softtabstop = 4
vim.bo.tabstop = 4
vim.bo.expandtab = true

pcall(vim.treesitter.language.register, "asterix_spec", "asterix-spec")
pcall(vim.treesitter.start, 0, "asterix_spec")

vim.wo.foldmethod = "expr"
vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.wo.foldlevel = 99
vim.o.foldlevelstart = 99
EOF

cp "$editor_dir/indent/asterix-spec.lua" "$staging_dir/runtime/lua/asterix_spec_indent.lua"
cp "$editor_dir/lua/asterix_spec_runtime.lua" "$staging_dir/runtime/lua/asterix_spec_runtime.lua"
cp "$editor_dir/plugin/asterix_spec.lua" "$staging_dir/runtime/plugin/asterix_spec.lua"
cp "$editor_dir/after/ftplugin/asterix-spec.lua" "$staging_dir/runtime/after/ftplugin/asterix-spec.lua"
cp "$editor_dir/after/indent/asterix-spec.lua" "$staging_dir/runtime/after/indent/asterix-spec.lua"
cp "$editor_dir/after/queries/markdown/injections.scm" "$staging_dir/runtime/after/queries/markdown/injections.scm"

cat > "$staging_dir/runtime/indent/asterix-spec.lua" <<'EOF'
require("asterix_spec_runtime").apply_indent(0)
EOF

(
  cd "$staging_dir/runtime"
  while IFS= read -r -d '' runtime_file; do
    sha256sum "$runtime_file"
  done < <(find . -type f -print0 | LC_ALL=C sort -z)
) | sed 's#  \./#  #' > "$staging_dir/runtime-manifest.sha256"

cp "$editor_dir/smoke.lua" "$staging_dir/smoke/smoke.lua"
cp "$editor_dir/guard-smoke.lua" "$staging_dir/smoke/guard-smoke.lua"
cp "$script_dir/markdown-injection-smoke.lua" "$staging_dir/smoke/markdown-injection-smoke.lua"
cp "$repo_root/examples/basic.ast" "$staging_dir/samples/basic.ast"
cp "$repo_root/LICENSE" "$staging_dir/LICENSE"
cp "$repo_root/THIRD_PARTY_NOTICES.md" "$staging_dir/THIRD_PARTY_NOTICES.md"

install -m 0755 "$templates_dir/install.sh" "$staging_dir/install.sh"
install -m 0755 "$templates_dir/uninstall.sh" "$staging_dir/uninstall.sh"
install -m 0755 "$templates_dir/smoke.sh" "$staging_dir/smoke.sh"

cat > "$staging_dir/README.txt" <<EOF
tree-sitter-asterix Neovim runtime bundle
=========================================

Version: ${version}
Platform: ${platform}
Tree-sitter parser ABI: ${abi}
Required Neovim: 0.10 or newer

Install:

  ./install.sh

Smoke test:

  ./smoke.sh

Uninstall:

  ./uninstall.sh

Files are installed into:

  \${NVIM_SITE_DIR:-\${XDG_DATA_HOME:-\$HOME/.local/share}/nvim/site}

This bundle is standalone for users: it does not require Git, npm, Node.js,
tree-sitter-cli, or a C compiler. The installer verifies the bundled runtime,
refuses to overwrite unowned or modified files, and records an ownership
manifest for safe upgrades and removal.

The runtime includes an Asterix indent guard. It re-applies the Asterix
indentexpr after common Neovim plugin overrides such as nvim-treesitter indent.
EOF

build_definition_sha256="$(
  (
    cd "$repo_root"
    sha256sum \
      packaging/neovim/make-bundle.sh \
      packaging/neovim/templates/install.sh \
      packaging/neovim/templates/uninstall.sh \
      packaging/neovim/templates/smoke.sh
  ) | sha256sum | cut -d ' ' -f 1
)"
runtime_manifest_sha256="$(sha256sum "$staging_dir/runtime-manifest.sha256" | cut -d ' ' -f 1)"

cat > "$staging_dir/manifest.txt" <<EOF
name=tree-sitter-asterix-neovim
version=${version}
platform=${platform}
tree_sitter_abi=${abi}
source_commit=${source_commit}
source_state=${source_state}
source_date_epoch=${source_date_epoch}
built_at=${build_timestamp}
node_version=$(node --version)
npm_version=$(npm --version)
tree_sitter_cli_version=$("$tree_sitter_cli" --version)
c_compiler=$($bundle_cc --version | head -1)
c_compiler_path=$(command -v "$bundle_cc")
required_glibc_symbols=${parser_glibc_symbol_versions}
maximum_required_glibc_symbol=${maximum_required_glibc_symbol}
package_lock_sha256=$(sha256sum "$repo_root/package-lock.json" | cut -d ' ' -f 1)
build_definition_sha256=${build_definition_sha256}
runtime_manifest_sha256=${runtime_manifest_sha256}
EOF

tar \
  --sort=name \
  --mtime="@$source_date_epoch" \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$dist_dir" \
  -cf - "$bundle_name" \
  | gzip -n > "$archive_path"

(
  cd "$dist_dir"
  sha256sum "$(basename "$archive_path")" > "$(basename "$checksum_path")"
)

echo "Created Neovim bundle:"
echo "  directory: $staging_dir"
echo "  archive:   $archive_path"
echo "  checksum:  $checksum_path"
