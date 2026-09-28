param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^dynetic-wms-v\d+\.\d+\.\d+$')]
    [string]$ReleaseTag,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$ExpectedCurrentVersion,

    [string]$HostName='localhost',
    [int]$Port=5432,
    [string]$DbUser='postgres',
    [string]$PsqlPath='C:\Program Files\PostgreSQL\18\bin\psql.exe',

    [switch]$ApprovedForProduction,
    [switch]$TestRegressionPassed
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

if(-not $ApprovedForProduction){
    throw 'PRODUCTION GUARD: -ApprovedForProduction is required.'
}

if(-not $TestRegressionPassed){
    throw 'PRODUCTION GUARD: confirm the exact release passed TEST using -TestRegressionPassed.'
}

Write-Host 'Delegating PROD database deployment to the canonical exact-tag release deployer.'

& "$PSScriptRoot\Deploy-DatabaseRelease.ps1" `
    -Target PROD `
    -HostName $HostName `
    -Port $Port `
    -DbUser $DbUser `
    -PsqlPath $PsqlPath `
    -ReleaseTag $ReleaseTag `
    -ExpectedCurrentVersion $ExpectedCurrentVersion `
    -ConfirmProductionRelease

if($LASTEXITCODE -ne 0){
    throw 'PROD database release deployment failed.'
}