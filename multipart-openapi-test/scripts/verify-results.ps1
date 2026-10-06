param([Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference = 'Stop'
$trialRoot = Split-Path $PSScriptRoot -Parent
$RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path

# Compare all JSON fields recursively; do not depend on JSON property order.
function Assert-JsonSame([object]$Expected, [object]$Actual, [string]$Path) {
    if ($null -eq $Expected) {
        if ($null -ne $Actual) { throw "Expected null at $Path" }
    } elseif ($Expected -is [pscustomobject]) {
        if ($Actual -isnot [pscustomobject]) { throw "Expected object at $Path" }
        $expectedKeys = @($Expected.PSObject.Properties.Name | Sort-Object)
        $actualKeys = @($Actual.PSObject.Properties.Name | Sort-Object)
        if (($expectedKeys -join "`0") -cne ($actualKeys -join "`0")) { throw "JSON fields differ at $Path" }
        foreach ($key in $expectedKeys) { Assert-JsonSame $Expected.$key $Actual.$key "$Path.$key" }
    } elseif ($Expected -is [array]) {
        if ($Actual -isnot [array] -or $Expected.Count -ne $Actual.Count) { throw "JSON array differs at $Path" }
        for ($i = 0; $i -lt $Expected.Count; $i++) { Assert-JsonSame $Expected[$i] $Actual[$i] "${Path}[$i]" }
    } elseif ($Expected -is [string]) {
        if ($Actual -isnot [string] -or $Expected -cne $Actual) { throw "JSON string differs at $Path" }
    } elseif ($Expected -is [bool]) {
        if ($Actual -isnot [bool] -or $Expected -ne $Actual) { throw "JSON boolean differs at $Path" }
    } elseif ($Actual -isnot [ValueType] -or $Actual -is [bool] -or $Expected -ne $Actual) {
        throw "JSON number differs at $Path"
    }
}

$report = Get-Content (Join-Path $RunDirectory 'report.json') -Raw | ConvertFrom-Json
if ($report.total -ne 3 -or $report.passed -ne 3 -or $report.failed -ne 0 -or $report.suite -ne 'generated-multipart') {
    throw 'Unexpected generated multipart suite result'
}
$expectedStatuses = @{ typed = 200; json_files = 200; legacy = 415; bad_metadata1_type = 415; bad_metadata2_type = 415; json_string = 400; wrong_csv_name = 400 }
$expectedSteps = @{ 'GENERATED-MULTIPART-001' = 4; 'GENERATED-MULTIPART-002' = 9; 'GENERATED-MULTIPART-003' = 1 }
if ((@($report.results.id | Sort-Object) -join ',') -cne (@($expectedSteps.Keys | Sort-Object) -join ',')) {
    throw 'Unexpected scenario IDs'
}
$captured = @{}
foreach ($scenario in $report.results) {
    if ($scenario.id -eq 'GENERATED-MULTIPART-003') {
        if (-not $scenario.passed -or $scenario.expect -ne 'fail' -or $scenario.actual -ne 'fail' -or
            @($scenario.steps).Count -ne 1 -or $scenario.steps[0].result -ne 'failure' -or
            $scenario.steps[0].error -notmatch 'http request failed.*invalid body: map' -or $null -ne $scenario.steps[0].evidence) {
            throw 'Expected native multipart map expansion error before HTTP transmission'
        }
        continue
    }
    if (-not $scenario.passed -or $scenario.expect -ne 'pass' -or $scenario.actual -ne 'pass' -or
        -not $expectedSteps.ContainsKey($scenario.id) -or @($scenario.steps).Count -ne $expectedSteps[$scenario.id] -or
        @($scenario.steps | Where-Object result -ne 'success').Count -ne 0) { throw 'Unexpected scenario steps' }
    foreach ($step in @($scenario.steps | Where-Object runner -eq 'http')) {
        if (-not $expectedStatuses.ContainsKey($step.key) -or $captured.ContainsKey($step.key) -or @($step.evidence).Count -ne 1) { throw 'Unexpected HTTP evidence' }
        $evidencePath = Join-Path (Join-Path $RunDirectory $report.evidenceDir) $step.evidence[0]
        $item = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        if ($item.response.status -ne $expectedStatuses[$step.key]) { throw "Unexpected HTTP status: $($step.key)" }
        $captured[$step.key] = $item
    }
}
if ($captured.Count -ne 7) { throw 'Expected seven HTTP requests' }
$metadata1 = Get-Content (Join-Path $trialRoot 'fixtures/metadata1.json') -Raw | ConvertFrom-Json
$metadata2 = Get-Content (Join-Path $trialRoot 'fixtures/metadata2.json') -Raw | ConvertFrom-Json
$csvPath = Join-Path $trialRoot 'fixtures/data.csv'
$expectedHash = (Get-FileHash $csvPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedSize = (Get-Item $csvPath).Length
$curl = Get-Content (Join-Path $trialRoot 'reports/curl-response.json') -Raw | ConvertFrom-Json
foreach ($response in @($curl, $captured.typed.response.body, $captured.json_files.response.body)) {
    Assert-JsonSame $metadata1 $response.metadata1 'metadata1'
    Assert-JsonSame $metadata2 $response.metadata2 'metadata2'
    if ($response.sha256 -ne $expectedHash -or $response.size -ne $expectedSize -or $response.rows -ne 2 -or
        $response.csvContentType -ne 'text/csv' -or $response.metadata1ContentType -ne 'application/json' -or
        $response.metadata2ContentType -ne 'application/json') { throw 'Received bytes or part Content-Types differ' }
}
if ($curl.fileName -cne 'data.csv' -or $captured.typed.response.body.fileName -cne '取込.csv' -or $captured.json_files.response.body.fileName -cne 'data.csv') { throw 'Unexpected received filenames' }
foreach ($key in @('typed', 'json_files')) {
    $request = $captured[$key].request
    $contentType = @($request.headers.'Content-Type')
    if (@($request.headers.Accept) -notcontains 'application/json' -or $contentType.Count -ne 1 -or
        $contentType[0] -notmatch '^multipart/form-data; boundary=([A-Za-z0-9]+)$') { throw "Incorrect HTTP headers: $key" }
    $boundary = $Matches[1]
    if (-not $request.body.StartsWith("--$boundary`r`n") -or -not $request.body.EndsWith("--$boundary--`r`n") -or
        -not $request.body.Contains('name="metadata1"') -or -not $request.body.Contains('name="metadata2"') -or
        -not $request.body.Contains('name="csv"') -or -not $request.body.Contains("Content-Type: text/csv`r`n")) {
        throw "Incorrect multipart body: $key"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $RunDirectory 'summary.html'))) { throw 'Missing summary.html' }
