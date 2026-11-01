#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs the battle screen unit tests headless (Windows/PowerShell analog of run_battle_tests.sh).

.DESCRIPTION
    Refreshes Godot's global class cache, runs res://tests/BattleScreenTests.tscn headless and
    fails unless the suite prints "[BATTLE TESTS] N checks, 0 failures". A GDScript parse error
    would otherwise leave Godot idling until --quit-after with exit code 0.

    Works in Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Godot
    Path to the Godot executable. Defaults to $env:GODOT, then the first of godot / godot.exe /
    Godot*_console.exe found on PATH. On Windows use the *_console.exe build: the GUI build does
    not write to the console, so the test summary could not be read.

.EXAMPLE
    .\tests\run_battle_tests.ps1
.EXAMPLE
    .\tests\run_battle_tests.ps1 -Godot 'C:\Tools\Godot\Godot_v4.7-stable_win64_console.exe'
#>
[CmdletBinding()]
param(
    [string]$Godot = $env:GODOT
)

# Godot logs to stderr; with 'Stop' Windows PowerShell 5.1 would turn that into a terminating error.
$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath (Join-Path $PSScriptRoot '..')

if (-not $Godot) {
    $found = Get-Command -Name 'godot', 'godot.exe', 'Godot*_console.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { $Godot = $found.Source }
}
if (-not $Godot -or -not (Get-Command -Name $Godot -ErrorAction SilentlyContinue)) {
    Write-Error "Godot not found ('$Godot'). Put it on PATH or pass -Godot / set `$env:GODOT (use the *_console.exe build on Windows)."
    exit 1
}

# Refresh the global class cache so newly added class_name scripts resolve.
& $Godot --headless --path . --import *> $null

$out = @(& $Godot --headless --path . --quit-after 20000 res://tests/BattleScreenTests.tscn 2>&1 | ForEach-Object { "$_" })
$code = $LASTEXITCODE

$out | Where-Object { $_ -match 'BATTLE TEST|SCRIPT ERROR|Parse Error|FAIL' } | Select-Object -First 40 | ForEach-Object { Write-Output $_ }

$summary = $out | Where-Object { $_ -match '^\[BATTLE TESTS\]' } | Select-Object -Last 1
if (-not $summary) { $summary = '[BATTLE TESTS] no summary (suite did not run to completion)' }
Write-Output $summary

if ($code -eq 0 -and $summary -like '* 0 failures') { exit 0 }
exit 1
