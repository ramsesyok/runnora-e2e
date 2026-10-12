# Regenerate runbook tables from the proto and render the Quarto book.
param([switch]$GenerateOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$projects = Split-Path (Split-Path $root -Parent) -Parent
$docgen = [Environment]::GetEnvironmentVariable('RUNNORA_DOCGEN_EXE')
if (-not $docgen) { $docgen = Join-Path $projects 'runnora-docgen/runnora-docgen.exe' }
if (-not (Test-Path -LiteralPath $docgen)) { throw "runnora-docgen が見つかりません: $docgen" }
Push-Location $root
try {
    & $docgen generate --suite grpc-sim --proto proto/simulation.proto --out docs/generated --force
    if ($LASTEXITCODE -ne 0) { throw '原稿生成に失敗しました' }
    if (-not $GenerateOnly) {
        quarto render docs --to html
        if ($LASTEXITCODE -ne 0) { throw 'HTML 発行に失敗しました' }
        Write-Host (Join-Path $root 'docs/_book/index.html')
    }
} finally {
    Pop-Location
}
