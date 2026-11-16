param([switch]$NoOpen)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# A .bat launched by PowerShell 7 can pass its incompatible modules to Windows PowerShell.
$env:PSModulePath = "$PSHOME\Modules;$env:PSModulePath"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$project = (Get-Item -LiteralPath "$PSScriptRoot/..").FullName
Set-Location -LiteralPath $project
$cache = Join-Path $project '.pointview'
$nodeVersion = '22.23.5'
$arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
$nodeFolder = "node-v$nodeVersion-win-$arch"

function Test-Program($exe, [string[]]$arguments) {
    # Windows PowerShell treats redirected stderr as an error, even for probes.
    $ErrorActionPreference = 'Continue'
    & $exe @arguments *> $null
    return $LASTEXITCODE -eq 0
}

function Get-NodeDirectory {
    $localNode = Join-Path $cache "$nodeFolder/node.exe"
    $systemNode = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    foreach ($exe in @($localNode, $systemNode.Source)) {
        if (!$exe -or !(Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
        $dir = Split-Path -Parent $exe
        if (!(Test-Path -LiteralPath (Join-Path $dir 'npm.cmd'))) { continue }
        $expectedArch = if ($arch -eq 'x86') { 'ia32' } else { 'x64' }
        if (!(Test-Program $exe @('-e', "process.exit(process.arch === '$expectedArch' && parseInt(process.versions.node) >= 18 ? 0 : 1)"))) { continue }
        if (Test-Program (Join-Path $dir 'npm.cmd') @('--version')) { return $dir }
    }

    $archive = Join-Path $cache "$nodeFolder.zip"
    $hash = if ($arch -eq 'x64') {
        '4a191082e9706866830379d577d2cc8a50c776fcd9436a8d061b063ed0d9a0e3'
    } else {
        '9c01245683c87e3f81eedfbad82c1665611749627cd1b0b5a42921db9361b4a6'
    }
    Write-Host "Installing Node.js $nodeVersion ($arch) and npm in the project..."
    try {
        Invoke-WebRequest -UseBasicParsing "https://nodejs.org/dist/v$nodeVersion/$nodeFolder.zip" -OutFile $archive
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $hash) {
            throw 'The Node.js archive failed SHA-256 verification. Run start.bat again.'
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $cache -Force
    } finally {
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
    }
    return (Join-Path $cache $nodeFolder)
}

function Install-Packages($nodeDir) {
    $node = Join-Path $nodeDir 'node.exe'
    $npm = Join-Path $nodeDir 'npm.cmd'
    $stamp = Join-Path $cache 'package-lock.sha256'
    $hash = (Get-FileHash -LiteralPath 'package-lock.json' -Algorithm SHA256).Hash
    if ((Test-Path -LiteralPath $stamp) -and (Get-Content -LiteralPath $stamp -Raw).Trim() -eq $hash) {
        if ((Test-Program $npm @('ls', '--all', '--omit=dev', '--silent')) -and
            (Test-Program $node @('-e', "require('express'); require('multer')"))) { return }
    }
    Write-Host 'Installing the dependencies from package-lock.json...'
    & $npm ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed. Check the network and run start.bat again.' }
    Set-Content -LiteralPath $stamp -Value $hash -Encoding Ascii
}

function Initialize-Converter {
    if ($arch -ne 'x64') { return }
    $runtime = 'runtime/parasolid-win-x64'
    $converter = Join-Path $runtime 'PointViewXt.exe'
    # A manually prepared, licensed runtime also works in a copy without Git metadata.
    if ((Test-Path -LiteralPath '.git') -and ((Test-Path -LiteralPath "$runtime/.git") -or !(Test-Path -LiteralPath $converter))) {
        Write-Host 'Checking the private X_T runtime. GitHub may ask you to sign in on first use.'
        & git submodule update --init -- $runtime
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'Could not fetch the X_T runtime. Sign in to Git with access to PointView-3D-runtime and run start.bat again. The viewer can still start.'
        } elseif (Test-Path -LiteralPath "$runtime/.git") {
            $missing = @(& git -C $runtime ls-files --deleted)
            if ($missing.Count -gt 0) {
                & git -C $runtime restore --worktree -- $missing
                if ($LASTEXITCODE -ne 0) { throw 'Could not restore missing converter files.' }
            }
        }
    }
    if (!(Test-Path -LiteralPath $converter)) { return }
    $framework = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
    if ($framework.Release -ge 378389) { return }
    $installer = Join-Path $cache 'ndp48.exe'
    Write-Host 'Installing Microsoft .NET Framework 4.8. Windows may request administrator approval.'
    try {
        Invoke-WebRequest -UseBasicParsing 'https://go.microsoft.com/fwlink/?linkid=2088631' -OutFile $installer
        $signature = Get-AuthenticodeSignature -LiteralPath $installer
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|, )O=Microsoft Corporation(,|$)') {
            throw 'The .NET installer failed Microsoft signature verification.'
        }
        $setup = Start-Process -FilePath $installer -Verb RunAs -ArgumentList '/passive /norestart' -Wait -PassThru
        if ($setup.ExitCode -in @(1641, 3010)) { throw 'Restart Windows to finish installing .NET, then run start.bat again.' }
        if ($setup.ExitCode -ne 0) { throw "The .NET installer returned $($setup.ExitCode)." }
    } finally {
        if (Test-Path -LiteralPath $installer) { Remove-Item -LiteralPath $installer }
    }
}

function Start-Viewer($nodeDir) {
    $port = if ($env:PORT) { [int]$env:PORT } else { 3000 }
    if ($port -lt 1 -or $port -gt 65535) { throw 'PORT must be between 1 and 65535.' }
    $url = "http://localhost:$port"
    $pidFile = Join-Path $project '.server.pid'
    $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    $savedPid = if (Test-Path -LiteralPath $pidFile) { (Get-Content -LiteralPath $pidFile -Raw).Trim() }
    $server = if ($savedPid -match '^\d+$') { Get-Process -Id $savedPid -ErrorAction SilentlyContinue }
    if ($server -and $server.ProcessName -eq 'node') {
        if ($listener.OwningProcess -notcontains $server.Id) { throw "A server is already running for this checkout (PID $savedPid). Stop it before changing ports." }
        Write-Host "Server is already running (PID $savedPid)."
    } else {
        if ($listener) { throw "Port $port is already in use. Choose another PORT or stop its current process." }
        $server = Start-Process -FilePath (Join-Path $nodeDir 'node.exe') -ArgumentList 'server.js' -WorkingDirectory $project -WindowStyle Hidden -PassThru
        try {
            $deadline = (Get-Date).AddSeconds(15)
            do {
                if ($server.HasExited) { throw "The server exited with code $($server.ExitCode)." }
                try { $ready = (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 2).StatusCode -eq 200 } catch { $ready = $false }
                if ($ready) { break }
                Start-Sleep -Milliseconds 300
            } while ((Get-Date) -lt $deadline)
            if (!$ready) { throw "The server did not respond at $url within 15 seconds." }
            Set-Content -LiteralPath $pidFile -Value $server.Id -Encoding Ascii
        } catch {
            if (!$server.HasExited) { $server.Kill() }
            throw
        }
        Write-Host "Server started (PID $($server.Id))."
    }
    Write-Host $url
    if (!$NoOpen) { Start-Process $url }
}

try {
    [IO.Directory]::CreateDirectory($cache) | Out-Null
    $lock = [IO.File]::Open((Join-Path $cache 'start.lock'), 'OpenOrCreate', 'Write', 'None')
    try {
        $nodeDir = Get-NodeDirectory
        $env:PATH = "$nodeDir;$env:PATH"
        Install-Packages $nodeDir
        Initialize-Converter
        Start-Viewer $nodeDir
    } finally {
        $lock.Dispose()
    }
} catch {
    [Console]::Error.WriteLine("[ERROR] $($_.Exception.Message)")
    exit 1
}
exit 0
