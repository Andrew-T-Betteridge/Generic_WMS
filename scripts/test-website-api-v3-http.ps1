param(
  [string]$BaseUrl="http://localhost:3001",
  [string]$DevSecret="dynetic-local-test-secret-change-me"
)
$ErrorActionPreference="Stop"

function Base64Url([byte[]]$Bytes){
  [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}
function JsonBytes($Object){
  [Text.Encoding]::UTF8.GetBytes(($Object | ConvertTo-Json -Compress))
}
function New-Hs256Token($Secret,[string[]]$Roles=@()){
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $header=Base64Url (JsonBytes @{alg="HS256";typ="JWT"})
  $payload=Base64Url (JsonBytes @{
    sub="dynetic-v3-http-test"
    email="v3-http-test@example.invalid"
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

$token=New-Hs256Token $DevSecret @()
$adminToken=New-Hs256Token $DevSecret @("admin")
$headers=@{Authorization="Bearer $token"}

$health=Invoke-RestMethod "$BaseUrl/health"
if($health.service -ne "DYNETIC WMS API"){throw "Unexpected health service name."}

$account=Invoke-RestMethod "$BaseUrl/api/account" -Headers $headers
if(-not $account.accountId){throw "Authenticated account endpoint failed."}

$addressBody=@{
  label="HTTP Test"
  name="DYNETIC V3 HTTP"
  address1="1 Test Road"
  town="Hinckley"
  postcode="LE10 0AA"
  country="GB"
  defaultDelivery=$true
} | ConvertTo-Json
$addr=Invoke-RestMethod "$BaseUrl/api/account/addresses" -Method Post -Headers $headers -ContentType "application/json" -Body $addressBody
if(-not $addr.saved){throw "Saved address HTTP test failed."}

$catalog=Invoke-RestMethod "$BaseUrl/api/catalog/products"
if(-not $catalog -or $catalog.Count -lt 1){throw "Catalogue unavailable."}
$slug=$catalog[0].slug

Invoke-RestMethod "$BaseUrl/api/account/favourites/$slug" -Method Put -Headers $headers | Out-Null
$favs=Invoke-RestMethod "$BaseUrl/api/account/favourites" -Headers $headers
if($favs.Count -lt 1){throw "Favourite HTTP test failed."}

# Admin endpoint must reject normal customer.
try {
  Invoke-RestMethod "$BaseUrl/api/admin/affiliate/demand" -Headers $headers | Out-Null
  throw "Admin endpoint unexpectedly accepted customer token."
} catch {
  if($_.Exception.Response.StatusCode.value__ -ne 403){throw}
}

# Admin token must be accepted.
Invoke-RestMethod "$BaseUrl/api/admin/affiliate/demand" -Headers @{Authorization="Bearer $adminToken"} | Out-Null

Write-Host "DYNETIC WMS V3 HTTP authentication/security smoke tests passed."
Write-Host "Stripe network charge is intentionally NOT performed by this script."
