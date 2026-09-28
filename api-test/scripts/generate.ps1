# OpenAPI からテストの雛形 (runbooks/generated/, cases/generated/) を作り直す。
# 応答は runnora が証跡として自動で保存するので、生成物には手を加えない。育てるテストは runbooks/contract/ に複製して使う。
. (Join-Path $PSScriptRoot '_common.ps1')
Push-Location $Root
try {
    # 出力先は runnora.yaml のあるフォルダ。template の接続先は ${RUNNORA_BASE_URL} で、実行時に環境 (unit / mock) の vars で決まる
    # タグ covers (表紙画像のアップロード。multipart/form-data) は対象外。生成物がファイルのパスを
    # "TODO: path/to/file" のままにし、真偽値の項目も送れないため、テストはシナリオ試験 LIB-008 に手書きしている
    & $Runnora generate --openapi openapi/library-api.yaml --tags system,books,members,loans --clean --force
    if ($LASTEXITCODE -ne 0) { throw 'runnora generate に失敗しました' }
} finally {
    Pop-Location
}
