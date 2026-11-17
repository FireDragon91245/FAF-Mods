$ErrorActionPreference = 'Stop'
$package = Join-Path $PSScriptRoot 'dist\FireDragonModLoader'
foreach ($folder in 'bin','bootstrap','sdk','examples','licenses') {
    New-Item -ItemType Directory (Join-Path $package $folder) -Force | Out-Null
}
# Remove the old 0.1 package layout, only inside this verified build output.
$obsolete = [IO.Path]::GetFullPath((Join-Path $package 'dist'))
$expected = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'dist\FireDragonModLoader\dist'))
if ($obsolete -ne $expected) { throw 'Unexpected obsolete package path' }
if (Test-Path -LiteralPath $obsolete) { Remove-Item -LiteralPath $obsolete -Recurse -Force }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'dist\FireDragonLoader.dll') -Destination (Join-Path $package 'bin\FireDragonLoader.dll')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'dist\dsound.dll') -Destination (Join-Path $package 'bootstrap\dsound.dll')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'native\include\FireDragonLoader.h') -Destination (Join-Path $package 'sdk\FireDragonLoader.h')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'native\include\firedragonmod.schema.json') -Destination (Join-Path $package 'sdk\firedragonmod.schema.json')
Copy-Item (Join-Path $PSScriptRoot 'examples\*') -Destination (Join-Path $package 'examples')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'native\third_party\nlohmann\LICENSE.MIT') -Destination (Join-Path $package 'licenses\nlohmann-json-LICENSE.MIT')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'native\third_party\minhook\LICENSE.txt') -Destination (Join-Path $package 'licenses\minhook-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src\mod_info.lua') -Destination $package
foreach ($name in 'install.ps1','install.cmd','uninstall.cmd','README.md') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $package
}
$zip = Join-Path $PSScriptRoot 'dist\FireDragonModLoader-v2.zip'
Compress-Archive -LiteralPath $package -DestinationPath $zip -Force
Write-Host "Release package: $zip"
