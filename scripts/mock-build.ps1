# OpenAPI + mock/mock-cases.yaml + mock/mock-responses/ から WireMock 資産を生成する (oapi2wire)。
#   validate : case YAML と OpenAPI の整合性を検査 (不整合は exit 1)
#   build    : mock/wiremock-out/{mappings,__files} を作り直す
. (Join-Path $PSScriptRoot '_common.ps1')
Push-Location $Root
try {
    & $Oapi2wire validate --openapi openapi/library-api.yaml --cases mock/mock-cases.yaml --responses-root mock/mock-responses
    if ($LASTEXITCODE -ne 0) { throw 'oapi2wire validate に失敗しました' }
    & $Oapi2wire build --openapi openapi/library-api.yaml --cases mock/mock-cases.yaml --responses-root mock/mock-responses `
        --out mock/wiremock-out --clean --fail-on-missing-operation --fail-on-missing-body-file
    if ($LASTEXITCODE -ne 0) { throw 'oapi2wire build に失敗しました' }
} finally {
    Pop-Location
}
