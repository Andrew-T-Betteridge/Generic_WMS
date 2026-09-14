param(
    [string]$Version = "0.2.0"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $status = git status --porcelain
    if ($LASTEXITCODE -ne 0) { throw "Unable to read git status." }

    if ($status) {
        Write-Host "Repository has uncommitted changes:"
        Write-Host $status
        throw "Commit the production-readiness files before creating the release tag."
    }

    $tag = "dynetic-wms-v$Version"
    $existing = git tag --list $tag
    if ($existing) {
        Write-Host "[INFO] Git tag already exists: $tag"
        exit 0
    }

    git tag -a $tag -m "DYNETIC WMS $Version production baseline"
    if ($LASTEXITCODE -ne 0) { throw "Unable to create release tag." }

    Write-Host "[PASS] Created local release tag: $tag"
    Write-Host ""
    Write-Host "Push it when ready:"
    Write-Host "git push origin $tag"
}
finally {
    Pop-Location
}
