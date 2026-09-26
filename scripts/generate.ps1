# OpenAPI からテストの雛形 (runbooks/generated/, cases/generated/) を作り直す。
# 生成物は再生成前提なので手で編集しない。育てるテストは runbooks/contract/ に複製して使う。
. (Join-Path $PSScriptRoot '_common.ps1')
Push-Location $Root
try {
    & $Runnora generate --config config.mock.yaml --openapi openapi/library-api.yaml --out . `
        --emit-response-example --clean --force
    if ($LASTEXITCODE -ne 0) { throw 'runnora generate に失敗しました' }
} finally {
    Pop-Location
}
