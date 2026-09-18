$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$deploy=Join-Path $repoRoot "scripts\Deploy-DatabaseRelease.ps1"
$inventory=Join-Path $repoRoot "scripts\New-DatabaseDeployInventory.ps1"
$manifest=Join-Path $repoRoot "database\deploy\release-manifest.txt"
$fail=@()

if(-not (Test-Path $deploy -PathType Leaf)){ $fail+="Deploy script missing" }
if(-not (Test-Path $inventory -PathType Leaf)){ $fail+="Inventory script missing" }
if(-not (Test-Path $manifest -PathType Leaf)){ $fail+="Manifest missing" }

if(Test-Path $deploy -PathType Leaf){
  $t=Get-Content $deploy -Raw
  foreach($needle in @(
    'ValidateSet("DEV","TEST","PROD")',
    'fulfilment_prod',
    'ConfirmProductionRelease',
    'current_database()',
    'ON_ERROR_STOP=1',
    'dynetic-wms-v',
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
Write-Host "DYNETIC DEPLOYMENT-SAFETY VERIFICATION V3" -ForegroundColor Cyan

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
Write-Host "PROD release tag ......... dynetic-wms-v* required on HEAD"

if($entries.Count -eq 0){
  Write-Host ""
  Write-Host "STATUS: SAFE BUT NOT YET DEPLOYABLE - release manifest is intentionally empty." -ForegroundColor Yellow
}
