#!/usr/bin/env bash
# Runs the battle screen unit tests headless. Fails unless the suite reports "0 failures" and no
# SCRIPT ERROR was printed (a GDScript parse error would otherwise leave Godot idling with exit code
# 0, and a runtime error aborts the running test function without recording a failure).
set -u
cd "$(dirname "$0")/.."
godot --headless --path . --import >/dev/null 2>&1  # refresh the global class cache for new class_name scripts
out="$(godot --headless --path . --quit-after 20000 res://tests/BattleScreenTests.tscn 2>&1)"
code=$?
echo "$out" | grep -E "BATTLE TEST|SCRIPT ERROR|Parse Error|FAIL" | head -40
summary="$(echo "$out" | grep -E '^\[BATTLE TESTS\]')"
echo "${summary:-[BATTLE TESTS] no summary (suite did not run to completion)}"
script_errors="$(echo "$out" | grep -c 'SCRIPT ERROR')"
[[ $script_errors -eq 0 ]] || echo "[BATTLE TESTS] $script_errors SCRIPT ERROR line(s): a test aborted"
[[ $code -eq 0 && "$summary" == *" 0 failures" && $script_errors -eq 0 ]]
