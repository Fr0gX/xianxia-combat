param([switch]$Editor, [switch]$Test)
$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot '.engine/Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $engine)) {
    & (Join-Path $PSScriptRoot 'tools/setup-engine.ps1')
    if (-not (Test-Path -LiteralPath $engine)) { throw 'Engine installation failed.' }
}
if ($Test) {
    $consoleEngine = Join-Path $PSScriptRoot '.engine/Godot_v4.7.2-stable_win64_console.exe'
    & $consoleEngine --headless --path $PSScriptRoot --script res://tests/test_battle.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $consoleEngine --headless --path $PSScriptRoot --script res://tests/test_framework.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $consoleEngine --headless --path $PSScriptRoot --script res://tests/test_timing.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $consoleEngine --headless --path $PSScriptRoot --script res://tests/test_sword.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $consoleEngine --headless --path $PSScriptRoot --script res://tests/test_ui.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $consoleEngine --headless --path $PSScriptRoot --script res://tests/test_drag_summary.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $consoleEngine --headless --path $PSScriptRoot --script res://tests/test_passives.gd
    exit $LASTEXITCODE
} elseif ($Editor) {
    Start-Process -FilePath $engine -ArgumentList @('--editor', '--path', ('"' + $PSScriptRoot + '"'))
} else {
    Start-Process -FilePath $engine -ArgumentList @('--path', ('"' + $PSScriptRoot + '"'))
}
