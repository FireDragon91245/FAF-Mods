param(
    [switch]$SkipBuild,
    [string]$EffectsArchive = (Join-Path $env:ProgramData 'FAForever\gamedata\effects.nx2'),
    [string]$ConsumerDirectory
)
$ErrorActionPreference = 'Stop'
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build.ps1') -SkipTests }
& (Join-Path $PSScriptRoot 'dist\resource-test.exe')
if ($LASTEXITCODE) { throw 'Native resource contract tests failed' }
& (Join-Path $PSScriptRoot 'dist\lua-test.exe')
if ($LASTEXITCODE) { throw 'Native Lua bridge tests failed' }
$arguments = @('-B', (Join-Path $PSScriptRoot 'tests\run.py'), '--archive', $EffectsArchive)
if ($ConsumerDirectory) { $arguments += @('--consumer', $ConsumerDirectory) }
& python @arguments
if ($LASTEXITCODE) { throw 'Native loader integration tests failed' }
& python -B (Join-Path $PSScriptRoot 'tests\install.py')
if ($LASTEXITCODE) { throw 'Native loader installer tests failed' }
& luac -p (Join-Path $PSScriptRoot 'src\mod_info.lua')
if ($LASTEXITCODE) { throw 'Loader mod metadata syntax failed' }
