#!/usr/bin/env bash
# Runs the battle screen unit tests headless. Fails unless the suite reports "0 failures"
# (a GDScript parse error would otherwise leave Godot idling with exit code 0).
set -u
cd "$(dirname "$0")/.."
out="$(godot --headless --path . --quit-after 20000 res://tests/BattleScreenTests.tscn 2>&1)"
code=$?
echo "$out" | grep -E "BATTLE TEST|SCRIPT ERROR|Parse Error|FAIL" | head -40
summary="$(echo "$out" | grep -E '^\[BATTLE TESTS\]')"
echo "${summary:-[BATTLE TESTS] no summary (suite did not run to completion)}"
[[ $code -eq 0 && "$summary" == *" 0 failures" ]]
