<#
.SYNOPSIS
    Bundles the mod into a ready-to-install FAF mod under dist/.
.DESCRIPTION
    1. Runs ./test.ps1 unless -SkipTests.
    2. Assembles dist/<ModFolder> (src/ + README.md) and dist/<ModFolder>-v<version>.zip.
    3. With -Install, mirrors dist/<ModFolder> into the FAF mods folder.
.EXAMPLE
    ./build.ps1
    ./build.ps1 -Install
#>
param(
    [switch]$SkipTests,
    [switch]$Install,
    [string]$ModsDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Gas Powered Games\Supreme Commander Forged Alliance\mods')
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$name = 'InstaBuildRenderFix'
$source = Join-Path $root 'src'
$dist = Join-Path $root 'dist'
$out = Join-Path $dist $name

if (-not $SkipTests) { & (Join-Path $root 'test.ps1') -ModFolder $name }

Write-Host "== Bundling $out" -ForegroundColor Cyan
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory $out -Force | Out-Null
Copy-Item (Join-Path $source '*') $out -Recurse
Copy-Item (Join-Path $root 'README.md') $out

$version = (Select-String (Join-Path $source 'mod_info.lua') -Pattern '^\s*version\s*=\s*(\d+)').Matches[0].Groups[1].Value
Get-ChildItem $dist -Filter "$name-v*.zip" | Remove-Item
$zip = Join-Path $dist "$name-v$version.zip"
Compress-Archive -LiteralPath $out -DestinationPath $zip -Force
Write-Host "Built v$version -> $out" -ForegroundColor Green
Write-Host "Archive      -> $zip" -ForegroundColor Green

if ($Install) {
    if (-not (Test-Path $ModsDir)) { throw "FAF mods folder not found: $ModsDir" }
    $target = Join-Path $ModsDir $name
    robocopy $out $target /MIR /NJH /NJS /NP /NFL /NDL | Out-Null
    if ($LASTEXITCODE -gt 3) { throw "robocopy failed ($LASTEXITCODE)" }
    $global:LASTEXITCODE = 0
    Write-Host "Installed    -> $target" -ForegroundColor Green
}
