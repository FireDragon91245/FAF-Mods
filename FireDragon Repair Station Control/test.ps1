<#
.SYNOPSIS
    Runs the Lua test suites, syntax-checks every mod source and lints /mods/ import paths.
.EXAMPLE
    ./test.ps1
    ./test.ps1 -Filter guard
#>
param(
    # Run only test files whose name matches this wildcard (without .lua).
    [string]$Filter = '*',
    # In-game mod folder; every /mods/<X>/ path in src must use it.
    [string]$ModFolder = 'FireDragon Repair Station Control'
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$mod = Join-Path $root 'src'

foreach ($tool in 'lua','luac') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "'$tool' was not found on PATH." }
}

$all = @(Get-ChildItem (Join-Path $root 'tests') -Filter *.lua | Sort-Object Name | ForEach-Object BaseName)
$tests = @($all | Where-Object { $_ -eq 'run' }) + @($all | Where-Object { $_ -ne 'run' })

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

    $sources = @(Get-ChildItem -LiteralPath $mod -Recurse -File | Where-Object { $_.Extension -in '.lua','.bp' })
    foreach ($source in $sources) {
        & luac -p $source.FullName
        if ($LASTEXITCODE -ne 0) { throw "Syntax failed: $($source.FullName)" }
    }

    $wrong = @($sources | Select-String -Pattern '/mods/([^/''"]+)/' -AllMatches | ForEach-Object {
        foreach ($m in $_.Matches) { if ($m.Groups[1].Value -notin @($ModFolder, 'FireDragon Core & Loader')) { "$($_.Path):$($_.LineNumber): $($m.Value)" } }
    })
    if ($wrong.Count) { throw "Import paths must use /mods/$ModFolder/:`n$($wrong -join "`n")" }

    Write-Host "PASS: $ran test files, $($sources.Count) Lua/blueprint syntax checks" -ForegroundColor Green
} finally {
    Pop-Location
}
