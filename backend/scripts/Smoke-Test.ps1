param([string]$BaseUrl = 'http://127.0.0.1:5080')
$ErrorActionPreference = 'Stop'
$checks = 0
function Assert($condition, [string]$message) {
    if (-not $condition) { throw $message }
    $script:checks++
}
function Request([string]$path, [string]$method = 'GET', $body = $null, [int]$expected = 200) {
    $options = @{ Uri = "$BaseUrl$path"; Method = $method; SkipHttpErrorCheck = $true; TimeoutSec = 10 }
    if ($null -ne $body) { $options.Body = ConvertTo-Json $body -Depth 10; $options.ContentType = 'application/json' }
    $response = Invoke-WebRequest @options
    Assert ($response.StatusCode -eq $expected) "$method $path expected $expected, got $($response.StatusCode): $($response.Content)"
    if ($response.Content) {
        $json = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { $response.Content }
        return ConvertFrom-Json $json -DateKind String
    }
}

# Unique client IDs allow reruns without deleting data. Use a dedicated test DB.
$suffix = [guid]::NewGuid().ToString('N')
$objects = @(Request '/objects')
$routes = @(Request '/routes/today')
Assert ($objects.Count -ge 5) 'Seed objects missing'
Assert ($routes.Count -gt 0) 'Today route missing; restart server to seed current UTC day'
$initial = Request '/sync'
$visit = @{ id = "smoke-visit-$suffix"; objectId = $objects[0].id; routeId = $routes[0].id; status = 'completed'; latitude = 55.75; longitude = 37.64; accuracy = 5; createdAt = [DateTimeOffset]::UtcNow.ToString('o'); serverVersion = $null }
$created = Request '/visits' 'POST' $visit 201
$afterVisit = @(Request '/objects')
Assert (($afterVisit | Where-Object id -eq $visit.objectId).status -eq 'visited') 'Completed visit must update object status'
$repeated = Request '/visits' 'POST' $visit
Assert ($created.serverVersion -eq 1 -and $repeated.updatedAt -eq $created.updatedAt) 'Retry must preserve version and timestamp'
$visit.status = 'failed'
$null = Request '/visits' 'POST' $visit 409
$visit.serverVersion = 1
$updated = Request '/visits' 'POST' $visit
Assert ($updated.serverVersion -eq 2) 'Update must increment version'
$visit.status = 'completed'
$null = Request '/visits' 'POST' $visit 409

$point = @{ id = "smoke-point-$suffix"; routeId = $routes[0].id; latitude = 55.75; longitude = 37.64; accuracy = 5; speed = $null; timestamp = [DateTimeOffset]::UtcNow.ToString('o') }
$batch = Request '/location/batch' 'POST' @{ points = @($point) }
$retry = Request '/location/batch' 'POST' @{ points = @($point) }
Assert ($batch.inserted -eq 1 -and $retry.inserted -eq 0 -and $retry.existing -eq 1) 'Batch retry created duplicates'
$newPoint = $point.Clone(); $newPoint.id = "rollback-$suffix"
$point.latitude = 56
$null = Request '/location/batch' 'POST' @{ points = @($newPoint, $point) } 409
$newPoint.latitude = 100
$null = Request '/location/batch' 'POST' @{ points = @($newPoint) } 400
$null = Request '/location/batch' 'POST' @{ points = @() } 400
$delta = Request ("/sync?since=" + [uri]::EscapeDataString($initial.cursor))
Assert (@($delta.visits | Where-Object id -eq $visit.id).Count -eq 1) 'Delta missing visit'
Assert (@($delta.locationPoints | Where-Object id -eq "rollback-$suffix").Count -eq 0) 'Conflicted batch was partially written'
$empty = Request ("/sync?since=" + [uri]::EscapeDataString($delta.cursor))
Assert (($empty.objects.Count + $empty.routes.Count + $empty.visits.Count + $empty.locationPoints.Count) -eq 0) 'Cursor duplicated changes'
$null = Request '/sync?since=invalid' 'GET' $null 400
$null = Request '/objects?debug=500' 'GET' $null 500
$null = Request '/objects?debug=409' 'GET' $null 409
$headerFault = Invoke-WebRequest "$BaseUrl/objects" -Headers @{ 'X-Debug-Fault' = '409' } -SkipHttpErrorCheck
Assert ($headerFault.StatusCode -eq 409) 'Header fault missing'
$timer = [Diagnostics.Stopwatch]::StartNew()
$null = Request '/objects?debug=delay&delayMs=200'
Assert ($timer.ElapsedMilliseconds -ge 190) 'Delay did not occur'
$visit.id = "timeout-$suffix"; $visit.serverVersion = $null
$timedOut = $false
try { Invoke-WebRequest "$BaseUrl/visits?debug=timeout" -Method POST -ContentType 'application/json' -Body (ConvertTo-Json $visit) -TimeoutSec 1 | Out-Null }
catch { if ($_.Exception -is [System.OperationCanceledException] -or $_.Exception.Message -match 'timeout|timed out|canceled|отмен|время') { $timedOut = $true } else { throw } }
Assert $timedOut 'Timeout fault must cause client cancellation'
$afterTimeout = Request '/sync'
Assert (@($afterTimeout.visits | Where-Object id -eq $visit.id).Count -eq 0) 'Timed-out request wrote data'
$schema = Request '/swagger/v1/swagger.json'
Assert ($null -ne $schema.paths.'/location/batch') 'Swagger endpoint missing'
Assert ($schema.components.schemas.VisitStatus.type -eq 'string') 'Swagger must describe string enums'
Write-Output "PASS: $checks checks. Persistent visit: $($created.id); cursor: $($afterTimeout.cursor)"
