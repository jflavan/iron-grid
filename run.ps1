#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Launches the game (Windows/PowerShell analog of run.sh).

.DESCRIPTION
    Refreshes Godot's import cache first, then runs the project. .godot/ is gitignored, so on a
    fresh clone or after pulling new class_name scripts a plain `godot --path .` can't resolve those
    class names, the autoloads fail to parse and the window stays blank.

    Works in Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Godot
    Path to the Godot executable. Defaults to $env:GODOT, then the first of godot / godot.exe /
    Godot*.exe found on PATH.

.PARAMETER GodotArgs
    Extra arguments passed to Godot, e.g. a scene path.

.EXAMPLE
    .\run.ps1
.EXAMPLE
    .\run.ps1 res://scenes/dev/BattlePreview.tscn
#>
[CmdletBinding()]
param(
    [string]$Godot = $env:GODOT,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GodotArgs = @()
)

# Godot logs to stderr; with 'Stop' Windows PowerShell 5.1 would turn that into a terminating error.
$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $PSScriptRoot

if (-not $Godot) {
    $found = Get-Command -Name 'godot', 'godot.exe', 'Godot*.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { $Godot = $found.Source }
}
if (-not $Godot -or -not (Get-Command -Name $Godot -ErrorAction SilentlyContinue)) {
    Write-Error "Godot not found ('$Godot'). Put it on PATH or pass -Godot / set `$env:GODOT."
    exit 1
}

# Refresh the global class cache so newly added class_name scripts resolve.
& $Godot --headless --path . --import *> $null

& $Godot --path . @GodotArgs
exit $LASTEXITCODE
