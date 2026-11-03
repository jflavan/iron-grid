#!/usr/bin/env bash
# Launches the game. Refreshes Godot's import cache first: .godot/ is gitignored, so on a fresh clone
# or after pulling new class_name scripts, a plain `godot --path .` can't resolve those class names,
# the autoloads fail to parse and the window stays blank.
# Extra arguments are passed to Godot, e.g. ./run.sh res://scenes/dev/BattlePreview.tscn
set -u
cd "$(dirname "$0")"
godot="${GODOT:-godot}"
if ! command -v "$godot" >/dev/null 2>&1; then
	echo "Godot not found ('$godot'). Put it on PATH or set GODOT=/path/to/godot." >&2
	exit 1
fi
"$godot" --headless --path . --import >/dev/null 2>&1
exec "$godot" --path . "$@"
