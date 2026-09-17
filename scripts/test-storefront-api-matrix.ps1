param(
    [string]$BaseUrl = "http://localhost:3001",
    [string]$Postcode = "CV13 0AA",
    [string]$Country = "GB",
    [int]$MaxVariants = 100
)

$ErrorActionPreference = "Stop"
$pass = 0
$fail = 0
$skip = 0

function Pass([string]$Name) {
    $script:pass++
    Write-Host "[PASS] $Name" -ForegroundColor Green
}

function Fail([string]$Name, [string]$Message) {
    $script:fail++
    Write-Host "[FAIL] $Name - $Message" -ForegroundColor Red
}

function Skip([string]$Name, [string]$Message) {
    $script:skip++
    Write-Host "[SKIP] $Name - $Message" -ForegroundColor Yellow
}

function Get-Json([string]$Path) {
    Invoke-RestMethod -Method Get -Uri "$BaseUrl$Path"
}

function Get-JsonItems([string]$Path) {
    $raw = Get-Json $Path

    if ($null -eq $raw) {
        return
    }

    if ($raw -is [System.Array]) {
        foreach ($item in $raw) {
            Write-Output $item
        }
    }
    else {
        Write-Output $raw
    }
}

function Post-Json([string]$Path, $Body, [switch]$Allow400) {
    try {
        return Invoke-RestMethod `
            -Method Post `
            -Uri "$BaseUrl$Path" `
            -ContentType "application/json" `
            -Body ($Body | ConvertTo-Json -Depth 20 -Compress)
    }
    catch {
        $statusCode = $null

        if ($_.Exception.Response) {
            try {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            catch {}
        }

        if ($Allow400 -and $statusCode -eq 400) {
            $text = $_.ErrorDetails.Message

            if ([string]::IsNullOrWhiteSpace($text)) {
                try {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $text = $reader.ReadToEnd()
                    $reader.Dispose()
                }
                catch {}
            }

            if (-not [string]::IsNullOrWhiteSpace($text)) {
                try {
                    return ($text | ConvertFrom-Json)
                }
                catch {
                    return [pscustomobject]@{
                        valid       = $false
                        rawResponse = $text
                        httpStatus  = 400
                    }
                }
            }

            return [pscustomobject]@{
                valid      = $false
                httpStatus = 400
            }
        }

        throw
    }
}

Write-Host "`nDYNETIC HTTP API MATRIX" -ForegroundColor Cyan
Write-Host "Base URL: $BaseUrl`n"

try {
    $null = Get-Json "/health"
    Pass "GET /health"
}
catch {
    Fail "GET /health" $_.Exception.Message
    throw "API unreachable"
}

try {
    $null = Get-Json "/api/system/version"
    Pass "GET /api/system/version"
}
catch {
    Fail "GET /api/system/version" $_.Exception.Message
}

try {
    $cats = @(Get-JsonItems "/api/catalog/categories")
    Pass "GET /api/catalog/categories ($($cats.Count))"
}
catch {
    Fail "GET /api/catalog/categories" $_.Exception.Message
    $cats = @()
}

try {
    $products = @(Get-JsonItems "/api/catalog/products")

    if ($products.Count -gt 0) {
        Pass "GET /api/catalog/products ($($products.Count))"
    }
    else {
        Fail "GET /api/catalog/products" "empty"
    }
}
catch {
    Fail "GET /api/catalog/products" $_.Exception.Message
    $products = @()
}

$variants = @()

foreach ($p in $products) {
    if ($variants.Count -ge $MaxVariants) {
        break
    }

    try {
        $detail = Get-Json "/api/catalog/products/$($p.slug)"
        $media = @(Get-JsonItems "/api/catalog/products/$($p.slug)/media")
        $null = Get-Json "/api/catalog/products/$($p.slug)/reviews"

        Pass "Product detail: $($p.slug)"
        Pass "Product media: $($p.slug) ($($media.Count))"
        Pass "Product reviews: $($p.slug)"

        foreach ($v in $detail.variants) {
            $aq = 0
            if ($null -ne $v.availableQty) {
                $aq = [decimal]$v.availableQty
            }

            $av = $false
            if ($null -ne $v.available) {
                $av = [bool]$v.available
            }

            $variants += [pscustomobject]@{
                ProductId     = $p.productId
                Slug          = $p.slug
                ProductName   = $(if ($null -ne $p.name) { $p.name } else { $p.productName })
                DeliveryClass = [string]$p.deliveryClass
                SkuId         = [string]$v.skuId
                VariantName   = $(if ($null -ne $v.name) { $v.name } else { $v.variantName })
                AvailableQty  = $aq
                Available     = $av
                Price         = $v.price
            }

            if ($variants.Count -ge $MaxVariants) {
                break
            }
        }
    }
    catch {
        Fail "Product APIs: $($p.slug)" $_.Exception.Message
    }
}

try {
    $null = Get-Json "/api/catalog/search?q=fry"
    Pass "GET /api/catalog/search"
}
catch {
    Fail "GET /api/catalog/search" $_.Exception.Message
}

$available = @(
    $variants | Where-Object {
        $_.Available -and $_.AvailableQty -gt 0
    }
)

$standard = $available |
    Where-Object { $_.DeliveryClass.ToUpperInvariant() -eq "STANDARD" } |
    Select-Object -First 1

$livestock = $available |
    Where-Object { $_.DeliveryClass.ToUpperInvariant() -eq "LIVESTOCK" } |
    Select-Object -First 1

Write-Host "Representative STANDARD: $($standard.SkuId)"
Write-Host "Representative LIVESTOCK: $($livestock.SkuId)`n"

foreach ($v in $available) {
    try {
        $r = Post-Json "/api/checkout/validate" @{
            items = @(
                @{
                    sku_id = $v.SkuId
                    qty    = 1
                }
            )
        } -Allow400

        if ($r.valid -eq $true) {
            Pass "Validate $($v.SkuId)"
        }
        else {
            Fail "Validate $($v.SkuId)" ($r | ConvertTo-Json -Depth 8 -Compress)
        }
    }
    catch {
        Fail "Validate $($v.SkuId)" $_.Exception.Message
    }
}

try {
    $r = Post-Json "/api/checkout/validate" @{
        items = @(
            @{
                sku_id = "MATRIX-NOT-A-REAL-SKU"
                qty    = 1
            }
        )
    } -Allow400

    if ($r.valid -eq $false) {
        Pass "Invalid SKU rejected"
    }
    else {
        Fail "Invalid SKU rejected" "unexpected valid response"
    }
}
catch {
    Fail "Invalid SKU rejected" $_.Exception.Message
}

function Test-BasketMatrix(
    [string]$Label,
    $Items,
    [bool]$ExpectStandard,
    [bool]$ExpectLivestock
) {
    try {
        $v = Post-Json "/api/checkout/validate" @{
            items = $Items
        } -Allow400

        if ($v.valid -ne $true) {
            Fail "$Label validate" ($v | ConvertTo-Json -Depth 8 -Compress)
            return
        }

        if (
            [bool]$v.hasStandard -ne $ExpectStandard -or
            [bool]$v.hasLivestock -ne $ExpectLivestock
        ) {
            Fail "$Label classification" "hasStandard=$($v.hasStandard), hasLivestock=$($v.hasLivestock)"
        }
        else {
            Pass "$Label classification"
        }

        $d = Post-Json "/api/delivery/options" @{
            items = $Items
            deliveryAddress = @{
                postcode = $Postcode
                country  = $Country
            }
        } -Allow400

        $options = @()
        if ($null -ne $d.fulfilmentOptions) {
            foreach ($option in $d.fulfilmentOptions) {
                $options += $option
            }
        }

        if ($d.valid -eq $true -and $options.Count -gt 0) {
            Pass "$Label delivery options"
        }
        else {
            Fail "$Label delivery options" ($d | ConvertTo-Json -Depth 8 -Compress)
            return
        }

        foreach ($opt in $options) {
            $q = Post-Json "/api/checkout/quote" @{
                items = $Items
                deliveryAddress = @{
                    postcode = $Postcode
                    country  = $Country
                }
                fulfilmentOptionCode = $opt.code
            } -Allow400

            if ($q.valid -ne $true) {
                Fail "$Label quote $($opt.code)" ($q | ConvertTo-Json -Depth 8 -Compress)
                continue
            }

            if ($null -eq $opt.price) {
                if ($q.paymentReady -eq $false -and $null -eq $q.total) {
                    Pass "$Label $($opt.code) blocks payment while unpriced"
                }
                else {
                    Fail "$Label $($opt.code)" "unpriced option became payment ready"
                }
            }
            else {
                if ($q.paymentReady -eq $true -and $null -ne $q.total) {
                    Pass "$Label $($opt.code) authoritative total=$($q.total)"
                }
                else {
                    Fail "$Label $($opt.code)" "priced option not payment ready"
                }
            }
        }
    }
    catch {
        Fail "$Label matrix" $_.Exception.Message
    }
}

if ($standard) {
    Test-BasketMatrix `
        "STANDARD" `
        @(@{ sku_id = $standard.SkuId; qty = 1 }) `
        $true `
        $false

    try {
        $r = Post-Json "/api/checkout/validate" @{
            items = @(
                @{
                    sku_id = $standard.SkuId
                    qty    = ([decimal]$standard.AvailableQty + 1)
                }
            )
        } -Allow400

        $codes = @(
            $r.errors | ForEach-Object { $_.code }
        )

        if ($r.valid -eq $false -and $codes -contains "INSUFFICIENT_STOCK") {
            Pass "STANDARD insufficient stock"
        }
        else {
            Fail "STANDARD insufficient stock" ($r | ConvertTo-Json -Depth 8 -Compress)
        }
    }
    catch {
        Fail "STANDARD insufficient stock" $_.Exception.Message
    }
}
else {
    Skip "STANDARD matrix" "No available STANDARD SKU"
}

if ($livestock) {
    Test-BasketMatrix `
        "LIVESTOCK" `
        @(@{ sku_id = $livestock.SkuId; qty = 1 }) `
        $false `
        $true
}
else {
    Skip "LIVESTOCK matrix" "No available LIVESTOCK SKU. Add real fish stock to DEV and rerun."
}

if ($standard -and $livestock) {
    Test-BasketMatrix `
        "MIXED" `
        @(
            @{ sku_id = $standard.SkuId; qty = 1 },
            @{ sku_id = $livestock.SkuId; qty = 1 }
        ) `
        $true `
        $true
}
else {
    Skip "MIXED matrix" "Need both STANDARD and LIVESTOCK stock"
}

Write-Host "`n================ API MATRIX SUMMARY ================" -ForegroundColor Cyan
Write-Host "PASS: $pass"
Write-Host "FAIL: $fail"
Write-Host "SKIP: $skip"
Write-Host "===================================================="

if ($fail -gt 0) {
    exit 1
}
else {
    exit 0
}
