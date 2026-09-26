# Go 製 gRPC サーバを起動して Unary / Server streaming の runbook を実行する。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$projects = Split-Path (Split-Path $root -Parent) -Parent
$runnora = [Environment]::GetEnvironmentVariable('RUNNORA_EXE')
if (-not $runnora) { $runnora = Join-Path $projects 'runnora\runnora.exe' }
if (-not (Test-Path -LiteralPath $runnora)) { throw "runnora が見つかりません: $runnora" }

Push-Location $root
$proc = $null
try {
    New-Item -ItemType Directory -Force bin | Out-Null
    $reportDir = Join-Path $root ('reports\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force $reportDir | Out-Null
    go build -o bin/libraryd.exe ./cmd/libraryd
    if ($LASTEXITCODE -ne 0) { throw 'gRPC サーバのビルドに失敗しました' }
    $proc = Start-Process -FilePath (Join-Path $root 'bin\libraryd.exe') -PassThru -WindowStyle Hidden `
        -ArgumentList @('-proto', 'proto/library.proto') `
        -RedirectStandardOutput (Join-Path $reportDir 'server.out.log') `
        -RedirectStandardError (Join-Path $reportDir 'server.err.log')
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if ($proc.HasExited) { throw 'gRPC サーバが起動直後に終了しました（ポート重複または proto の読み込みエラー）' }
        $client = New-Object Net.Sockets.TcpClient
        try {
            $client.Connect('127.0.0.1', 19090)
            $ready = $true
            break
        } catch {
            Start-Sleep -Milliseconds 200
        } finally {
            $client.Dispose()
        }
    }
    if (-not $ready) { throw 'gRPC サーバが 127.0.0.1:19090 で起動しませんでした' }
    & $runnora run --config config.yaml --report-format text `
        --report-out (Join-Path $reportDir 'runnora.txt') `
        runbooks/unary.yml runbooks/server-streaming.yml runbooks/calculation-streaming.yml
    if ($LASTEXITCODE -ne 0) {
        Get-Content (Join-Path $reportDir 'runnora.txt')
        throw 'runbook の実行に失敗しました'
    }
    Get-Content (Join-Path $reportDir 'runnora.txt')
    & $runnora coverage --long runbooks/unary.yml runbooks/server-streaming.yml runbooks/calculation-streaming.yml |
        Tee-Object -FilePath (Join-Path $reportDir 'coverage.txt')
    if ($LASTEXITCODE -ne 0) { throw 'カバレッジの確認に失敗しました' }
    Write-Host "レポート: $reportDir"
} finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    Pop-Location
}
