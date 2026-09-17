param(
    [string]$BaseUrl = "http://localhost:3001",
    [string]$DatabaseName = "fulfilment_test",
    [int]$WebhookWaitSeconds = 30
)
# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety -ScriptPath $MyInvocation.MyCommand.Path -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END


$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticNonProductionApi -BaseUrl $BaseUrl
function Read-DotEnv([string]$Path) {
    $values = @{}
    if (-not (Test-Path $Path)) { throw "API .env not found: $Path" }

    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $eq = $trimmed.IndexOf("=")
        if ($eq -lt 1) { continue }
        $values[$trimmed.Substring(0,$eq).Trim()] = $trimmed.Substring($eq+1).Trim()
    }
    return $values
}

function Base64Url([byte[]]$Bytes) {
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function JsonBytes($Object) {
    [Text.Encoding]::UTF8.GetBytes(($Object | ConvertTo-Json -Compress))
}

function New-Hs256Token([string]$Secret,[string[]]$Roles=@()) {
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header=Base64Url (JsonBytes @{alg="HS256";typ="JWT"})
    $payload=Base64Url (JsonBytes @{
        sub="dynetic-stripe-lifecycle-admin"
        email="stripe-lifecycle-admin@example.invalid"
        email_verified=$true
        roles=$Roles
        iat=$now
        exp=$now+3600
    })
    $unsigned="$header.$payload"
    $hmac=[System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($Secret))
    $sig=Base64Url ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($unsigned)))
    "$unsigned.$sig"
}

function Invoke-PsqlCommand([string]$Sql) {
    $psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
    if (-not (Test-Path $psql)) { throw "psql not found at $psql" }

    & $psql -X -P pager=off -v ON_ERROR_STOP=1 `
        -h $dbHost -p $dbPort -U $dbUser -d $DatabaseName -c $Sql

    if ($LASTEXITCODE -ne 0) { throw "psql command failed." }
}

function Invoke-PsqlScalar([string]$Sql) {
    $psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
    if (-not (Test-Path $psql)) { throw "psql not found at $psql" }

    $result = & $psql -X -t -A -P pager=off -v ON_ERROR_STOP=1 `
        -h $dbHost -p $dbPort -U $dbUser -d $DatabaseName -c $Sql

    if ($LASTEXITCODE -ne 0) { throw "psql scalar command failed." }
    return (($result | Out-String).Trim())
}

function New-TestOrder([string]$Prefix) {
    $key = $Prefix + (Get-Date -Format "yyMMddHHmmssfff")

    $body = @{
        idempotencyKey = $key
        items = @(
            @{
                sku_id = "FRYTRAY001-S-G-W-G"
                qty = 1
            }
        )
        customer = @{
            name = "Stripe Lifecycle Test"
            email = "stripe-lifecycle@example.invalid"
            mobile = "07000000000"
        }
        deliveryAddress = @{
            name = "Stripe Lifecycle Test"
            address1 = "1 Test Street"
            town = "Hinckley"
            county = "Leicestershire"
            postcode = "CV13 0AA"
            country = "GB"
        }
        fulfilmentMethod = "COLLECTION"
        fulfilmentPreference = "CONSOLIDATE"
    } | ConvertTo-Json -Depth 10

    $order = Invoke-RestMethod `
        -Uri "$BaseUrl/api/orders" `
        -Method Post `
        -ContentType "application/json" `
        -Body $body

    if ($order.status -ne "PENDING_PAYMENT" -or -not $order.orderAccessToken) {
        throw "Order creation failed: $($order | ConvertTo-Json -Depth 10 -Compress)"
    }

    return @{
        orderId = [string]$order.orderId
        orderToken = [string]$order.orderAccessToken
        key = $key
    }
}

function New-StripePayment($Order) {
    $headers = @{ "X-Order-Access-Token" = $Order.orderToken }
    $body = @{
        referenceType = "ORDER"
        referenceId = $Order.orderId
        provider = "STRIPE"
        idempotencyKey = "PAY-" + $Order.key
    } | ConvertTo-Json

    $payment = Invoke-RestMethod `
        -Uri "$BaseUrl/api/payments/prepare" `
        -Method Post `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $body

    if ($payment.provider -ne "STRIPE" -or -not $payment.providerReference -or -not $payment.paymentId) {
        throw "PaymentIntent creation failed: $($payment | ConvertTo-Json -Depth 10 -Compress)"
    }

    return @{
        paymentId = [string]$payment.paymentId
        paymentIntentId = [string]$payment.providerReference
        amount = $payment.amount
        currency = $payment.currency
    }
}

function Get-Order([string]$OrderId,[string]$OrderToken) {
    Invoke-RestMethod `
        -Uri "$BaseUrl/api/orders/$OrderId" `
        -Method Get `
        -Headers @{ "X-Order-Access-Token" = $OrderToken }
}

function Get-Payment([string]$PaymentId,[string]$OrderToken) {
    Invoke-RestMethod `
        -Uri "$BaseUrl/api/payments/$PaymentId" `
        -Method Get `
        -Headers @{ "X-Order-Access-Token" = $OrderToken }
}

function Wait-ForState(
    [string]$Label,
    $Order,
    [string]$PaymentId,
    [string]$ExpectedOrderStatus,
    [string]$ExpectedPaymentStatus,
    [string]$ExpectedFulfilmentStatus,
    [int]$Seconds = 30
) {
    $deadline = (Get-Date).AddSeconds($Seconds)

    do {
        Start-Sleep -Seconds 1
        $o = Get-Order $Order.orderId $Order.orderToken
        $p = Get-Payment $PaymentId $Order.orderToken

        Write-Host ("[WAIT] {0}: Order={1} Payment={2} Fulfilment={3}" -f `
            $Label,$o.status,$p.status,$o.fulfilmentStatus)

        if (
            $o.status -eq $ExpectedOrderStatus -and
            $p.status -eq $ExpectedPaymentStatus -and
            $o.fulfilmentStatus -eq $ExpectedFulfilmentStatus
        ) {
            return @{ order=$o; payment=$p }
        }
    } while ((Get-Date) -lt $deadline)

    throw "$Label timed out. Expected $ExpectedOrderStatus / $ExpectedPaymentStatus / $ExpectedFulfilmentStatus."
}

function Confirm-StripeIntentSuccess([string]$IntentId) {
    Invoke-RestMethod `
        -Uri "https://api.stripe.com/v1/payment_intents/$IntentId/confirm" `
        -Method Post `
        -Headers $stripeHeaders `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{
            payment_method = "pm_card_visa"
            return_url = "http://localhost:5173/payment-complete"
        }
}

function Confirm-StripeIntentDeclined([string]$IntentId) {
    try {
        Invoke-RestMethod `
            -Uri "https://api.stripe.com/v1/payment_intents/$IntentId/confirm" `
            -Method Post `
            -Headers $stripeHeaders `
            -ContentType "application/x-www-form-urlencoded" `
            -Body @{
                payment_method = "pm_card_chargeDeclined"
                return_url = "http://localhost:5173/payment-complete"
            } | Out-Null
    } catch {
        # Stripe intentionally returns a non-2xx response for the decline test card.
        # The signed payment_intent.payment_failed webhook is the authoritative result.
    }
}

function Cancel-StripeIntent([string]$IntentId) {
    Invoke-RestMethod `
        -Uri "https://api.stripe.com/v1/payment_intents/$IntentId/cancel" `
        -Method Post `
        -Headers $stripeHeaders `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{}
}

function Get-StripeEvent([string]$EventId) {
    Invoke-RestMethod `
        -Uri "https://api.stripe.com/v1/events/$EventId" `
        -Method Get `
        -Headers $stripeHeaders
}

function Send-SignedStripeEventTwice([string]$EventId) {
    $event = Get-StripeEvent $EventId
    $json = $event | ConvertTo-Json -Depth 100 -Compress
    $raw = [Text.Encoding]::UTF8.GetBytes($json)
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $signedPayload = "$timestamp.$json"
    $hmac = [System.Security.Cryptography.HMACSHA256]::new(
        [Text.Encoding]::UTF8.GetBytes($webhookSecret)
    )
    $signature = (($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($signedPayload))) | ForEach-Object { $_.ToString("x2") }) -join ""
    $stripeSignature = "t=$timestamp,v1=$signature"

    $headers = @{ "Stripe-Signature" = $stripeSignature }

    $one = Invoke-RestMethod `
        -Uri "$BaseUrl/api/webhooks/stripe" `
        -Method Post `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $raw

    $two = Invoke-RestMethod `
        -Uri "$BaseUrl/api/webhooks/stripe" `
        -Method Post `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $raw

    if (-not $one.received -or -not $two.received) {
        throw "Signed webhook replay was not accepted."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot "apps\api\.env"
$envValues = Read-DotEnv $envPath

if ($envValues["DB_NAME"] -ne $DatabaseName) {
    throw "Safety stop: apps\api\.env DB_NAME is '$($envValues["DB_NAME"])'. Expected '$DatabaseName'."
}

$stripeKey = $envValues["STRIPE_SECRET_KEY"]
$webhookSecret = $envValues["STRIPE_WEBHOOK_SECRET"]
$devSecret = $envValues["AUTH_DEV_HS256_SECRET"]

if (-not $stripeKey -or -not $stripeKey.StartsWith("sk_test_")) {
    throw "Safety stop: STRIPE_SECRET_KEY must begin sk_test_."
}
if (-not $webhookSecret -or -not $webhookSecret.StartsWith("whsec_")) {
    throw "STRIPE_WEBHOOK_SECRET must be configured."
}
if ($envValues["AUTH_MODE"] -ne "DEV_HS256" -or -not $devSecret) {
    throw "This TEST script requires AUTH_MODE=DEV_HS256 and AUTH_DEV_HS256_SECRET."
}

$dbHost = if ($envValues["DB_HOST"]) { $envValues["DB_HOST"] } else { "localhost" }
$dbPort = if ($envValues["DB_PORT"]) { $envValues["DB_PORT"] } else { "5432" }
$dbUser = if ($envValues["DB_USER"]) { $envValues["DB_USER"] } else { "postgres" }

$stripeHeaders = @{ Authorization = "Bearer $stripeKey" }
$adminToken = New-Hs256Token $devSecret @("admin")
$adminHeaders = @{ Authorization = "Bearer $adminToken" }

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS STRIPE LIFECYCLE REGRESSION"
Write-Host "===================================================="
Write-Host "Database .............. $DatabaseName"
Write-Host "API ................... $BaseUrl"
Write-Host "Stripe ................ TEST/SANDBOX"
Write-Host "Secrets ............... hidden"
Write-Host "===================================================="

$health = Invoke-RestMethod -Uri "$BaseUrl/health"
if (-not $health.ok) { throw "API health failed." }
Write-Host "[PASS] API health"

$fixtureSql = @"
INSERT INTO core.LOCATION (
    LOCATION_ID,LOC_TYPE,LOCK_STATUS,VOLUME,DISALLOW_ALLOC,
    COUNT_NEEDED,ID,DESCRIPTION,ACTIVE,LIVESTOCK_ALLOWED
)
VALUES (
    'STRIPE-LIFE-LOC','STORAGE','UNLOCKED',1000000,'N',
    'N',992202,'Stripe lifecycle TEST stock','Y','Y'
)
ON CONFLICT (LOCATION_ID) DO NOTHING;

INSERT INTO core.INVENTORY (
    CLIENT_ID,SKU_ID,SITE_ID,LOCATION_ID,
    QTY_ON_HAND,QTY_ALLOCATED,LOCK_STATUS,
    RECEIPT_DSTAMP,MOVE_DSTAMP,DISALLOW_ALLOC,DESCRIPTION
)
VALUES (
    'FINATICS','FRYTRAY001-S-G-W-G','WEB','STRIPE-LIFE-LOC',
    20,0,'UNLOCKED',now(),now(),'N','Stripe lifecycle TEST inventory'
);
"@
Invoke-PsqlCommand $fixtureSql | Out-Null
Write-Host "[PASS] TEST inventory fixture"

# ---------------------------------------------------------
# 1. REAL STRIPE PAYMENT FAILURE
# ---------------------------------------------------------
Write-Host ""
Write-Host "[CASE 1] Real Stripe decline -> FAILED / PAYMENT_FAILED / CANCELLED"
$failedOrder = New-TestOrder "SFAIL"
$failedPayment = New-StripePayment $failedOrder

Confirm-StripeIntentDeclined $failedPayment.paymentIntentId

Wait-ForState `
    "DECLINE" `
    $failedOrder `
    $failedPayment.paymentId `
    "PAYMENT_FAILED" `
    "FAILED" `
    "CANCELLED" `
    $WebhookWaitSeconds | Out-Null

$failedAlloc = Invoke-PsqlScalar @"
SELECT COALESCE(SUM(QTY_SOFT_ALLOCATED),0)
FROM core.ORDER_LINE
WHERE CLIENT_ID='FINATICS' AND ORDER_ID='$($failedOrder.orderId)';
"@
if ([decimal]$failedAlloc -ne 0) {
    throw "Failed payment retained order allocation: $failedAlloc"
}
Write-Host "[PASS] Declined Stripe payment cancelled fulfilment and released stock"

# ---------------------------------------------------------
# 2. REAL STRIPE CANCELLATION
# ---------------------------------------------------------
Write-Host ""
Write-Host "[CASE 2] Real Stripe PaymentIntent cancellation"
$cancelOrder = New-TestOrder "SCAN"
$cancelPayment = New-StripePayment $cancelOrder

Cancel-StripeIntent $cancelPayment.paymentIntentId | Out-Null

Wait-ForState `
    "CANCEL" `
    $cancelOrder `
    $cancelPayment.paymentId `
    "CANCELLED" `
    "CANCELLED" `
    "CANCELLED" `
    $WebhookWaitSeconds | Out-Null

$cancelAlloc = Invoke-PsqlScalar @"
SELECT COALESCE(SUM(QTY_SOFT_ALLOCATED),0)
FROM core.ORDER_LINE
WHERE CLIENT_ID='FINATICS' AND ORDER_ID='$($cancelOrder.orderId)';
"@
if ([decimal]$cancelAlloc -ne 0) {
    throw "Cancelled payment retained order allocation: $cancelAlloc"
}
Write-Host "[PASS] Stripe cancellation released stock"

# ---------------------------------------------------------
# 3. REAL PAYMENT + ADMIN REFUND + STRIPE REFUND WEBHOOK
# ---------------------------------------------------------
Write-Host ""
Write-Host "[CASE 3] Paid Stripe order -> DYNETIC admin full refund"
$refundOrder = New-TestOrder "SREF"
$refundPayment = New-StripePayment $refundOrder

Confirm-StripeIntentSuccess $refundPayment.paymentIntentId | Out-Null

Wait-ForState `
    "PAY-FOR-REFUND" `
    $refundOrder `
    $refundPayment.paymentId `
    "NEW" `
    "PAID" `
    "ALLOCATED" `
    $WebhookWaitSeconds | Out-Null

$refundResult = Invoke-RestMethod `
    -Uri "$BaseUrl/api/admin/payments/$($refundPayment.paymentId)/refund" `
    -Method Post `
    -Headers $adminHeaders `
    -ContentType "application/json" `
    -Body "{}"

if (-not $refundResult.id) {
    throw "Stripe refund was not created."
}

$deadline = (Get-Date).AddSeconds($WebhookWaitSeconds)
do {
    Start-Sleep -Seconds 1
    $refundState = Get-Payment $refundPayment.paymentId $refundOrder.orderToken
    Write-Host "[WAIT] REFUND: Payment=$($refundState.status)"
    if ($refundState.status -eq "REFUNDED") { break }
} while ((Get-Date) -lt $deadline)

if ($refundState.status -ne "REFUNDED") {
    throw "Refund webhook did not move payment to REFUNDED."
}

$refundOrderState = Get-Order $refundOrder.orderId $refundOrder.orderToken
if ($refundOrderState.paymentStatus -ne "REFUNDED") {
    throw "Order payment status did not become REFUNDED."
}
Write-Host "[PASS] Real Stripe refund recorded through signed webhook"

# ---------------------------------------------------------
# 4. SIGNED WEBHOOK REPLAY / IDEMPOTENCY
# ---------------------------------------------------------
Write-Host ""
Write-Host "[CASE 4] Signed Stripe event replay / idempotency"

$eventId = Invoke-PsqlScalar @"
SELECT PROVIDER_EVENT_ID
FROM audit.PAYMENT_EVENT
WHERE CLIENT_ID='FINATICS'
  AND PAYMENT_ID='$($refundPayment.paymentId)'::uuid
  AND EVENT_TYPE='payment_intent.succeeded'
  AND EVENT_STATUS='PROCESSED'
ORDER BY CREATED_DSTAMP DESC
LIMIT 1;
"@

if (-not $eventId) {
    throw "Could not locate processed Stripe success event for replay test."
}

$beforeCount = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM audit.PAYMENT_EVENT
WHERE CLIENT_ID='FINATICS' AND PROVIDER_EVENT_ID='$eventId';
"@

Send-SignedStripeEventTwice $eventId

$afterCount = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM audit.PAYMENT_EVENT
WHERE CLIENT_ID='FINATICS' AND PROVIDER_EVENT_ID='$eventId';
"@

if ([int]$beforeCount -ne 1 -or [int]$afterCount -ne 1) {
    throw "Webhook replay created duplicate audit events. Before=$beforeCount After=$afterCount"
}

$replayPayment = Get-Payment $refundPayment.paymentId $refundOrder.orderToken
if ($replayPayment.status -ne "REFUNDED") {
    throw "Old replayed success event incorrectly changed a refunded payment to $($replayPayment.status)."
}
Write-Host "[PASS] Duplicate event was idempotent and did not regress payment state"

# ---------------------------------------------------------
# 5. UNPAID ORDER TIMEOUT / ADMIN EXPIRY
# ---------------------------------------------------------
Write-Host ""
Write-Host "[CASE 5] Pending-payment timeout releases stock"
$timeoutOrder = New-TestOrder "STIME"

Invoke-PsqlCommand @"
UPDATE core.ORDER_HEADER
SET PAYMENT_DUE_DSTAMP = now() - interval '1 minute'
WHERE CLIENT_ID='FINATICS' AND ORDER_ID='$($timeoutOrder.orderId)';
"@ | Out-Null

$expire = Invoke-RestMethod `
    -Uri "$BaseUrl/api/admin/reservations/expire" `
    -Method Post `
    -Headers $adminHeaders `
    -ContentType "application/json" `
    -Body "{}"

$timeoutState = Get-Order $timeoutOrder.orderId $timeoutOrder.orderToken

if (
    $timeoutState.status -ne "CANCELLED" -or
    $timeoutState.paymentStatus -ne "CANCELLED" -or
    $timeoutState.fulfilmentStatus -ne "CANCELLED"
) {
    throw "Expired pending-payment order final state is incorrect: $($timeoutState | ConvertTo-Json -Compress)"
}

$timeoutAlloc = Invoke-PsqlScalar @"
SELECT COALESCE(SUM(QTY_SOFT_ALLOCATED),0)
FROM core.ORDER_LINE
WHERE CLIENT_ID='FINATICS' AND ORDER_ID='$($timeoutOrder.orderId)';
"@

if ([decimal]$timeoutAlloc -ne 0) {
    throw "Expired pending-payment order retained allocation: $timeoutAlloc"
}
Write-Host "[PASS] Timed-out pending payment cancelled order and released stock"

Write-Host ""
Write-Host "===================================================="
Write-Host "STRIPE LIFECYCLE REGRESSION PASSED"
Write-Host "===================================================="
Write-Host "Real decline ................. PASS"
Write-Host "Real cancellation ............ PASS"
Write-Host "Real full refund ............. PASS"
Write-Host "Webhook replay/idempotency ... PASS"
Write-Host "Pending-payment timeout ...... PASS"
Write-Host "===================================================="
Write-Host ""
Write-Host "TEST records are retained for inspection."
Write-Host "Rebuild fulfilment_test to remove them."
