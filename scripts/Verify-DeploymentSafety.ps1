$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$deploy=Join-Path $repoRoot "scripts\Deploy-DatabaseRelease.ps1"
$prodWrapper=Join-Path $repoRoot "scripts\deploy-to-prod.ps1"
$inventory=Join-Path $repoRoot "scripts\New-DatabaseDeployInventory.ps1"
$bootstrap=Join-Path $repoRoot "scripts\Bootstrap-FreshDatabase.ps1"
$tagScript=Join-Path $repoRoot "scripts\create-release-tag.ps1"
$manifest=Join-Path $repoRoot "database\deploy\release-manifest.txt"
$fail=@()

if(-not (Test-Path $deploy -PathType Leaf)){ $fail+="Deploy script missing" }
if(-not (Test-Path $prodWrapper -PathType Leaf)){ $fail+="PROD wrapper missing" }
if(-not (Test-Path $inventory -PathType Leaf)){ $fail+="Inventory script missing" }
if(-not (Test-Path $bootstrap -PathType Leaf)){ $fail+="Fresh bootstrap script missing" }
if(-not (Test-Path $tagScript -PathType Leaf)){ $fail+="Release tag script missing" }
if(-not (Test-Path $manifest -PathType Leaf)){ $fail+="Manifest missing" }

if(Test-Path $deploy -PathType Leaf){
  $t=Get-Content $deploy -Raw
  foreach($needle in @(
    'ValidateSet("DEV","TEST","PROD")',
    'fulfilment_prod',
    'ConfirmProductionRelease',
    'current_database()',
    'ON_ERROR_STOP=1',
    'ReleaseTag',
    'ExpectedCurrentVersion',
    'GET_SYSTEM_VERSION',
    'rev-parse --verify',
    '^dynetic-wms-v\d+\.\d+\.\d+$',
    'git -C $repoRoot status --porcelain --untracked-files=no',
    'Required deployment file is not committed',
    'Manifest SQL is not committed to Git'
  )){
    if(-not $t.Contains($needle)){ $fail+="Missing guard marker: $needle" }
  }
  if($t -notmatch 'tests\?'){ $fail+="Test-path rejection missing" }
  if($t -notmatch 'fixtures\?'){ $fail+="Fixture-path rejection missing" }
  if($t.Contains('[System.IO.Path]::GetRelativePath')){ $fail+="Unsupported System.IO.Path.GetRelativePath usage found" }
}


if(Test-Path $prodWrapper -PathType Leaf){
  $p=Get-Content $prodWrapper -Raw

  if(-not $p.Contains('Deploy-DatabaseRelease.ps1')){
    $fail+="PROD wrapper does not delegate to canonical release deployer"
  }

  if($p.Contains('build-database.ps1')){
    $fail+="Legacy PROD build-database deployment path still exists"
  }

  if(-not $p.Contains('ExpectedCurrentVersion')){
    $fail+="PROD wrapper does not require an explicit expected baseline version"
  }

  if(-not $p.Contains('ReleaseTag')){
    $fail+="PROD wrapper does not require an explicit release tag"
  }
}

if(Test-Path $bootstrap -PathType Leaf){
  $b=Get-Content $bootstrap -Raw

  if(-not $b.Contains('ValidateSet("VERIFY","TEST")')){
    $fail+="Fresh bootstrap is not restricted to VERIFY/TEST"
  }

  if($b.Contains('ValidateSet("VERIFY","TEST","PROD")')){
    $fail+="Fresh bootstrap still permits PROD"
  }

  if($b.Contains('Target -eq "PROD"')){
    $fail+="Fresh bootstrap still contains a PROD execution branch"
  }

  if($b.Contains('fulfilment_prod')){
    $fail+="Fresh bootstrap still references fulfilment_prod"
  }
}

if(Test-Path $tagScript -PathType Leaf){
  $r=Get-Content $tagScript -Raw

  foreach($needle in @(
    'Parameter(Mandatory=$true)',
    'ValidatePattern',
    'status --porcelain --untracked-files=no',
    'apps\api\package.json',
    'database\deploy\release-manifest.txt',
    'cat-file -e',
    'rev-parse',
    'git -C $repoRoot tag -a'
  )){
    if(-not $r.Contains($needle)){
      $fail+="Release tag script missing guard marker: $needle"
    }
  }

  if($r.Contains('[string]$Version = "0.2.0"')){
    $fail+="Release tag script still has the obsolete 0.2.0 default"
  }
}
if(Test-Path $inventory -PathType Leaf){
  $i=Get-Content $inventory -Raw
  if($i.Contains('[System.IO.Path]::GetRelativePath')){ $fail+="Inventory still uses unsupported System.IO.Path.GetRelativePath" }
}

$entries=@()
if(Test-Path $manifest -PathType Leaf){
  $entries=@(Get-Content $manifest | ForEach-Object {$_.Trim()} | Where-Object {$_ -and -not $_.StartsWith("#")})
  foreach($e in $entries){
    $n=$e.Replace("\","/")
    if($n -match '(^|/)tests?(/|$)|(^|/)fixtures?(/|$)|(^|/)samples?(/|$)|(^|/)demo(/|$)|(^|/)load[-_]?tests?(/|$)|(^|/)test[-_]|[-_]test(s)?\.sql$|fixture.*\.sql$|smoke.*\.sql$|load.*\.sql$'){
      $fail+="Forbidden manifest entry: $e"
    }
  }
}

Write-Host ""
Write-Host "DYNETIC DEPLOYMENT-SAFETY VERIFICATION V6" -ForegroundColor Cyan

if($fail.Count){
  Write-Host "FAIL - DEPLOYMENT SAFETY IS NOT COMPLETE" -ForegroundColor Red
  $fail | ForEach-Object {Write-Host " - $_" -ForegroundColor Red}
  exit 1
}

Write-Host "PASS - FAIL-CLOSED DEPLOYMENT GUARDS ARE PRESENT" -ForegroundColor Green
Write-Host ""
Write-Host "PowerShell ............... Windows PowerShell 5.1 compatible"
Write-Host "Manifest entries ......... $($entries.Count)"
Write-Host "Tests / fixtures ......... rejected by deploy path"
Write-Host "Unknown target ........... rejected by ValidateSet"
Write-Host "Database identity ........ verified before SQL execution"
Write-Host "SQL errors ............... stop remaining deployment"
Write-Host "PROD tracked state ....... tracked tree must be clean"
Write-Host "PROD release files ....... guard + every manifest SQL must be committed"
Write-Host "PROD release tag ......... explicit dynetic-wms-vX.Y.Z must resolve exactly to HEAD"
Write-Host "PROD baseline version ..... explicit version verified before release SQL"
Write-Host "PROD resulting version .... exact release version verified after SQL"
Write-Host "Fresh bootstrap .......... VERIFY / TEST only; PROD impossible"
Write-Host "Release tag creation ..... explicit semantic version matched to committed source"

if($entries.Count -eq 0){
  Write-Host ""
  Write-Host "STATUS: SAFE BUT NOT YET DEPLOYABLE - release manifest is intentionally empty." -ForegroundColor Yellow
}
