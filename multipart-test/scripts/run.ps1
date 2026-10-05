param(
    [string]$RunnoraExe = $env:RUNNORA_EXE,
    [switch]$UseCachedJars
)
$ErrorActionPreference = 'Stop'
$trialRoot = Split-Path $PSScriptRoot -Parent
if (-not $RunnoraExe) { $RunnoraExe = Join-Path (Split-Path $trialRoot -Parent) 'api-test/bin/runnora-multipart.exe' }
$RunnoraExe = (Resolve-Path -LiteralPath $RunnoraExe).Path
& (Join-Path $PSScriptRoot 'build-server.ps1') -UseCachedJars:$UseCachedJars
$logDir = Join-Path $trialRoot 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$javaArgs = if ($UseCachedJars) {
    $classPath = [IO.File]::ReadAllText((Join-Path $trialRoot 'server/target/classpath.txt'))
    @('-cp', "`"$classPath`"", 'trial.MultipartApplication')
} else {
    @('-jar', "`"$(Join-Path $trialRoot 'server/target/multipart-trial-0.0.1-SNAPSHOT.jar')`"")
}
$javaArgs += @('--server.address=127.0.0.1', '--server.port=18082')
$server = Start-Process -FilePath (Get-Command java).Source -ArgumentList $javaArgs -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $logDir 'spring.out.log') -RedirectStandardError (Join-Path $logDir 'spring.err.log')
Push-Location $trialRoot
try {
    $ready = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($server.HasExited) { throw 'Spring Boot exited; see logs/spring.out.log and spring.err.log' }
        try {
            $health = Invoke-RestMethod 'http://127.0.0.1:18082/health' -TimeoutSec 2
            if ($health.status -eq 'UP') { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'Spring Boot did not become ready' }
    New-Item -ItemType Directory -Force 'reports' | Out-Null
    & curl.exe --fail-with-body --silent --show-error 'http://127.0.0.1:18082/upload' `
        -H 'Accept: application/json' `
        -F 'metadata=@fixtures/metadata.json;type=application/json' `
        -F 'file=@fixtures/data.csv;type=text/csv' `
        -o 'reports/curl-response.json'
    if ($LASTEXITCODE -ne 0) { throw 'curl baseline failed' }
    $curlResponse = Get-Content 'reports/curl-response.json' -Raw | ConvertFrom-Json
    $expectedHash = (Get-FileHash 'fixtures/data.csv' -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($curlResponse.sha256 -ne $expectedHash) { throw 'curl file hash differs from fixture' }
    & $RunnoraExe run --suite multipart
    if ($LASTEXITCODE -ne 0) { throw "multipart trial failed (exit $LASTEXITCODE)" }
    $latestRun = Get-ChildItem 'reports' -Directory | Where-Object {$_.Name -match '^\d{8}-\d{6}-multipart'} | Sort-Object CreationTime | Select-Object -Last 1
    $typedEvidence = Get-Content (Join-Path $latestRun.FullName 'evidence/MULTIPART-001/03-typed.json') -Raw | ConvertFrom-Json
    if ($typedEvidence.response.body.sha256 -ne $expectedHash -or $typedEvidence.response.body.size -ne $curlResponse.size) {
        throw 'runnora received bytes differ from curl/fixture'
    }
} finally {
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    Pop-Location
}
