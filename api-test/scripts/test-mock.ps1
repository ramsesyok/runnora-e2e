# WireMock (oapi2wire 生成モック) に対してテストを流す。DB は使わない。
#   1. generated-mock : runnora generate が OpenAPI から作った suite (example 値・ステータスのみ検証)
#   2. contract-mock  : 契約テスト (ステータス + 本文の全体一致 + OpenAPI 応答スキーマ検証)
# 接続先 (環境 mock) と実行する runbook は runnora.yaml のスイートに書いてある。
# 事前に scripts/mock-build.ps1 と scripts/mock-start.ps1 (別ターミナル) を実行しておく。
# 結果は reports/<日時>-<スイート名>/ (summary.html・report.json・evidence/) に保存される。
. (Join-Path $PSScriptRoot '_common.ps1')
Push-Location $Root
try {
    Wait-Http "$MockUrl/health" 10
    Write-Host "== モック ($MockUrl) に対するテスト"
    $results = @(
        Invoke-Runnora -Name 'mock-generated' -Suite 'generated-mock'
        Invoke-Runnora -Name 'mock-contract' -Suite 'contract-mock'
    )
    if ((Write-RunSummary 'モック' $results) -gt 0) { exit 1 }
    exit 0
} finally {
    Pop-Location
}
