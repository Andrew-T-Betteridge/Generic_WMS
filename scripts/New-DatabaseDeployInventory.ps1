$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

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
$outDir=Join-Path $repoRoot "database\deploy"
$out=Join-Path $outDir "database-sql-inventory.txt"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$rows=@(
  Get-ChildItem (Join-Path $repoRoot "database") -Recurse -File -Filter "*.sql" |
    Sort-Object FullName |
    ForEach-Object {
      $r=(Get-RepoRelativePath $repoRoot $_.FullName).Replace("\","/")
      $bad=$r -match '(^|/)tests?(/|$)|(^|/)fixtures?(/|$)|(^|/)samples?(/|$)|(^|/)demo(/|$)|(^|/)load[-_]?tests?(/|$)|(^|/)test[-_]|[-_]test(s)?\.sql$|fixture.*\.sql$|smoke.*\.sql$|load.*\.sql$'

      [pscustomobject]@{
        Classification=if($bad){"BLOCKED_FROM_PROD"}else{"CANDIDATE"}
        Path=$r
      }
    }
)

$lines=@(
 "# DYNETIC database SQL inventory",
 "# Generated: $(Get-Date -Format o)",
 "# CANDIDATE means only 'not automatically blocked'; it is NOT approval for PROD.",
 ""
)

foreach($row in $rows){
  $lines += "$($row.Classification)`t$($row.Path)"
}

$lines | Set-Content $out -Encoding utf8

Write-Host ""
Write-Host "Created database SQL inventory:" -ForegroundColor Green
Write-Host $out
Write-Host ""
Write-Host "Total SQL files : $($rows.Count)"
Write-Host "Candidates      : $(($rows | Where-Object Classification -eq 'CANDIDATE').Count)"
Write-Host "Blocked         : $(($rows | Where-Object Classification -eq 'BLOCKED_FROM_PROD').Count)"
Write-Host ""
Write-Host "No SQL was executed."
