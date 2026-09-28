#!/usr/bin/env bash
# Installs the pinned toolchain into .tools/bin (Linux x86_64 / macOS arm64).
# Locally you can use Rokit instead (`rokit install`, see rokit.toml).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.tools/bin"
mkdir -p "$BIN"

LUNE_VERSION="0.10.4"
STYLUA_VERSION="2.5.2"
SELENE_VERSION="0.30.0"
LUAU_LSP_VERSION="1.70.1"
ROJO_VERSION="7.6.1"

case "$(uname -s)-$(uname -m)" in
	Linux-x86_64) LUNE_T="linux-x86_64"; STYLUA_T="linux-x86_64"; SELENE_T="linux"; LSP_T="linux-x86_64"; ROJO_T="linux-x86_64" ;;
	Darwin-arm64) LUNE_T="macos-aarch64"; STYLUA_T="macos-aarch64"; SELENE_T="macos"; LSP_T="macos"; ROJO_T="macos-aarch64" ;;
	*) echo "Unsupported platform: use Rokit (rokit.toml)"; exit 1 ;;
esac

fetch() { # name url
	local name="$1" url="$2" tmp
	if [ -x "$BIN/$name" ]; then return; fi
	echo "-> $name"
	tmp="$(mktemp -d)"
	curl -fsSL -o "$tmp/archive.zip" "$url"
	python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$tmp/archive.zip" "$tmp/out"
	find "$tmp/out" -type f -name "$name" -exec mv {} "$BIN/$name" \;
	chmod +x "$BIN/$name"
	rm -rf "$tmp"
}

fetch lune "https://github.com/lune-org/lune/releases/download/v$LUNE_VERSION/lune-$LUNE_VERSION-$LUNE_T.zip"
fetch stylua "https://github.com/JohnnyMorganz/StyLua/releases/download/v$STYLUA_VERSION/stylua-$STYLUA_T.zip"
fetch selene "https://github.com/Kampfkarren/selene/releases/download/$SELENE_VERSION/selene-$SELENE_VERSION-$SELENE_T.zip"
fetch luau-lsp "https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LUAU_LSP_VERSION/luau-lsp-$LSP_T.zip"
fetch rojo "https://github.com/rojo-rbx/rojo/releases/download/v$ROJO_VERSION/rojo-$ROJO_VERSION-$ROJO_T.zip"

DEFS="$ROOT/.tools/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	echo "-> Roblox type definitions"
	curl -fsSL -o "$DEFS" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
fi
echo "Tools ready in $BIN"
