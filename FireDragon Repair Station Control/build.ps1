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
$name = 'FireDragon Repair Station Control'
$source = Join-Path $root 'src'
$dist = Join-Path $root 'dist'
$out = Join-Path $dist $name

# Honor the same custom vault that FAF and the core installer use.
if (-not $PSBoundParameters.ContainsKey('ModsDir')) {
    $pathFile = Join-Path $env:ProgramData 'FAForever/fa_path.lua'
    if (Test-Path -LiteralPath $pathFile) {
        $match = [regex]::Match((Get-Content -LiteralPath $pathFile -Raw), 'custom_vault_path\s*=\s*["'']([^"'']+)["'']')
        if ($match.Success) { $ModsDir = Join-Path $match.Groups[1].Value 'mods' }
    }
}

# Compile the native candidate gates against the existing loader ABI.
$compiler = if ($env:FD_CXX) { $env:FD_CXX } else { 'H:\msys64\mingw32\bin\g++.exe' }
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Set FD_CXX to a 32-bit MinGW-w64 g++.' }
New-Item -ItemType Directory -Force (Join-Path $source 'dlls') | Out-Null
$priorPath = $env:PATH
$env:PATH = (Split-Path -Parent $compiler) + ';' + $env:PATH
try {
    & $compiler -m32 -std=c++17 -O2 -Wall -Wextra -shared -static -static-libgcc -static-libstdc++ '-Wl,--no-insert-timestamp' "-I$root/../FireDragon Core & Loader/native/include" (Join-Path $root 'native/TargetFilter.cpp') -o (Join-Path $source 'dlls/TargetFilter.dll')
    if ($LASTEXITCODE) { throw 'Native target filter build failed.' }
} finally { $env:PATH = $priorPath }

if (-not $SkipTests) { & (Join-Path $root 'test.ps1') -ModFolder $name }

Write-Host "== Bundling $out" -ForegroundColor Cyan
if (Test-Path -LiteralPath $out) {
    $resolvedOut = (Resolve-Path -LiteralPath $out).Path
    $expectedOut = [IO.Path]::GetFullPath((Join-Path $root "dist/$name"))
    if ($resolvedOut -ne $expectedOut) { throw "Unexpected package path: $resolvedOut" }
    Remove-Item -LiteralPath $resolvedOut -Recurse -Force
}
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
    if (Get-Process ForgedAlliance -ErrorAction SilentlyContinue) { throw 'Close Forged Alliance before installing FireDragon Repair Station Control.' }
    if (-not (Test-Path $ModsDir)) { throw "FAF mods folder not found: $ModsDir" }
    $modsRoot = (Resolve-Path -LiteralPath $ModsDir).Path
    $target = [IO.Path]::GetFullPath((Join-Path $modsRoot $name))
    if ((Split-Path -Parent $target) -ne $modsRoot) { throw "Unexpected install path: $target" }
    if (Test-Path -LiteralPath $target) {
        if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to mirror into a linked mod folder.' }
    }
    robocopy $out $target /MIR /NJH /NJS /NP /NFL /NDL | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
    $global:LASTEXITCODE = 0
    $packageFiles = @(Get-ChildItem -LiteralPath $out -File -Recurse)
    $installedFiles = @(Get-ChildItem -LiteralPath $target -File -Recurse)
    if ($packageFiles.Count -ne $installedFiles.Count) { throw 'Installed package contains missing or obsolete files.' }
    foreach ($file in $packageFiles) {
        $relative = $file.FullName.Substring($out.Length + 1)
        $installed = Join-Path $target $relative
        if (-not (Test-Path -LiteralPath $installed) -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $installed).Hash) {
            throw "Installed hash mismatch: $relative"
        }
    }
    $installedVersion = (Select-String (Join-Path $target 'mod_info.lua') -Pattern '^\s*version\s*=\s*(\d+)').Matches[0].Groups[1].Value
    if ($installedVersion -ne $version) { throw 'Installed version mismatch.' }
    Write-Host "Installed    -> $target" -ForegroundColor Green
    Write-Host "Verified v$installedVersion and $($packageFiles.Count) SHA256 file hashes." -ForegroundColor Green
}
