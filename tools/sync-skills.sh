#!/usr/bin/env bash
# .claude/skills is the source of truth (Claude Code). Mirrors it to:
#   skills/          (manual install for Antigravity / Gemini global skills)
#   .agents/skills/  (Antigravity workspace skills)
# Usage: tools/sync-skills.sh          copy
#        tools/sync-skills.sh --check  fail if a copy differs
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.claude/skills"
TARGETS=("$ROOT/skills" "$ROOT/.agents/skills")

if [ "${1:-}" = "--check" ]; then
	status=0
	for target in "${TARGETS[@]}"; do
		if ! diff -r -q "$SRC" "$target" >/dev/null 2>&1; then
			echo "Out of sync: ${target#"$ROOT"/} (run tools/sync-skills.sh)"
			diff -r -q "$SRC" "$target" || true
			status=1
		fi
	done
	exit $status
fi

for target in "${TARGETS[@]}"; do
	rm -rf "$target"
	mkdir -p "$target"
	cp -R "$SRC/." "$target/"
	echo "Synced ${target#"$ROOT"/}"
done
