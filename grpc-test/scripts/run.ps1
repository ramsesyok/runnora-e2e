# Go 製 gRPC サーバを起動して Unary / Server streaming の runbook を実行する。
# レポート (summary.html・report.json) と各 RPC の応答 (証跡) は、runnora が reports/<日時>-grpc/ に保存する。
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
    New-Item -ItemType Directory -Force bin | Out-Null
    # サーバのログの置き場所。実行のたびに上書きする
    $logDir = Join-Path $root 'logs'
    New-Item -ItemType Directory -Force $logDir | Out-Null
    go build -buildvcs=false -o bin/libraryd.exe ./cmd/libraryd
    if ($LASTEXITCODE -ne 0) { throw 'gRPC サーバのビルドに失敗しました' }
    if (-not $runnora) {
        $runnora = Join-Path $root 'bin/runnora.exe'
        go -C $runnoraProject build -buildvcs=false -o $runnora .
        if ($LASTEXITCODE -ne 0) { throw 'runnora のビルドに失敗しました' }
    }
    $proc = Start-Process -FilePath (Join-Path $root 'bin\libraryd.exe') -PassThru -WindowStyle Hidden `
        -ArgumentList @('-proto', 'proto/library.proto') `
        -RedirectStandardOutput (Join-Path $logDir 'server.out.log') `
        -RedirectStandardError (Join-Path $logDir 'server.err.log')
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
    # 接続先は runnora.yaml、実行する runbook はスイート grpc で決まる。
    # 画面に結果の要約を出し、最後に「レポート: reports/<日時>-grpc/summary.html」を表示する
    $ErrorActionPreference = 'Continue'   # Windows PowerShell 5.1 でネイティブコマンドの stderr を例外にしない
    & $runnora run --suite grpc 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0) { throw 'runbook の実行に失敗しました' }
    & $runnora coverage --long --suite grpc |
        Tee-Object -FilePath (Join-Path $root 'reports\coverage.txt')
    if ($LASTEXITCODE -ne 0) { throw 'カバレッジの確認に失敗しました' }
} finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    Pop-Location
}
