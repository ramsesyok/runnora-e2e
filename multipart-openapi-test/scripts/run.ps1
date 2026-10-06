param([string]$RunnoraExe = $env:RUNNORA_EXE)
$ErrorActionPreference = 'Stop'
$trialRoot = Split-Path $PSScriptRoot -Parent
if (-not $RunnoraExe) { throw 'Specify -RunnoraExe or RUNNORA_EXE (v0.5.0 or a build with multipart support)' }
$RunnoraExe = (Resolve-Path -LiteralPath $RunnoraExe).Path
$logDir = Join-Path $trialRoot 'logs'
$reportDir = Join-Path $trialRoot 'reports'
New-Item -ItemType Directory -Force -Path $logDir, $reportDir | Out-Null
$javaVersion = (& java --version) -join "`n"
if ($LASTEXITCODE -ne 0 -or $javaVersion -notmatch '^(openjdk|java) 17(?:\.|\s)') { throw 'Java 17 is required' }
& mvn --batch-mode --no-transfer-progress -f (Join-Path $trialRoot 'server/pom.xml') clean package -DskipTests 2>&1 |
    Tee-Object -FilePath (Join-Path $logDir 'maven.log')
if ($LASTEXITCODE -ne 0) { throw 'OpenAPI generation / Spring Boot build failed; see logs/maven.log' }
$generatorRoot = Join-Path $trialRoot 'server/target/generated-sources/openapi'
$generatorVersion = [IO.File]::ReadAllText((Join-Path $generatorRoot '.openapi-generator/VERSION')).Trim()
$pom = [xml](Get-Content (Join-Path $trialRoot 'server/pom.xml') -Raw)
if ($generatorVersion -ne $pom.project.properties.'openapi-generator.version') { throw 'Generator version differs from pinned version' }
$runnoraVersion = & $RunnoraExe version
if ($LASTEXITCODE -ne 0) { throw 'Cannot read runnora version' }
[ordered]@{ java = $javaVersion; springBoot = $pom.project.parent.version; generator = $generatorVersion; runnora = $runnoraVersion } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $reportDir 'toolchain.json') -Encoding utf8

# Refuse to reuse an existing listener; stop only the process started below.
$portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 18083)
try { $portProbe.Start() } finally { $portProbe.Stop() }
$jarPath = Join-Path $trialRoot 'server/target/multipart-openapi-trial-0.0.1-SNAPSHOT.jar'
$server = Start-Process -FilePath (Get-Command java).Source -ArgumentList @('-Dfile.encoding=UTF-8', '-jar', "`"$jarPath`"", '--server.address=127.0.0.1', '--server.port=18083') -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $logDir 'spring.out.log') -RedirectStandardError (Join-Path $logDir 'spring.err.log')
Push-Location $trialRoot
try {
    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($server.HasExited) { throw 'Generated Spring server exited; see logs/spring.out.log' }
        try {
            $health = Invoke-RestMethod 'http://127.0.0.1:18083/health' -TimeoutSec 2
            if ($health.status -eq 'UP' -and $health.handledUploads -eq 0 -and $health.receivedUploads -eq 0) { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'Generated Spring server did not become ready' }
    & curl.exe --fail-with-body --silent --show-error 'http://127.0.0.1:18083/generated/upload' -H 'Accept: application/json' `
        -F 'metadata1=@fixtures/metadata1.json;type=application/json' -F 'metadata2=@fixtures/metadata2.json;type=application/json' `
        -F 'csv=@fixtures/data.csv;type=text/csv' -o 'reports/curl-response.json'
    if ($LASTEXITCODE -ne 0) { throw 'curl baseline against generated API failed' }
    $previousRuns = @(Get-ChildItem 'reports' -Directory | Select-Object -ExpandProperty FullName)
    & $RunnoraExe run --suite generated-multipart
    if ($LASTEXITCODE -ne 0) { throw 'Generated multipart runbooks failed' }
    $newRuns = @(Get-ChildItem 'reports' -Directory | Where-Object { $_.Name -match '^\d{8}-\d{6}-generated-multipart' -and $_.FullName -notin $previousRuns })
    if ($newRuns.Count -ne 1) { throw 'Expected exactly one new generated multipart report' }
    & (Join-Path $PSScriptRoot 'verify-results.ps1') -RunDirectory $newRuns[0].FullName
    $health = Invoke-RestMethod 'http://127.0.0.1:18083/health' -TimeoutSec 2
    if ($health.handledUploads -ne 3 -or $health.receivedUploads -ne 8) { throw 'Unexpected server request/handler counts; a client failure or rejected request reached the wrong stage' }
    $health | ConvertTo-Json | Set-Content -LiteralPath 'reports/final-health.json' -Encoding utf8
    Write-Host "Generated multipart E2E passed: 3 runbooks, 14 steps, 7 HTTP requests + 1 expected client failure; $($newRuns[0].FullName)"
} finally {
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    Pop-Location
}
