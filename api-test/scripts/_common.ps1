# 各スクリプトが dot-source する共通設定。
# ツールの場所は既定で隣接リポジトリ (runnora-e2e と並ぶ ..\..\runnora 等) を見る。別の場所にある場合は環境変数で上書きする。
$ErrorActionPreference = 'Stop'
$script:Root = Split-Path $PSScriptRoot -Parent
# Root はテストセットのフォルダ (runnora-e2e/api-test)。兄弟リポジトリ (runnora 等) はリポジトリの 1 つ上にある
$script:Projects = Split-Path (Split-Path $script:Root -Parent) -Parent

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

# 起動を待つための URL。runbook の接続先は runnora.yaml の環境 (unit / mock) の vars に書く
$script:ApiUrl = 'http://127.0.0.1:18081'
$script:MockUrl = 'http://127.0.0.1:18080'

# サーバ (API / WireMock) のログの置き場所。実行のたびに上書きする
function Get-LogDir {
    $dir = Join-Path $Root 'logs'
    New-Item -ItemType Directory -Force $dir | Out-Null
    return $dir
}

# runnora.yaml のスイートを 1 つ実行し、成功したかどうかと実行ごとのフォルダを結果オブジェクトで返す。
# 環境 (接続先・共通の前後処理)、runbook ごとの前後処理、期待する結果 (expect) は
# runnora.yaml と各 runbook の runnora: ブロックに書いてあるので、ここではスイート名だけを渡す。
# runnora は全 runbook が期待どおりなら 0 を返す (期待どおりのフック失敗も 0)。
# レポート (report.json / summary.html) と各ステップの応答 (証跡) は、runnora が
# reports/<日時>-<スイート名>/ に保存する。画面の出力はそのフォルダの runnora.log に残す。
function Invoke-Runnora {
    param([string]$Name, [string]$Suite)
    $reports = Join-Path $Root 'reports'
    New-Item -ItemType Directory -Force $reports | Out-Null
    $log = Join-Path $reports "$Name.log"
    # Windows PowerShell 5.1 では Stop 設定下でネイティブコマンドの stderr が例外になるため一時的に緩める
    $ErrorActionPreference = 'Continue'
    & $Runnora run --suite $Suite *> $log
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $runDir = Get-RunFolder $Suite
    if ($runDir) {
        Move-Item -LiteralPath $log -Destination (Join-Path $runDir 'runnora.log') -Force
        $log = Join-Path $runDir 'runnora.log'
    }
    $ok = ($code -eq 0)
    $mark = if ($ok) { 'OK ' } else { 'NG ' }
    Write-Host ("  [{0}] {1,-28} suite={2} exit={3}" -f $mark, $Name, $Suite, $code)
    if (-not $ok) { Get-Content $log -TotalCount 15 | ForEach-Object { Write-Host "        $_" } }
    [pscustomobject]@{ Name = $Name; Exit = $code; Ok = $ok; Report = $runDir }
}

# runnora がスイートの実行で作った最新のフォルダ (reports/<日時>-<スイート名>[-n]) を返す。なければ $null。
function Get-RunFolder([string]$Suite) {
    $pattern = '^\d{8}-\d{6}-' + [regex]::Escape($Suite) + '(-\d+)?$'
    Get-ChildItem -LiteralPath (Join-Path $Root 'reports') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        Sort-Object CreationTime, Name |
        Select-Object -Last 1 -ExpandProperty FullName
}

# 結果の一覧と、各スイートのサマリー HTML の場所を表示する
function Write-RunSummary([string]$Title, $Results) {
    $failed = @($Results | Where-Object { -not $_.Ok })
    Write-Host ("{0}: {1}/{2} OK" -f $Title, ($Results.Count - $failed.Count), $Results.Count)
    foreach ($r in $Results) {
        if ($r.Report) { Write-Host ("  {0,-28} {1}" -f $r.Name, (Join-Path $r.Report 'summary.html')) }
    }
    return $failed.Count
}

# ディレクトリを削除する。直前に書いたファイルをエディタやウイルス対策が一時的に掴んでいると
# Remove-Item が IOException で失敗することがあるため、間隔を空けて数回やり直す。
function Remove-DirectoryWithRetry([string]$Path, [int]$Attempts = 5, [int]$DelayMs = 500) {
    for ($i = 1; $i -le $Attempts; $i++) {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($i -eq $Attempts) { throw }
            Write-Host "  $Path を削除できませんでした (使用中のファイルあり)。再試行します ($i/$Attempts)"
            Start-Sleep -Milliseconds ($DelayMs * $i)
        }
    }
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
