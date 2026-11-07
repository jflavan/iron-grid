#!/usr/bin/env bash
# Runs every automated check: the battle unit tests and the seeded playtest. Exits non-zero if any
# of them fails. SCALE=1 also prints the scalability benchmark table (timings only, no assertions). Honours $GODOT (path to the Godot executable, default: godot).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
export GODOT
status=0

echo "== battle unit tests =="
tests/run_battle_tests.sh || status=1

echo "== script-mode compile check =="
# Scripts run with `godot -s` (the screenshot tool, matrix.gd, backfire.gd) compile before the
# autoloads exist, so a rule or data class that references GlobalState breaks them while every
# scene-based test stays green. Loading the snapshot tool with no arguments compiles its whole
# dependency graph (SkirmishEngine, Rules, the grids and catalogs) and must report no compile error.
compile_log="$("$GODOT" --headless --path . -s tools/ui_snapshot/snapshot.gd 2>&1)"
if grep -q "Compile Error" <<< "$compile_log"; then
	grep -E "Compile Error|at: " <<< "$compile_log" | head -10
	echo "[SCRIPT MODE] FAILED: a script run with -s no longer compiles"
	status=1
else
	echo "[SCRIPT MODE] ok"
fi

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
if [[ "${SCALE:-0}" == "1" ]]; then
	echo "== scale benchmark =="
	"$GODOT" --headless --path . res://tests/ScaleBench.tscn 2>&1 | grep "SCALE BENCH"
fi
exit $status
