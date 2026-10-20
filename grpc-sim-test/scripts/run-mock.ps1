# Start GripMock, run the same four simulation runbooks, then stop the mock.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$projects = Split-Path (Split-Path $root -Parent) -Parent
$runnoraProject = Join-Path $projects 'runnora'

$gripmock = [Environment]::GetEnvironmentVariable('GRIPMOCK_EXE')
if (-not $gripmock) {
    $command = Get-Command gripmock -ErrorAction Stop
    $gripmock = $command.Source
}
if (-not (Test-Path -LiteralPath $gripmock)) { throw "GripMock が見つかりません: $gripmock" }

$runnora = [Environment]::GetEnvironmentVariable('RUNNORA_EXE')
if ($runnora -and -not (Test-Path -LiteralPath $runnora)) { throw "runnora が見つかりません: $runnora" }
if (-not $runnora -and -not (Test-Path -LiteralPath (Join-Path $runnoraProject 'go.mod'))) {
    throw "runnora のソースが見つかりません: $runnoraProject"
}

Push-Location $root
$proc = $null
try {
    New-Item -ItemType Directory -Force bin, logs | Out-Null
    if (-not $runnora) {
        $runnora = Join-Path $root 'bin/runnora.exe'
        go -C $runnoraProject build -buildvcs=false -o $runnora .
        if ($LASTEXITCODE -ne 0) { throw 'runnora のビルドに失敗しました' }
    }

    $proc = Start-Process -FilePath $gripmock -PassThru -WindowStyle Hidden `
        -ArgumentList @('--stub=mock/stubs', 'proto/simulation.proto') `
        -RedirectStandardOutput (Join-Path $root 'logs/gripmock.out.log') `
        -RedirectStandardError (Join-Path $root 'logs/gripmock.err.log')
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if ($proc.HasExited) { throw 'GripMock が起動直後に終了しました（ポート重複または proto/stub エラー）' }
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:4771/api/health/readiness' -TimeoutSec 2
            if ($health.message -eq 'ok') { $ready = $true; break }
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    if (-not $ready) { throw 'GripMock が 127.0.0.1:4770 で起動しませんでした' }

    $ErrorActionPreference = 'Continue' # Windows PowerShell 5.1 handles stderr differently.
    & $runnora run --suite grpc-sim-mock 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0) { throw 'モック向け runbook の実行に失敗しました' }
} finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    Pop-Location
}
