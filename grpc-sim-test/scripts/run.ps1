# Build the server and runnora, run all simulation cases, then stop the server.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$projects = Split-Path (Split-Path $root -Parent) -Parent
$runnora = [Environment]::GetEnvironmentVariable('RUNNORA_EXE')
$runnoraProject = Join-Path $projects 'runnora'
if ($runnora -and -not (Test-Path -LiteralPath $runnora)) { throw "runnora が見つかりません: $runnora" }
if (-not $runnora -and -not (Test-Path -LiteralPath (Join-Path $runnoraProject 'go.mod'))) {
    throw "runnora のソースが見つかりません: $runnoraProject"
}

Push-Location $root
$proc = $null
try {
    New-Item -ItemType Directory -Force bin, logs | Out-Null
    go build -buildvcs=false -o bin/simd.exe ./cmd/simd
    if ($LASTEXITCODE -ne 0) { throw 'simd のビルドに失敗しました' }
    if (-not $runnora) {
        $runnora = Join-Path $root 'bin/runnora.exe'
        go -C $runnoraProject build -buildvcs=false -o $runnora .
        if ($LASTEXITCODE -ne 0) { throw 'runnora のビルドに失敗しました' }
    }
    $proc = Start-Process -FilePath (Join-Path $root 'bin/simd.exe') -PassThru -WindowStyle Hidden `
        -ArgumentList @('-proto', 'proto/simulation.proto') `
        -RedirectStandardOutput (Join-Path $root 'logs/server.out.log') `
        -RedirectStandardError (Join-Path $root 'logs/server.err.log')
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if ($proc.HasExited) { throw 'simd が起動直後に終了しました（ポート重複または proto エラー）' }
        $client = New-Object Net.Sockets.TcpClient
        try {
            $client.Connect('127.0.0.1', 19091)
            $ready = $true
            break
        } catch {
            Start-Sleep -Milliseconds 200
        } finally {
            $client.Dispose()
        }
    }
    if (-not $ready) { throw 'simd が 127.0.0.1:19091 で起動しませんでした' }
    $ErrorActionPreference = 'Continue' # Windows PowerShell 5.1 handles stderr differently.
    & $runnora run --suite grpc-sim 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0) { throw 'runbook の実行に失敗しました' }
    & $runnora coverage --long --suite grpc-sim |
        Tee-Object -FilePath (Join-Path $root 'reports/coverage.txt')
    if ($LASTEXITCODE -ne 0) { throw 'カバレッジの確認に失敗しました' }
} finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    Pop-Location
}
