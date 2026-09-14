param([string]$BaseUrl="http://localhost:3001")
$ErrorActionPreference="Stop"
function Assert-True([bool]$Condition,[string]$Message){ if(-not $Condition){ throw $Message } }
Write-Host "Testing Website Domain V2 HTTP API at $BaseUrl"
$health=Invoke-RestMethod "$BaseUrl/health"; Assert-True ($health.ok -eq $true) "Health endpoint failed."
$cats=Invoke-RestMethod "$BaseUrl/api/catalog/categories"; Assert-True ($null -ne $cats) "Category endpoint failed."
$products=Invoke-RestMethod "$BaseUrl/api/catalog/products"; Assert-True ($null -ne $products) "Catalogue endpoint failed."
$search=Invoke-RestMethod "$BaseUrl/api/catalog/search?q=fry"; Assert-True ($null -ne $search) "Search endpoint failed."
$product=Invoke-RestMethod "$BaseUrl/api/catalog/products/finatics-aquatics-air-driven-fry-tray"; Assert-True ($product.productId -eq "FRYTRAY001") "Product endpoint failed."
$media=Invoke-RestMethod "$BaseUrl/api/catalog/products/finatics-aquatics-air-driven-fry-tray/media"; Assert-True ($null -ne $media) "Media endpoint failed."
$reviews=Invoke-RestMethod "$BaseUrl/api/catalog/products/finatics-aquatics-air-driven-fry-tray/reviews"; Assert-True ($null -ne $reviews) "Reviews endpoint failed."
$body=@{items=@(@{sku_id="FRYTRAY001-S-G-W-G";qty=1})}|ConvertTo-Json -Depth 6
try { $validation=Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/checkout/validate" -ContentType "application/json" -Body $body } catch { $validation=$_.ErrorDetails.Message | ConvertFrom-Json }
Assert-True ($null -ne $validation.valid) "Checkout validation endpoint did not return validation data."
Write-Host "HTTP route smoke tests passed. Mutation endpoints are covered transactionally by database test 014."
