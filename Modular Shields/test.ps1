<#
.SYNOPSIS
    Runs the Modular Shields Lua test suite and syntax-checks every mod source.
.EXAMPLE
    ./test.ps1
    ./test.ps1 -Filter gameplay
#>
param(
    # Run only test files whose name matches this wildcard (without .lua).
    [string]$Filter = '*'
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$mod = Join-Path $root 'src'

foreach ($tool in 'lua','luac') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "'$tool' was not found on PATH." }
}

# run.lua covers the pure rules and must run first; the rest are independent suites.
$tests = @('run') + (Get-ChildItem (Join-Path $root 'tests') -Filter *.lua |
    Where-Object BaseName -ne 'run' | Sort-Object Name | ForEach-Object BaseName)

Push-Location -LiteralPath $root
try {
    $ran = 0
    foreach ($test in $tests | Where-Object { $_ -like $Filter }) {
        Write-Host "== $test" -ForegroundColor Cyan
        & lua (Join-Path 'tests' "$test.lua")
        if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
        $ran++
    }
    if ($ran -eq 0) { throw "No tests match '$Filter'." }

    $sources = Get-ChildItem -LiteralPath $mod -Recurse -File | Where-Object { $_.Extension -in '.lua','.bp' }
    foreach ($source in $sources) {
        & luac -p $source.FullName
        if ($LASTEXITCODE -ne 0) { throw "Syntax failed: $($source.FullName)" }
    }
    Write-Host "PASS: $ran test files, $($sources.Count) Lua/blueprint syntax checks" -ForegroundColor Green
} finally {
    Pop-Location
}
