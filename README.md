# tree-sitter-asterix

Tree-sitter grammar for ASTERIX `.ast` specification files, with syntax
highlighting, folds and indentation for Neovim.

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
sha256sum -c tree-sitter-asterix-neovim-linux-x86_64-v0.1.0.tar.gz.sha256
tar -xzf tree-sitter-asterix-neovim-linux-x86_64-v0.1.0.tar.gz
cd tree-sitter-asterix-neovim-linux-x86_64-v0.1.0
./install.sh
./smoke.sh
```

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

BSD-3-Clause licensed. See [LICENSE](LICENSE).
