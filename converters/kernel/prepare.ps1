param(
    [Parameter(Mandatory = $true)]
    [string]$UgiiDirectory
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $UgiiDirectory).Path
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$runtime = Join-Path $project 'runtime/parasolid-win-x64'
$binding = Get-Item -LiteralPath (Join-Path $source 'managed/pskernel_net.dll')
$kernel = Get-Item -LiteralPath (Join-Path $source 'pskernel.dll')
$compiler = Get-Item -LiteralPath (Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe')
$crt = Get-Item -LiteralPath (Join-Path $env:SystemRoot 'System32/msvcr110.dll')

New-Item -ItemType Directory -Force -Path (Join-Path $runtime 'schemas') | Out-Null
Push-Location -LiteralPath $PSScriptRoot
try {
    & $compiler.FullName /nologo /unsafe /optimize+ /platform:x64 "/out:$runtime\PointViewXt.exe" "/r:$($binding.FullName)" /r:System.Web.Extensions.dll KernelHost.cs Converter.cs
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the Parasolid converter.' }
} finally {
    Pop-Location
}
Copy-Item -LiteralPath $kernel.FullName, $binding.FullName, $crt.FullName -Destination $runtime -Force
# NX 10 ships older transmit schemas in SWSchema and its current set in ugschema.
foreach ($catalog in @('SWSchema', 'ugschema')) {
    $dir = Join-Path $source $catalog
    if (Test-Path -LiteralPath $dir) {
        foreach ($file in Get-ChildItem -LiteralPath $dir -File) {
            if ($file.Name -match '^sch_([0-9_]+)\.(sch_txt|s_t)$') {
                $target = Join-Path $runtime ("schemas/sch_" + $Matches[1] + ".sch_txt")
                Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            }
        }
    }
}
Write-Output "Prepared local x64 runtime in $runtime"
