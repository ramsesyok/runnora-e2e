# 各スクリプトが dot-source する共通設定。
# ツールの場所は既定で隣接リポジトリ (..\runnora 等) を見る。別の場所にある場合は環境変数で上書きする。
$ErrorActionPreference = 'Stop'
$script:Root = Split-Path $PSScriptRoot -Parent
$script:Projects = Split-Path $script:Root -Parent

function Resolve-Tool {
    param([string]$EnvName, [string]$Default, [string]$CommandName)
    $candidate = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not $candidate) { $candidate = $Default }
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
    if ($CommandName) {
        $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw "$EnvName が見つかりません ($candidate)。環境変数 $EnvName でパスを指定してください。"
}

$script:Runnora = Resolve-Tool 'RUNNORA_EXE' (Join-Path $Projects 'runnora\runnora.exe') 'runnora'
$script:Oapi2wire = Resolve-Tool 'OAPI2WIRE_EXE' (Join-Path $Projects 'oapi2wire\oapi2wire.exe') 'oapi2wire'

$script:ApiUrl = 'http://127.0.0.1:18081'
$script:MockUrl = 'http://127.0.0.1:18080'

function New-ReportDir([string]$Kind) {
    $dir = Join-Path $Root ("reports\{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Kind)
    New-Item -ItemType Directory -Force $dir | Out-Null
    return $dir
}

# runnora を 1 回実行し、期待した終了コードかどうかを結果オブジェクトで返す。
function Invoke-Runnora {
    param(
        [string]$Name, [string]$Config, [string[]]$Runbooks, [string]$ReportDir,
        [string[]]$BeforeSql = @(), [string[]]$AfterSql = @(), [int]$Expect = 0
    )
    # runnora 0.x は --report-format json/junit が未実装 (text で出力される) ため text で保存する
    $runArgs = @('run', '--config', $Config, '--report-format', 'text', '--report-out', (Join-Path $ReportDir "$Name.txt"))
    foreach ($f in $BeforeSql) { $runArgs += @('--before-sql', $f) }
    foreach ($f in $AfterSql) { $runArgs += @('--after-sql', $f) }
    $runArgs += $Runbooks
    $log = Join-Path $ReportDir "$Name.log"
    # Windows PowerShell 5.1 では Stop 設定下でネイティブコマンドの stderr が例外になるため一時的に緩める
    $ErrorActionPreference = 'Continue'
    & $Runnora @runArgs *> $log
    $code = $LASTEXITCODE
    $ok = ($code -eq $Expect)
    $mark = if ($ok) { 'OK ' } else { 'NG ' }
    Write-Host ("  [{0}] {1,-28} exit={2} (expect {3})" -f $mark, $Name, $code, $Expect)
    if (-not $ok) { Get-Content $log -TotalCount 15 | ForEach-Object { Write-Host "        $_" } }
    [pscustomobject]@{ Name = $Name; Exit = $code; Expect = $Expect; Ok = $ok }
}

function Wait-Http([string]$Url, [int]$TimeoutSec = 60) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3 | Out-Null
            return
        } catch {
            if ($_.Exception.Response) { return }   # 404 等でも起動はしている
            Start-Sleep -Milliseconds 500
        }
    }
    throw "$Url が $TimeoutSec 秒以内に応答しませんでした"
}
