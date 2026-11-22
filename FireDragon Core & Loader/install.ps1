param(
    [string]$FafDirectory = (Join-Path $env:ProgramData 'FAForever'),
    [string]$ModsDirectory,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
function Get-SHA256([string]$path) {
    $stream = [IO.File]::OpenRead($path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally { $stream.Dispose(); $sha.Dispose() }
}
if (Get-Process ForgedAlliance -ErrorAction SilentlyContinue) { throw 'Close Forged Alliance before changing the native loader installation.' }
$receiptFile = Join-Path $env:LOCALAPPDATA 'FireDragonModLoader\installation.json'
$receipt = if (Test-Path -LiteralPath $receiptFile) { Get-Content -LiteralPath $receiptFile -Raw | ConvertFrom-Json } else { $null }
function Assert-Owned($path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $owned = @($receipt.Files | Where-Object Path -eq $path)
    if ($owned.Count -ne 1 -or (Get-SHA256 $path) -ne $owned[0].Hash) {
        throw "Existing file is unowned or was modified; refusing to replace/remove: $path"
    }
}
if ($Uninstall) {
    if (-not $receipt) { throw 'No installation receipt found; refusing to remove unowned files.' }
    foreach ($file in $receipt.Files) { Assert-Owned $file.Path }
    foreach ($file in $receipt.Files) {
        if (Test-Path -LiteralPath $file.Path) { Remove-Item -LiteralPath $file.Path }
    }
    Remove-Item -LiteralPath $receiptFile
    Write-Host 'Removed only loader-owned files. Disable native-dependent mods when playing without the loader.'
    return
}
$payload = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'bin\FireDragonLoader.dll')) { $PSScriptRoot } else { Join-Path $PSScriptRoot 'dist\FireDragon Core & Loader' }
if (-not (Test-Path -LiteralPath (Join-Path $payload 'bin\FireDragonLoader.dll'))) { throw 'Build/package the native loader first.' }
$FafDirectory = (Resolve-Path -LiteralPath $FafDirectory).Path
if (-not $ModsDirectory) {
    $pathFile = Join-Path $FafDirectory 'fa_path.lua'
    if (Test-Path -LiteralPath $pathFile) {
        $match = [regex]::Match((Get-Content -LiteralPath $pathFile -Raw), 'custom_vault_path\s*=\s*["'']([^"'']+)["'']')
        if ($match.Success) { $ModsDirectory = Join-Path $match.Groups[1].Value 'mods' }
    }
    if (-not $ModsDirectory) { $ModsDirectory = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Gas Powered Games\Supreme Commander Forged Alliance\mods' }
}
$ModsDirectory = (Resolve-Path -LiteralPath $ModsDirectory).Path
$modTarget = Join-Path $ModsDirectory 'FireDragon Core & Loader'
$bins = @(Join-Path $FafDirectory 'bin')
$replayBin = Join-Path $FafDirectory 'replaydata\bin'
if (Test-Path -LiteralPath (Join-Path $replayBin 'ForgedAlliance.exe')) { $bins += $replayBin }
$copies = @()
foreach ($source in Get-ChildItem -LiteralPath $payload -File -Recurse) {
    $relative = $source.FullName.Substring($payload.TrimEnd('\').Length+1)
    $copies += @{ Source=$source.FullName; Path=(Join-Path $modTarget $relative) }
}
$configs = @()
foreach ($bin in $bins) {
    if (-not (Test-Path -LiteralPath (Join-Path $bin 'ForgedAlliance.exe'))) { throw "Missing FAF executable: $bin" }
    $copies += @{ Source=(Join-Path $payload 'bootstrap\dsound.dll'); Path=(Join-Path $bin 'dsound.dll') }
    $configs += Join-Path $bin 'FireDragonLoader.ini'
}
$targets = @($copies | ForEach-Object Path) + $configs
foreach ($path in $targets) { Assert-Owned $path }
if ($receipt) { foreach ($file in $receipt.Files) { Assert-Owned $file.Path } }
$originals = @{}
foreach ($bin in $bins) {
    foreach ($file in Get-ChildItem -LiteralPath $bin -File) {
        if ($file.FullName -notin $targets -and $file.FullName -notin @($receipt.Files | ForEach-Object Path)) {
            $originals[$file.FullName] = Get-SHA256 $file.FullName
        }
    }
}
$effects = Join-Path $FafDirectory 'gamedata\effects.nx2'
if (Test-Path -LiteralPath $effects) { $originals[$effects] = Get-SHA256 $effects }
$files = @()
foreach ($copy in $copies) {
    New-Item -ItemType Directory (Split-Path -Parent $copy.Path) -Force | Out-Null
    if ([IO.Path]::GetFullPath($copy.Source) -ne [IO.Path]::GetFullPath($copy.Path)) { Copy-Item -LiteralPath $copy.Source -Destination $copy.Path -Force }
    $installedHash=Get-SHA256 $copy.Path
    if ($installedHash -ne (Get-SHA256 $copy.Source)) { throw "Installed package hash mismatch: $($copy.Path)" }
    $files += @{ Path=$copy.Path; Hash=$installedHash }
}
foreach ($config in $configs) {
    Set-Content -LiteralPath $config -Value "[Loader]`r`nLoaderPath=$(Join-Path $modTarget 'bin\FireDragonLoader.dll')`r`nModsDirectory=$ModsDirectory" -Encoding Unicode
    $files += @{ Path=$config; Hash=(Get-SHA256 $config) }
}
if ($receipt) {
    foreach ($file in $receipt.Files) {
        if ($file.Path -notin $targets -and (Test-Path -LiteralPath $file.Path)) { Remove-Item -LiteralPath $file.Path }
    }
}
foreach ($path in $originals.Keys) {
    if ((Get-SHA256 $path) -ne $originals[$path]) { throw "Unexpected managed file change: $path" }
}
New-Item -ItemType Directory (Split-Path -Parent $receiptFile) -Force | Out-Null
@{ Version='3'; Files=$files; ManagedFileHashes=$originals } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptFile -Encoding utf8
Write-Host "Installed FireDragonModLoader mod and bootstrap in $($bins.Count) FAF binary directories. $($originals.Count) managed hashes unchanged."
Write-Host 'No managed archive/executable/init file or game launch setting was modified.'
