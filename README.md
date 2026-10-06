# tree-sitter-asterix

Tree-sitter grammar for ASTERIX `.ast` specification files, with syntax
highlighting, folds and indentation for Neovim.

This grammar supports `.ast` files from the
[asterix-specs project](https://github.com/zoranbosnjak/asterix-specs).

Neovim uses the `asterix-spec` filetype and Markdown fenced-code label. The
internal Tree-sitter parser identifier is `asterix_spec`.

## Requirements

The prebuilt bundle requires Linux x86_64 with glibc, Bash, `tar`,
`sha256sum`, and Neovim 0.10 or newer.

Building from source additionally requires Git, Node.js 24, npm, a C compiler,
and `readelf` from GNU Binutils.

## Install

Download the `.tar.gz` archive and matching `.sha256` file from
[Releases](https://github.com/alenpozegic/tree-sitter-asterix/releases), then
run:

```bash
sha256sum -c tree-sitter-asterix-neovim-linux-x86_64-v0.2.0.tar.gz.sha256
tar -xzf tree-sitter-asterix-neovim-linux-x86_64-v0.2.0.tar.gz
cd tree-sitter-asterix-neovim-linux-x86_64-v0.2.0
./install.sh
./smoke.sh
```

The installer safely upgrades an unmodified runtime installed from `v0.1.0`.
It refuses to replace modified, foreign or ambiguously owned files.

Run `./uninstall.sh` from the same directory to remove the installed runtime.

## Manual installation with NvChad / lazy.nvim

Requires an existing NvChad configuration, or a lazy.nvim setup that imports
`lua/plugins/`. These commands use the default Linux Neovim directories and the
Linux x86_64 glibc bundle. Downloading the bundle requires `curl`. Close Neovim
before installing.

### Download and verify

```bash
mkdir -p ~/Downloads/asterix-manual-v0.2.0
cd ~/Downloads/asterix-manual-v0.2.0

curl --fail --location \
  --output tree-sitter-asterix-neovim-linux-x86_64-v0.2.0.tar.gz \
  https://github.com/alenpozegic/tree-sitter-asterix/releases/download/v0.2.0/tree-sitter-asterix-neovim-linux-x86_64-v0.2.0.tar.gz

echo 'dcc90023d56382ce8dcdc62a388ecf9837c9d3b095d71a1f46bbf664170e5cdb  tree-sitter-asterix-neovim-linux-x86_64-v0.2.0.tar.gz' | sha256sum --check
```

Continue only if verification reports `OK`.

### Copy the runtime

```bash
tar -xzf tree-sitter-asterix-neovim-linux-x86_64-v0.2.0.tar.gz
cd tree-sitter-asterix-neovim-linux-x86_64-v0.2.0

mkdir -p ~/.local/share/nvim/manual-plugins/tree-sitter-asterix
cp -R runtime/. ~/.local/share/nvim/manual-plugins/tree-sitter-asterix/
```

### Configure lazy.nvim

Create this file for a fresh installation. Preserve any existing configuration
with the same filename.

```bash
mkdir -p ~/.config/nvim/lua/plugins

cat > ~/.config/nvim/lua/plugins/asterix.lua <<'EOF'
return {
  {
    dir = vim.fn.stdpath("data") .. "/manual-plugins/tree-sitter-asterix",
    name = "tree-sitter-asterix",
    lazy = false,
    priority = 1000,
  },
}
EOF
```

### Verify

Open an ASTERIX specification, replacing the example path with your own:

```bash
nvim /path/to/specification.ast
```

Run inside Neovim:

```vim
:Lazy
:set filetype?
:InspectTree
:set indentexpr?
```

Expected: the plugin is loaded, `filetype=asterix-spec`, the syntax tree starts
with `source_file`, and `indentexpr=v:lua.GetAsterixSpecIndent()`.

To enable Tree-sitter folding in the current buffer:

```vim
:setlocal foldmethod=expr foldexpr=v:lua.vim.treesitter.foldexpr()
```

Use `zc` to close a fold and `zo` to open it.

### Uninstall

Close Neovim, then remove the configuration and manually installed runtime:

```bash
rm -- ~/.config/nvim/lua/plugins/asterix.lua
rm -r -- ~/.local/share/nvim/manual-plugins/tree-sitter-asterix
```

## Build from source

```bash
git clone https://github.com/alenpozegic/tree-sitter-asterix.git
cd tree-sitter-asterix
npm ci
npm test
npm run build:neovim:bundle
```

The bundle and its checksum are created in `dist/`.

## Modify the grammar

Edit `grammar.js`, add or update a matching case in `test/corpus/`, then run:

```bash
npm ci
npm run generate
npm test
```

Commit the grammar, corpus test and regenerated files in `src/` together.

BSD-3-Clause licensed. See [LICENSE](LICENSE).
