#!/usr/bin/env bash
# Runs every automated check: the battle unit tests and the seeded playtest. Exits non-zero if any
# of them fails. Honours $GODOT (path to the Godot executable, default: godot).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
export GODOT
status=0

echo "== battle unit tests =="
tests/run_battle_tests.sh || status=1

echo "== playtest =="
log="$(mktemp)"
"$GODOT" --headless --path . res://tests/Playtest.tscn > "$log" 2>&1
code=$?
grep -E "SCRIPT ERROR|Parse Error|FAIL|failures" "$log" | head -20
errors="$(grep -c 'SCRIPT ERROR' "$log")"
if [[ $code -ne 0 || $errors -ne 0 ]] || ! grep -q " 0 failures" "$log"; then
	echo "[PLAYTEST] FAILED (exit $code, $errors SCRIPT ERROR line(s)); log: $log"
	status=1
else
	echo "[PLAYTEST] ok"
	rm -f "$log"
fi
exit $status
