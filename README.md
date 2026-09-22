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
