param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("DEV","TEST","PROD")]
  [string]$Target,
  [string]$HostName="localhost",
  [int]$Port=5432,
  [string]$DbUser="postgres",
  [string]$PsqlPath="C:\Program Files\PostgreSQL\18\bin\psql.exe",
  [switch]$ConfirmProductionRelease
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Stop-Deploy([string]$Message) {
  Write-Host ""
  Write-Host "DEPLOYMENT BLOCKED: $Message" -ForegroundColor Red
  exit 1
}

function Get-RepoRelativePath([string]$BasePath,[string]$FullPath) {
  $baseFull=[System.IO.Path]::GetFullPath($BasePath)
  $full=[System.IO.Path]::GetFullPath($FullPath)
  $prefix=$baseFull
  if(-not $prefix.EndsWith("\")){ $prefix += "\" }

  if(-not $full.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)){
    throw "Path '$full' is not under repository root '$baseFull'."
  }

  return $full.Substring($prefix.Length)
}

$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifestPath=Join-Path $repoRoot "database\deploy\release-manifest.txt"
$dbMap=@{DEV="fulfilment_dev";TEST="fulfilment_test";PROD="fulfilment_prod"}
$database=$dbMap[$Target]

if (-not (Test-Path $PsqlPath -PathType Leaf)) { Stop-Deploy "psql not found at $PsqlPath" }
if (-not (Test-Path $manifestPath -PathType Leaf)) { Stop-Deploy "Missing release manifest." }

$entries=@(Get-Content $manifestPath | ForEach-Object {$_.Trim()} | Where-Object {$_ -and -not $_.StartsWith("#")})
if ($entries.Count -eq 0) { Stop-Deploy "Release manifest is empty." }

$blocked=@(
 '(^|[\\/])tests?([\\/]|$)',
 '(^|[\\/])fixtures?([\\/]|$)',
 '(^|[\\/])samples?([\\/]|$)',
 '(^|[\\/])demo([\\/]|$)',
 '(^|[\\/])load[-_]?tests?([\\/]|$)',
 '(^|[\\/])test[-_]',
 '[-_]test(s)?\.sql$',
 'fixture.*\.sql$',
 'smoke.*\.sql$',
 'load.*\.sql$'
)

$files=@()
foreach($entry in $entries){
  if([System.IO.Path]::IsPathRooted($entry)){Stop-Deploy "Manifest path must be repository-relative: $entry"}

  $n=$entry.Replace("/","\")
  if(-not $n.ToLowerInvariant().StartsWith("database\")){Stop-Deploy "Only SQL files under database\ are allowed: $entry"}

  foreach($pattern in $blocked){
    if($n -match $pattern){Stop-Deploy "Forbidden test/fixture/demo/load SQL in manifest: $entry"}
  }

  if([System.IO.Path]::GetExtension($n).ToLowerInvariant() -ne ".sql"){
    Stop-Deploy "Only .sql files are allowed: $entry"
  }

  $full=Join-Path $repoRoot $n
  if(-not (Test-Path $full -PathType Leaf)){Stop-Deploy "Manifest file does not exist: $entry"}

  $resolved=(Resolve-Path $full).Path
  try {
    [void](Get-RepoRelativePath $repoRoot $resolved)
  } catch {
    Stop-Deploy $_.Exception.Message
  }

  $files += $resolved
}

# Verify the database actually reached before any release SQL is executed.
$dbOut=& $PsqlPath -X -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $DbUser -d $database -Atc "select current_database();" 2>&1
if($LASTEXITCODE -ne 0){Stop-Deploy "Could not verify target database: $($dbOut -join ' ')"}

$actual=(($dbOut | Select-Object -Last 1).ToString()).Trim()
if($actual -ne $database){Stop-Deploy "Connected database '$actual' does not match expected '$database'."}

if($Target -eq "PROD"){
  if(-not $ConfirmProductionRelease){Stop-Deploy "PROD requires the explicit -ConfirmProductionRelease switch."}

  $trackedStatus=@(& git -C $repoRoot status --porcelain --untracked-files=no)
  if($LASTEXITCODE -ne 0){Stop-Deploy "Could not read Git status."}
  if($trackedStatus.Count -gt 0){Stop-Deploy "Tracked changes exist. PROD deploys require committed source."}

  foreach($requiredTrackedFile in @(
    "scripts/Deploy-DatabaseRelease.ps1",
    "scripts/Verify-DeploymentSafety.ps1",
    "scripts/New-DatabaseDeployInventory.ps1",
    "database/deploy/release-manifest.txt"
  )){
    & git -C $repoRoot ls-files --error-unmatch -- $requiredTrackedFile *> $null
    if($LASTEXITCODE -ne 0){Stop-Deploy "Required deployment file is not committed: $requiredTrackedFile"}
  }

  # Every SQL file in the manifest must exist in the tagged Git release.
  # This prevents PROD from executing an untracked local SQL file.
  foreach($entry in $entries){
    $gitPath=$entry.Replace("\","/")
    & git -C $repoRoot ls-files --error-unmatch -- $gitPath *> $null
    if($LASTEXITCODE -ne 0){
      Stop-Deploy "Manifest SQL is not committed to Git: $entry"
    }
  }

  $head=(& git -C $repoRoot rev-parse HEAD).Trim()
  if(-not $head){Stop-Deploy "Could not determine Git HEAD."}

  $tags=@(& git -C $repoRoot tag --points-at HEAD "dynetic-wms-v*" | Where-Object {$_})
  if($tags.Count -eq 0){Stop-Deploy "PROD requires HEAD to have a dynetic-wms-v* release tag."}

  Write-Host ""
  Write-Host "PRODUCTION RELEASE GUARD PASSED" -ForegroundColor Yellow
  Write-Host "Git HEAD : $head"
  Write-Host "Tag(s)   : $($tags -join ', ')"
  Write-Host "Manifest : all SQL files committed in this release"
}

Write-Host ""
Write-Host "DYNETIC DATABASE RELEASE DEPLOYMENT" -ForegroundColor Cyan
Write-Host "Target   : $Target"
Write-Host "Database : $database"
Write-Host "Host     : $HostName"
Write-Host "Files    : $($files.Count)"
Write-Host ""

foreach($sql in $files){
  $rel=Get-RepoRelativePath $repoRoot $sql
  Write-Host "Applying: $rel"

  & $PsqlPath -X -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $DbUser -d $database -f $sql
  if($LASTEXITCODE -ne 0){Stop-Deploy "psql failed while applying '$rel'. Remaining files were not run."}
}

Write-Host ""
Write-Host "DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "Target: $Target / $database"
