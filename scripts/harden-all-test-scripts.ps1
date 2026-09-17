param(
    [string]$RepoRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path $RepoRoot).Path
$scriptsPath = Join-Path $RepoRoot "scripts"
$helperPath = Join-Path $scriptsPath "Test-Safety.ps1"

if (-not (Test-Path $helperPath)) {
    throw "Missing scripts/Test-Safety.ps1. Replace it with the V2 file first."
}

function Write-Utf8NoBom {
    param([string]$Path,[string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path,$Content,$utf8NoBom)
}

Write-Host ""
Write-Host "DYNETIC TEST WRAPPER HARDENING V2" -ForegroundColor Cyan
Write-Host "Repository: $RepoRoot"
Write-Host ""

$files = @(Get-ChildItem $scriptsPath -File -Filter "test-*.ps1")

foreach ($file in $files) {
    if ($file.Name -ieq "Test-Safety.ps1") { continue }

    $content = Get-Content $file.FullName -Raw

    if ($file.Name -like "test-prod-*") {
        # test-prod-smoke is already a hard stop. Other test-prod-* scripts
        # receive the universal preflight, which stops purely from the filename.
        if ($content -match 'SAFETY STOP - PROD TEST EXECUTION IS DISABLED') {
            Write-Host "[OK] permanently disabled: $($file.Name)" -ForegroundColor Green
            continue
        }
    }

    if ($content -match 'Assert-DyneticTestScriptSafety') {
        Write-Host "[OK] universal guard already present: $($file.Name)"
        continue
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    )

    if ($errors.Count -gt 0) {
        throw "Cannot safely patch $($file.Name): PowerShell parser reported errors."
    }

    $insertAt = 0
    if ($null -ne $ast.ParamBlock) {
        $insertAt = $ast.ParamBlock.Extent.EndOffset
    }

    $guard = @'

# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety -ScriptPath $MyInvocation.MyCommand.Path -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END

'@

    $content = $content.Insert($insertAt,$guard)
    Write-Utf8NoBom -Path $file.FullName -Content $content
    Write-Host "[UPDATED] universal fail-closed guard: $($file.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Wrapper hardening complete." -ForegroundColor Cyan
Write-Host "Run .\scripts\verify-prod-test-safety.ps1 next."
