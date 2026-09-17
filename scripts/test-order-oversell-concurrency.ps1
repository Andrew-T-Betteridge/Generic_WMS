param(
    [string]$BaseUrl = "http://localhost:3001",
    [string]$SkuId = "TEST-LIVESTOCK-001-4CM",
    [string]$ProductSlug = "test-malawi-livestock-fish",
    [int]$Attempts = 10
)

$ErrorActionPreference = "Stop"

function Read-ErrorBody($err) {
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
        return $err.ErrorDetails.Message
    }

    try {
        if ($err.Exception.Response) {
            $stream = $err.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $text = $reader.ReadToEnd()
            $reader.Dispose()
            return $text
        }
    }
    catch {}

    return $null
}

function Get-AvailableQty {
    $detail = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/catalog/products/$ProductSlug"
    $variant = $detail.variants | Where-Object { $_.skuId -eq $SkuId } | Select-Object -First 1

    if (-not $variant) {
        throw "SKU $SkuId was not found on product $ProductSlug"
    }

    return [decimal]$variant.availableQty
}

Write-Host ""
Write-Host "DYNETIC ORDER OVERSELL CONCURRENCY TEST" -ForegroundColor Cyan
Write-Host "Base URL: $BaseUrl"
Write-Host "SKU:      $SkuId"
Write-Host "Attempts: $Attempts"
Write-Host ""
Write-Host "WARNING: this creates real PENDING_PAYMENT orders in the database currently configured for the API and reserves test stock." -ForegroundColor Yellow
Write-Host ""

$before = Get-AvailableQty
Write-Host "Available before test: $before"

if ($before -le 0) {
    throw "No available stock. Reset the DEV livestock fixture before running this test."
}

$runId = [Guid]::NewGuid().ToString("N")
$jobs = @()

for ($i = 1; $i -le $Attempts; $i++) {
    $idempotencyKey = "OVSELL-$runId-$i"

    $bodyObject = @{
        idempotencyKey = $idempotencyKey
        items = @(
            @{
                sku_id = $SkuId
                qty    = 1
            }
        )
        customer = @{
            name  = "Oversell Test $i"
            email = "oversell-$runId-$i@example.invalid"
        }
        deliveryAddress = @{
            name     = "Oversell Test $i"
            address1 = "1 Test Street"
            town     = "Hinckley"
            postcode = "CV13 0AA"
            country  = "GB"
        }
        fulfilmentOptionCode = "COLLECTION"
        fulfilmentPreference = "CONSOLIDATE"
    }

    $bodyJson = $bodyObject | ConvertTo-Json -Depth 20 -Compress

    $jobs += Start-Job -ArgumentList $BaseUrl, $i, $idempotencyKey, $bodyJson -ScriptBlock {
        param($BaseUrl, $Index, $IdempotencyKey, $BodyJson)

        try {
            $response = Invoke-RestMethod `
                -Method Post `
                -Uri "$BaseUrl/api/orders" `
                -ContentType "application/json" `
                -Body $BodyJson

            [pscustomobject]@{
                Index          = $Index
                IdempotencyKey = $IdempotencyKey
                Success        = $true
                HttpStatus     = 200
                OrderId        = [string]$response.orderId
                Status         = [string]$response.status
                StockReserved  = [bool]$response.stockReserved
                IdempotentReplay = [bool]$response.idempotentReplay
                BodyJson       = $BodyJson
                ErrorBody      = $null
            }
        }
        catch {
            $statusCode = 0
            try {
                if ($_.Exception.Response) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            }
            catch {}

            $errorText = $null

            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $errorText = $_.ErrorDetails.Message
            }
            else {
                try {
                    if ($_.Exception.Response) {
                        $stream = $_.Exception.Response.GetResponseStream()
                        $reader = New-Object System.IO.StreamReader($stream)
                        $errorText = $reader.ReadToEnd()
                        $reader.Dispose()
                    }
                }
                catch {}
            }

            [pscustomobject]@{
                Index          = $Index
                IdempotencyKey = $IdempotencyKey
                Success        = $false
                HttpStatus     = $statusCode
                OrderId        = $null
                Status         = $null
                StockReserved  = $false
                IdempotentReplay = $false
                BodyJson       = $BodyJson
                ErrorBody      = $errorText
            }
        }
    }
}

$results = @($jobs | Wait-Job | Receive-Job)
$jobs | Remove-Job -Force | Out-Null

$results = @($results | Sort-Object Index)

Write-Host ""
Write-Host "RESULTS" -ForegroundColor Cyan

foreach ($r in $results) {
    if ($r.Success) {
        Write-Host ("[SUCCESS] #{0} order={1} status={2} reserved={3}" -f `
            $r.Index, $r.OrderId, $r.Status, $r.StockReserved) -ForegroundColor Green
    }
    else {
        $errorSummary = $r.ErrorBody
        if ([string]::IsNullOrWhiteSpace($errorSummary)) {
            $errorSummary = "HTTP $($r.HttpStatus)"
        }
        Write-Host ("[REJECT ] #{0} http={1} {2}" -f `
            $r.Index, $r.HttpStatus, $errorSummary) -ForegroundColor Yellow
    }
}

$successful = @($results | Where-Object {
    $_.Success -and $_.StockReserved -and -not [string]::IsNullOrWhiteSpace($_.OrderId)
})

$rejected = @($results | Where-Object { -not $_.Success })

$distinctOrderIds = @(
    $successful |
    Select-Object -ExpandProperty OrderId -Unique
)

$orderIdCollision = $distinctOrderIds.Count -ne $successful.Count

$distinctOrderIds = @(
    $successful |
    Select-Object -ExpandProperty OrderId -Unique
)

$orderIdCollision = $distinctOrderIds.Count -ne $successful.Count

$after = Get-AvailableQty

Write-Host ""
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "Available before:      $before"
Write-Host "Successful reserves:   $($successful.Count)"
Write-Host "Rejected attempts:     $($rejected.Count)"
Write-Host "Available after:       $after"

$expectedSuccesses = [Math]::Min([int]$before, $Attempts)

$oversold = $successful.Count -gt [int]$before
$countWrong = $successful.Count -ne $expectedSuccesses
$availabilityWrong = $after -ne ($before - $successful.Count)

if ($orderIdCollision) {
    Write-Host "[FAIL] ORDER_ID COLLISION: multiple successful requests returned the same operational order ID." -ForegroundColor Red
}
else {
    Write-Host "[PASS] Every successful request received a distinct operational order ID." -ForegroundColor Green
}

if ($orderIdCollision) {
    Write-Host "[FAIL] ORDER_ID COLLISION: multiple successful requests returned the same operational order ID." -ForegroundColor Red
}
else {
    Write-Host "[PASS] Every successful request received a distinct operational order ID." -ForegroundColor Green
}

if ($oversold) {
    Write-Host "[FAIL] OVERSELL DETECTED: successful reservations exceeded available stock." -ForegroundColor Red
}
else {
    Write-Host "[PASS] No oversell: successful reservations did not exceed available stock." -ForegroundColor Green
}

if ($countWrong) {
    Write-Host "[FAIL] Expected $expectedSuccesses successful reservations but got $($successful.Count)." -ForegroundColor Red
}
else {
    Write-Host "[PASS] Reservation count matches available stock." -ForegroundColor Green
}

if ($availabilityWrong) {
    Write-Host "[FAIL] Availability mismatch: expected $($before - $successful.Count), got $after." -ForegroundColor Red
}
else {
    Write-Host "[PASS] Remaining availability matches successful reservations." -ForegroundColor Green
}

# Reuse one successful idempotency key AFTER stock is exhausted/reduced.
# The backend should return the SAME order rather than attempt a second allocation.
if ($successful.Count -gt 0) {
    $first = $successful | Select-Object -First 1

    Write-Host ""
    Write-Host "IDEMPOTENCY REPLAY AFTER CONTENTION" -ForegroundColor Cyan
    Write-Host "Replaying key: $($first.IdempotencyKey)"

    try {
        $replay = Invoke-RestMethod `
            -Method Post `
            -Uri "$BaseUrl/api/orders" `
            -ContentType "application/json" `
            -Body $first.BodyJson

        if ([string]$replay.orderId -eq [string]$first.OrderId) {
            Write-Host "[PASS] Replay returned the original order $($replay.orderId)." -ForegroundColor Green
        }
        else {
            Write-Host "[FAIL] Replay returned a different order. Original=$($first.OrderId), replay=$($replay.orderId)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[FAIL] Idempotency replay was rejected after contention: $($_.Exception.Message)" -ForegroundColor Red
        $body = Read-ErrorBody $_
        if ($body) {
            Write-Host $body
        }
    }
}

Write-Host ""
Write-Host "CREATED TEST ORDERS" -ForegroundColor Cyan

$orderIds = @($successful | ForEach-Object { $_.OrderId })
foreach ($id in $orderIds) {
    Write-Host $id
}

# Save order ids for cleanup/reconciliation.
$outFile = Join-Path $PSScriptRoot "last-oversell-order-ids.txt"
$orderIds | Set-Content -Path $outFile -Encoding UTF8

Write-Host ""
Write-Host "Saved order IDs to:"
Write-Host $outFile
Write-Host ""
Write-Host "Do not run this test again until these reservations are cleaned up/reset." -ForegroundColor Yellow

if ($orderIdCollision -or $oversold -or $countWrong -or $availabilityWrong) {
    exit 1
}

exit 0
