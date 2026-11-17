<#
.SYNOPSIS
    Bundles Modular Shields into a ready-to-install FAF mod under dist/.
.DESCRIPTION
    1. Generates module icon artifacts (artifacts/module-icons) if missing or -Regenerate.
    2. Runs ./test.ps1 unless -SkipTests.
    3. Assembles dist/ModularShields (src/, README, PLAYTEST + generated textures) and
       dist/ModularShields-v<version>.zip.
    4. With -Install, mirrors dist/ModularShields into the FAF mods folder.
.EXAMPLE
    ./build.ps1
    ./build.ps1 -Install
    ./build.ps1 -Regenerate -SkipTests
#>
param(
    [switch]$SkipTests,
    [switch]$Regenerate,
    [switch]$Install,
    [string]$Compiler = $env:FD_CXX,
    [string]$ModsDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Gas Powered Games\Supreme Commander Forged Alliance\mods')
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$name = 'ModularShields'
$source = Join-Path $root 'src'
$icons = Join-Path $root 'artifacts\module-icons\textures\modules'
$dist = Join-Path $root 'dist'
$out = Join-Path $dist $name
$loaderRoot = Join-Path (Split-Path -Parent $root) 'FireDragon Mod Loader'
if (-not (Test-Path -LiteralPath (Join-Path $loaderRoot 'build.ps1'))) { throw 'Native FireDragon Mod Loader project is missing.' }
Write-Host '== Building shared C++ loader' -ForegroundColor Cyan
& (Join-Path $loaderRoot 'build.ps1') -SkipTests -Compiler $Compiler

Write-Host '== Generating and compiling UEF T4 hex shader' -ForegroundColor Cyan
& python (Join-Path $root 'scripts\hex_shader.py') --assets
if ($LASTEXITCODE -ne 0) { throw 'Hex shader validation failed.' }
$shaderSource = Join-Path $source 'shaders'
New-Item -ItemType Directory $shaderSource -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'shaders\UEFT4Hex.fx') -Destination $shaderSource

if ($Regenerate -or -not (Test-Path (Join-Path $icons '*.dds'))) {
    Write-Host '== Generating module icons' -ForegroundColor Cyan
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw "'python' was not found on PATH (needs Pillow)." }
    & python (Join-Path $root 'scripts\generate_module_icons.py')
    if ($LASTEXITCODE -ne 0) { throw 'Icon generation failed (pip install pillow?).' }
}

if (-not $SkipTests) { & (Join-Path $root 'test.ps1') -SkipNativeBuild }

Write-Host "== Bundling $out" -ForegroundColor Cyan
$resolvedOut = [IO.Path]::GetFullPath($out)
if ($resolvedOut -ne [IO.Path]::GetFullPath((Join-Path $root 'dist\ModularShields'))) { throw 'Unexpected bundle output path' }
if (Test-Path -LiteralPath $resolvedOut) { Remove-Item -LiteralPath $resolvedOut -Recurse -Force }
New-Item -ItemType Directory $out -Force | Out-Null
Copy-Item (Join-Path $source '*') $out -Recurse
Copy-Item (Join-Path $root 'README.md'),(Join-Path $root 'docs\PLAYTEST.md') $out
$outDocs = Join-Path $out 'docs'
New-Item -ItemType Directory $outDocs -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'docs\UEF_T4_HEX_TEST.md') -Destination $outDocs
$textures = Join-Path $out 'textures\modules'
New-Item -ItemType Directory $textures -Force | Out-Null
Copy-Item (Join-Path $icons '*.dds') $textures

$version = (Select-String (Join-Path $source 'mod_info.lua') -Pattern '^\s*version\s*=\s*(\d+)').Matches[0].Groups[1].Value
Get-ChildItem $dist -Filter "$name-v*.zip" | Remove-Item
$zip = Join-Path $dist "$name-v$version.zip"
Compress-Archive -LiteralPath $out -DestinationPath $zip -Force
Write-Host "Built v$version -> $out" -ForegroundColor Green
Write-Host "Archive      -> $zip" -ForegroundColor Green

if ($Install) {
    if (-not (Test-Path $ModsDir)) { throw "FAF mods folder not found: $ModsDir" }
    $loaderInstaller = Join-Path (Split-Path -Parent $root) 'FireDragon Mod Loader\install.ps1'
    if (-not (Test-Path -LiteralPath $loaderInstaller)) { throw 'Native FireDragon Mod Loader dependency is missing.' }
    & $loaderInstaller -ModsDirectory $ModsDir
    $target = Join-Path $ModsDir $name
    robocopy $out $target /MIR /NJH /NJS /NP /NFL /NDL | Out-Null
    if ($LASTEXITCODE -gt 3) { throw "robocopy failed ($LASTEXITCODE)" }
    $global:LASTEXITCODE = 0
    Write-Host "Installed    -> $target" -ForegroundColor Green
}
