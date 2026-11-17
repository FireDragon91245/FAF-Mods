param(
    [string]$Compiler = $env:FD_CXX,
    [switch]$SkipTests,
    [switch]$Install,
    [string]$ModsDirectory,
    [string]$EffectsArchive = (Join-Path $env:ProgramData 'FAForever\gamedata\effects.nx2')
)
$ErrorActionPreference = 'Stop'
if (-not $Compiler) {
    $candidate = Get-Command i686-w64-mingw32-g++.exe -ErrorAction SilentlyContinue
    if ($candidate) { $Compiler = $candidate.Source }
    elseif (Test-Path 'H:\msys64\mingw32\bin\g++.exe') { $Compiler = 'H:\msys64\mingw32\bin\g++.exe' }
}
if (-not $Compiler -or -not (Test-Path -LiteralPath $Compiler)) { throw 'Set FD_CXX or supply -Compiler with a 32-bit MinGW-w64 g++.' }
$priorPath = $env:PATH
try {
    $env:PATH = (Split-Path -Parent $Compiler) + ';' + $env:PATH
    foreach ($tool in 'cmake','ninja') { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is required to build native components." } }
    $build = Join-Path $PSScriptRoot 'build'
    $cCompiler = Join-Path (Split-Path -Parent $Compiler) ([IO.Path]::GetFileName($Compiler).Replace('g++','gcc'))
    & cmake -S $PSScriptRoot -B $build -G Ninja "-DCMAKE_CXX_COMPILER=$Compiler" "-DCMAKE_C_COMPILER=$cCompiler" '-DCMAKE_BUILD_TYPE=Release' "-DCMAKE_MAKE_PROGRAM=$((Get-Command ninja).Source)"
    if ($LASTEXITCODE) { throw 'CMake configure failed' }
    & cmake --build $build --parallel 2
    if ($LASTEXITCODE) { throw 'Native C++ build failed' }
    $out = Join-Path $PSScriptRoot 'dist'
    New-Item -ItemType Directory $out -Force | Out-Null
    Copy-Item (Join-Path $build 'bin\*') -Destination $out -Force
    Write-Host 'Built x86 FireDragonLoader.dll, proxy bootstrap and native test fixtures.'
} finally { $env:PATH = $priorPath }
if (-not $SkipTests) { & (Join-Path $PSScriptRoot 'test.ps1') -SkipBuild -EffectsArchive $EffectsArchive }
& (Join-Path $PSScriptRoot 'package.ps1')
if ($Install) { & (Join-Path $PSScriptRoot 'install.ps1') -ModsDirectory $ModsDirectory }
