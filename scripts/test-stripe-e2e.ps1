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
    if (-not (Test-Path $Path)) {
        throw "API .env not found: $Path"
    }

    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $eq = $trimmed.IndexOf("=")
        if ($eq -lt 1) { continue }

        $name = $trimmed.Substring(0,$eq).Trim()
        $value = $trimmed.Substring($eq+1).Trim()
        $values[$name] = $value
    }
    return $values
}

function Invoke-PsqlCommand([string]$Sql) {
    $psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
    if (-not (Test-Path $psql)) {
        throw "psql not found at $psql"
    }

    $dbHost = if ($envValues["DB_HOST"]) { $envValues["DB_HOST"] } else { "localhost" }
    $dbPort = if ($envValues["DB_PORT"]) { $envValues["DB_PORT"] } else { "5432" }
    $dbUser = if ($envValues["DB_USER"]) { $envValues["DB_USER"] } else { "postgres" }

    & $psql `
        -X `
        -P pager=off `
        -v ON_ERROR_STOP=1 `
        -h $dbHost `
        -p $dbPort `
        -U $dbUser `
        -d $DatabaseName `
        -c $Sql

    if ($LASTEXITCODE -ne 0) {
        throw "psql command failed."
    }
}

function Wait-ForPaidOrder(
    [string]$OrderId,
    [string]$PaymentId,
    [string]$OrderToken,
    [int]$Seconds
) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $headers = @{ "X-Order-Access-Token" = $OrderToken }

    do {
        Start-Sleep -Seconds 1

        try {
            $order = Invoke-RestMethod `
                -Uri "$BaseUrl/api/orders/$OrderId" `
                -Method Get `
                -Headers $headers

            $payment = Invoke-RestMethod `
                -Uri "$BaseUrl/api/payments/$PaymentId" `
                -Method Get `
                -Headers $headers

            Write-Host ("[WAIT] Order={0} Payment={1} Fulfilment={2}" -f `
                $order.status,$payment.status,$order.fulfilmentStatus)

            if (
                $payment.status -eq "PAID" -and
                $order.paymentStatus -eq "PAID" -and
                $order.status -eq "NEW" -and
                $order.fulfilmentStatus -eq "ALLOCATED"
            ) {
                return @{
                    order = $order
                    payment = $payment
                }
            }
        }
        catch {
            Write-Host "[WAIT] API state not ready yet..."
        }
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for Stripe webhook to make the DYNETIC order PAID/NEW/ALLOCATED. Confirm that 'stripe listen --forward-to http://localhost:3001/api/webhooks/stripe' is still running and returning HTTP 200."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot "apps\api\.env"
$envValues = Read-DotEnv $envPath

if ($envValues["DB_NAME"] -ne $DatabaseName) {
    throw "Safety stop: apps\api\.env DB_NAME is '$($envValues["DB_NAME"])'. Expected '$DatabaseName'. This test must not run against DEV or PROD."
}

$stripeKey = $envValues["STRIPE_SECRET_KEY"]
if (-not $stripeKey -or -not $stripeKey.StartsWith("sk_test_")) {
    throw "Safety stop: STRIPE_SECRET_KEY must be a Stripe TEST/SANDBOX key beginning sk_test_."
}

if (-not $envValues["STRIPE_WEBHOOK_SECRET"]) {
    throw "STRIPE_WEBHOOK_SECRET is missing from apps\api\.env."
}

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS STRIPE END-TO-END TEST"
Write-Host "===================================================="
Write-Host "Database .............. $DatabaseName"
Write-Host "API ................... $BaseUrl"
Write-Host "Stripe key ............ TEST/SANDBOX (value hidden)"
Write-Host "Webhook secret ........ configured (value hidden)"
Write-Host "===================================================="
Write-Host ""

# API must already be running against fulfilment_test.
$health = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get
if (-not $health.ok -or $health.service -ne "DYNETIC WMS API") {
    throw "DYNETIC WMS API health check failed."
}
Write-Host "[PASS] API health"

# Add deterministic TEST-only stock for a real seeded catalogue SKU.
# This intentionally persists in fulfilment_test so the resulting order can be inspected after the test.
$fixtureSql = @"
INSERT INTO core.LOCATION (
    LOCATION_ID,LOC_TYPE,LOCK_STATUS,VOLUME,DISALLOW_ALLOC,
    COUNT_NEEDED,ID,DESCRIPTION,ACTIVE,LIVESTOCK_ALLOWED
)
VALUES (
    'STRIPE-E2E-LOC','STORAGE','UNLOCKED',1000000,'N',
    'N',992201,'Stripe E2E TEST stock','Y','Y'
)
ON CONFLICT (LOCATION_ID) DO NOTHING;

INSERT INTO core.INVENTORY (
    CLIENT_ID,SKU_ID,SITE_ID,LOCATION_ID,
    QTY_ON_HAND,QTY_ALLOCATED,LOCK_STATUS,
    RECEIPT_DSTAMP,MOVE_DSTAMP,DISALLOW_ALLOC,DESCRIPTION
)
VALUES (
    'FINATICS','FRYTRAY001-S-G-W-G','WEB','STRIPE-E2E-LOC',
    5,0,'UNLOCKED',now(),now(),'N','Stripe E2E TEST inventory'
);
"@
Invoke-PsqlCommand $fixtureSql | Out-Null
Write-Host "[PASS] TEST inventory fixture available"

$idempotency = "SE2E" + (Get-Date -Format "yyMMddHHmmssfff")

$orderBody = @{
    idempotencyKey = $idempotency
    items = @(
        @{
            sku_id = "FRYTRAY001-S-G-W-G"
            qty = 1
        }
    )
    customer = @{
        name = "Stripe E2E Test"
        email = "stripe-e2e@example.invalid"
        mobile = "07000000000"
    }
    deliveryAddress = @{
        name = "Stripe E2E Test"
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
    -Body $orderBody

if ($order.status -ne "PENDING_PAYMENT") {
    throw "Order did not enter PENDING_PAYMENT. Response: $($order | ConvertTo-Json -Depth 10 -Compress)"
}
if (-not $order.orderAccessToken) {
    throw "Guest order did not return an orderAccessToken."
}

$orderId = [string]$order.orderId
$orderToken = [string]$order.orderAccessToken

Write-Host "[PASS] DYNETIC order created"
Write-Host "       Order ID: $orderId"
Write-Host "       State: PENDING_PAYMENT / RESERVED"

$paymentIdempotency = "PAY-" + $idempotency
$paymentBody = @{
    referenceType = "ORDER"
    referenceId = $orderId
    provider = "STRIPE"
    idempotencyKey = $paymentIdempotency
} | ConvertTo-Json

$guestHeaders = @{
    "X-Order-Access-Token" = $orderToken
}

$payment = Invoke-RestMethod `
    -Uri "$BaseUrl/api/payments/prepare" `
    -Method Post `
    -Headers $guestHeaders `
    -ContentType "application/json" `
    -Body $paymentBody

if ($payment.provider -ne "STRIPE" -or -not $payment.providerReference -or -not $payment.paymentId) {
    throw "Stripe PaymentIntent was not created correctly. Response: $($payment | ConvertTo-Json -Depth 10 -Compress)"
}

$paymentId = [string]$payment.paymentId
$paymentIntentId = [string]$payment.providerReference

Write-Host "[PASS] Stripe PaymentIntent created"
Write-Host "       Payment ID: $paymentId"
Write-Host "       Stripe PaymentIntent: $paymentIntentId"
Write-Host "       Amount: $($payment.amount) $($payment.currency)"

# Confirm the exact PaymentIntent created by DYNETIC.
# The test-mode PaymentMethod pm_card_visa succeeds without using real card data.
$stripeHeaders = @{
    Authorization = "Bearer $stripeKey"
}

$confirmBody = @{
    payment_method = "pm_card_visa"
    return_url = "http://localhost:5173/payment-complete"
}

$confirmed = Invoke-RestMethod `
    -Uri "https://api.stripe.com/v1/payment_intents/$paymentIntentId/confirm" `
    -Method Post `
    -Headers $stripeHeaders `
    -ContentType "application/x-www-form-urlencoded" `
    -Body $confirmBody

if ($confirmed.id -ne $paymentIntentId) {
    throw "Stripe returned an unexpected PaymentIntent."
}

Write-Host "[PASS] Exact Stripe PaymentIntent confirmed"
Write-Host "       Stripe status: $($confirmed.status)"
Write-Host "[WAIT] Waiting for signed Stripe webhook to update DYNETIC..."

$result = Wait-ForPaidOrder `
    -OrderId $orderId `
    -PaymentId $paymentId `
    -OrderToken $orderToken `
    -Seconds $WebhookWaitSeconds

# Database assertions include the webhook audit ledger and the live reservation.
$assertSql = @"
DO `$`$
DECLARE
    v_order_status VARCHAR(15);
    v_payment_status VARCHAR(30);
    v_fulfilment_status VARCHAR(30);
    v_provider_reference VARCHAR(150);
    v_payment_events INTEGER;
    v_qty_alloc NUMERIC;
BEGIN
    SELECT STATUS,PAYMENT_STATUS,FULFILMENT_STATUS
      INTO v_order_status,v_payment_status,v_fulfilment_status
      FROM core.ORDER_HEADER
     WHERE CLIENT_ID='FINATICS' AND ORDER_ID='$orderId';

    IF v_order_status <> 'NEW'
       OR v_payment_status <> 'PAID'
       OR v_fulfilment_status <> 'ALLOCATED' THEN
        RAISE EXCEPTION 'Unexpected final order state: % / % / %',
            v_order_status,v_payment_status,v_fulfilment_status;
    END IF;

    SELECT PROVIDER_REFERENCE
      INTO v_provider_reference
      FROM core.PAYMENT_TRANSACTION
     WHERE CLIENT_ID='FINATICS'
       AND PAYMENT_ID='$paymentId'::uuid
       AND STATUS='PAID';

    IF v_provider_reference <> '$paymentIntentId' THEN
        RAISE EXCEPTION 'Provider reference mismatch.';
    END IF;

    SELECT COUNT(*)
      INTO v_payment_events
      FROM audit.PAYMENT_EVENT
     WHERE CLIENT_ID='FINATICS'
       AND PAYMENT_ID='$paymentId'::uuid
       AND EVENT_TYPE='payment_intent.succeeded'
       AND EVENT_STATUS='PROCESSED';

    IF v_payment_events <> 1 THEN
        RAISE EXCEPTION 'Expected one processed payment_intent.succeeded audit event; got %',
            v_payment_events;
    END IF;

    SELECT COALESCE(SUM(QTY_SOFT_ALLOCATED),0)
      INTO v_qty_alloc
      FROM core.ORDER_LINE
     WHERE CLIENT_ID='FINATICS'
       AND ORDER_ID='$orderId';

    IF v_qty_alloc <> 1 THEN
        RAISE EXCEPTION 'Expected order to retain 1 allocated unit after payment; got %',
            v_qty_alloc;
    END IF;
END
`$`$;
"@
Invoke-PsqlCommand $assertSql | Out-Null

Write-Host "[PASS] Database state reconciled"
Write-Host ""
Write-Host "===================================================="
Write-Host "STRIPE END-TO-END PAYMENT TEST PASSED"
Write-Host "===================================================="
Write-Host "Order .................. $orderId"
Write-Host "Payment ................ $paymentId"
Write-Host "Stripe Intent .......... $paymentIntentId"
Write-Host "Payment status ......... PAID"
Write-Host "Order status ........... NEW"
Write-Host "Fulfilment status ...... ALLOCATED"
Write-Host "Payment audit event .... PASS"
Write-Host "Inventory allocation ... PASS"
Write-Host "===================================================="
Write-Host ""
Write-Host "The TEST order is intentionally retained in fulfilment_test for inspection."
Write-Host "Rebuilding TEST with create-test-db.ps1/test-full-regression.ps1 will remove it."
