param(
    [Parameter(Mandatory)][string]$RunDirectory
)
$ErrorActionPreference = 'Stop'
$trialRoot = Split-Path $PSScriptRoot -Parent
$RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path
$report = Get-Content (Join-Path $RunDirectory 'report.json') -Raw | ConvertFrom-Json
if ($report.total -ne 1 -or $report.passed -ne 1 -or $report.failed -ne 0 -or $report.suite -ne 'multipart') {
    throw 'Unexpected multipart suite result'
}
$scenario = @($report.results | Where-Object { $_.id -eq 'MULTIPART-001' })
if ($scenario.Count -ne 1 -or $scenario[0].actual -ne 'pass' -or @($scenario[0].steps).Count -ne 12 -or
    @($scenario[0].steps | Where-Object { $_.result -ne 'success' }).Count -ne 0) {
    throw 'Expected 12 successful MULTIPART-001 steps'
}
$httpSteps = @($scenario[0].steps | Where-Object { $_.runner -eq 'http' })
$expectedStatuses = @{ legacy = 415; typed = 200; json_file = 200; bad_json_type = 415; bad_csv_type = 415; image = 200 }
if ($httpSteps.Count -ne $expectedStatuses.Count) { throw 'Expected six HTTP steps' }
$captured = @{}
foreach ($step in $httpSteps) {
    if (-not $expectedStatuses.ContainsKey($step.key) -or $captured.ContainsKey($step.key) -or @($step.evidence).Count -ne 1) {
        throw "Unexpected HTTP step/evidence: $($step.key)"
    }
    $evidencePath = Join-Path (Join-Path $RunDirectory $report.evidenceDir) $step.evidence[0]
    $item = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    if ($item.response.status -ne $expectedStatuses[$step.key]) { throw "Unexpected status: $($step.key)" }
    $captured[$step.key] = $item
}
$csvPath = Join-Path $trialRoot 'fixtures/data.csv'
$expectedHash = (Get-FileHash $csvPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedSize = (Get-Item $csvPath).Length
$curlResponse = Get-Content (Join-Path $trialRoot 'reports/curl-response.json') -Raw | ConvertFrom-Json
foreach ($response in @($curlResponse, $captured.typed.response.body, $captured.json_file.response.body)) {
    if ($response.sha256 -ne $expectedHash -or $response.size -ne $expectedSize -or $response.rows -ne 2 -or
        $response.contentType -ne 'text/csv' -or $response.metadataContentType -ne 'application/json') {
        throw 'CSV bytes or part types differ from curl/fixture'
    }
}
foreach ($key in @('typed', 'json_file', 'image')) {
    $request = $captured[$key].request
    $contentType = @($request.headers.'Content-Type')
    if (@($request.headers.Accept) -notcontains 'application/json' -or $contentType.Count -ne 1 -or
        $contentType[0] -notmatch '^multipart/form-data; boundary=([A-Za-z0-9]+)$') {
        throw "Incorrect multipart/Accept header: $key"
    }
    $boundary = $Matches[1]
    if ($key -eq 'image') {
        # Binary request bodies are summarized by the existing evidence capturer.
        # Spring's successful parse and the received PNG hash verify this upload.
        if ($request.body -notmatch '^\(binary \d+ bytes\)$' -or
            $captured.image.response.body.contentType -ne 'image/png' -or
            $captured.image.response.body.metadataContentType -ne 'application/json') {
            throw 'Incorrect binary multipart evidence or image part types'
        }
        continue
    }
    if (-not $request.body.StartsWith("--$boundary`r`n") -or
        -not $request.body.EndsWith("--$boundary--`r`n")) {
        throw "Multipart body and boundary differ: $key"
    }
    if (-not $request.body.Contains("Content-Type: application/json`r`n")) {
        throw "Missing JSON part Content-Type: $key"
    }
}
$pngPath = Join-Path $trialRoot '../api-test/fixtures/uploads/cover.png'
if ($captured.image.response.body.sha256 -ne (Get-FileHash $pngPath -Algorithm SHA256).Hash.ToLowerInvariant() -or
    $captured.image.response.body.size -ne (Get-Item $pngPath).Length) {
    throw 'PNG bytes changed in transit'
}
if (-not (Test-Path -LiteralPath (Join-Path $RunDirectory 'summary.html'))) { throw 'Missing summary.html' }
