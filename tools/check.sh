#!/usr/bin/env bash
# Runs every quality gate on the skills: format, lint, strict type check, tests, copy sync.
# Usage: tools/check.sh            (tools from .tools/bin, else PATH)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/.tools/bin:$PATH"
cd "$ROOT"

DEFS="$ROOT/.tools/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	mkdir -p "$ROOT/.tools"
	curl -fsSL -o "$DEFS" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
fi

echo "== StyLua"
stylua --check .claude/skills tools

echo "== Selene"
selene .claude/skills tools

echo "== luau-lsp (strict types, Roblox definitions, Rojo sourcemaps)"
for project in .claude/skills/*/default.project.json; do
	dir="$(dirname "$project")"
	name="$(basename "$dir")"
	map="$ROOT/.tools/$name.sourcemap.json"
	(cd "$dir" && rojo sourcemap default.project.json -o "$map" >/dev/null)
	(cd "$dir" && luau-lsp analyze --platform=roblox --definitions="$DEFS" --sourcemap="$map" src)
	echo "   $name: ok"
done

echo "== Lune tests"
lune run tools/test/run.luau

echo "== Skill copies in sync"
tools/sync-skills.sh --check

echo "All checks passed."
