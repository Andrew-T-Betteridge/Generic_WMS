param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifestPath=Join-Path $repoRoot 'database\deploy\release-manifest.txt'
$apiPackagePath=Join-Path $repoRoot 'apps\api\package.json'
$tag="dynetic-wms-v$Version"

$trackedStatus=@(& git -C $repoRoot status --porcelain --untracked-files=no)
if($LASTEXITCODE -ne 0){
    throw 'Unable to read Git status.'
}

if($trackedStatus.Count -gt 0){
    Write-Host 'Tracked repository changes exist:'
    $trackedStatus | ForEach-Object { Write-Host $_ }

    throw 'Commit all tracked release changes before creating a release tag.'
}

if(-not (Test-Path $apiPackagePath -PathType Leaf)){
    throw 'apps/api/package.json is missing.'
}

$apiPackage=Get-Content $apiPackagePath -Raw | ConvertFrom-Json

if($apiPackage.version -ne $Version){
    throw "Requested release $Version does not match API package version $($apiPackage.version)."
}

if(-not (Test-Path $manifestPath -PathType Leaf)){
    throw 'Release manifest is missing.'
}

$manifestLines=@(
    Get-Content $manifestPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)

if($manifestLines.Count -eq 0){
    throw 'Release manifest is empty.'
}

$expectedHeader="# DYNETIC WMS $Version release manifest"

if($manifestLines[0] -ne $expectedHeader){
    throw "Release manifest header does not match requested version. Expected: $expectedHeader"
}

$entries=@(
    $manifestLines |
        Where-Object { -not $_.StartsWith('#') }
)

if($entries.Count -eq 0){
    throw 'Release manifest contains no SQL migrations.'
}

$requiredReleaseFiles=@(
    'scripts/Deploy-DatabaseRelease.ps1',
    'scripts/Verify-DeploymentSafety.ps1',
    'scripts/deploy-to-prod.ps1',
    'scripts/Bootstrap-FreshDatabase.ps1',
    'scripts/create-release-tag.ps1',
    'database/deploy/release-manifest.txt',
    'apps/api/package.json'
)

foreach($requiredFile in $requiredReleaseFiles){
    & git -C $repoRoot cat-file -e "HEAD:$requiredFile" 2>$null

    if($LASTEXITCODE -ne 0){
        throw "Required release file is not committed at HEAD: $requiredFile"
    }
}

foreach($entry in $entries){
    if([IO.Path]::IsPathRooted($entry)){
        throw "Release manifest contains an absolute path: $entry"
    }

    if($entry -match '(^|[\\/])\.\.([\\/]|$)'){
        throw "Release manifest contains path traversal: $entry"
    }

    $gitPath=$entry.Replace('\','/')

    & git -C $repoRoot cat-file -e "HEAD:$gitPath" 2>$null

    if($LASTEXITCODE -ne 0){
        throw "Release manifest file is not committed at HEAD: $entry"
    }
}

$head=(& git -C $repoRoot rev-parse HEAD).Trim()

if(-not $head){
    throw 'Unable to determine Git HEAD.'
}

$existing=@(& git -C $repoRoot tag --list $tag)

if($LASTEXITCODE -ne 0){
    throw "Unable to check existing release tag: $tag"
}

if($existing.Count -gt 0){
    $tagCommit=(& git -C $repoRoot rev-parse "$tag^{commit}").Trim()

    if($LASTEXITCODE -ne 0 -or -not $tagCommit){
        throw "Existing release tag cannot be resolved: $tag"
    }

    if($tagCommit -ne $head){
        throw "Release tag $tag already exists at $tagCommit and cannot be moved to HEAD $head."
    }

    Write-Host "[PASS] Release tag already exists at the exact current HEAD: $tag"
    exit 0
}

& git -C $repoRoot tag -a $tag -m "DYNETIC WMS $Version production release"

if($LASTEXITCODE -ne 0){
    throw "Unable to create release tag: $tag"
}

$tagCommit=(& git -C $repoRoot rev-parse "$tag^{commit}").Trim()

if($tagCommit -ne $head){
    throw "Release tag verification failed. $tag resolves to $tagCommit instead of $head."
}

Write-Host ""
Write-Host "[PASS] Created exact release tag: $tag" -ForegroundColor Green
Write-Host "Git commit : $head"
Write-Host "Version    : $Version"
Write-Host ""
Write-Host "Tag remains local until explicitly pushed:"
Write-Host "git push origin $tag"