param(
    [string]$Database='fulfilment_test',
    [string]$DbUser='postgres',
    [string]$HostName='localhost',
    [int]$Port=5432,
    [switch]$KeepExisting
)

$ErrorActionPreference='Stop'

. "$PSScriptRoot\environment-common.ps1"

$allowedTestHosts=@('localhost','127.0.0.1','::1')

if($HostName -notin $allowedTestHosts){
    throw "TEST database safety guard blocked non-local PostgreSQL host '$HostName'."
}

Assert-DyneticDatabaseName `
    -Database $Database `
    -Environment TEST

if(-not (Test-Path $script:DyneticPsql)){
    throw "psql not found at $script:DyneticPsql"
}

if(-not $KeepExisting){
    & $script:DyneticPsql `
        -X `
        -h $HostName `
        -p $Port `
        -U $DbUser `
        -d postgres `
        -v ON_ERROR_STOP=1 `
        -P pager=off `
        -c ('DROP DATABASE IF EXISTS "{0}" WITH (FORCE);' -f $Database)

    if($LASTEXITCODE -ne 0){
        throw "Failed to drop TEST database '$Database'."
    }
}

$existsResult = (
    & $script:DyneticPsql `
        -X `
        -h $HostName `
        -p $Port `
        -U $DbUser `
        -d postgres `
        -Atqc "SELECT 1 FROM pg_database WHERE datname='$Database';"
) | Out-String

if($LASTEXITCODE -ne 0){
    throw "Failed checking TEST database '$Database'."
}

$exists=$existsResult.Trim() -eq '1'

if(-not $exists){
    & $script:DyneticPsql `
        -X `
        -h $HostName `
        -p $Port `
        -U $DbUser `
        -d postgres `
        -v ON_ERROR_STOP=1 `
        -P pager=off `
        -c ('CREATE DATABASE "{0}";' -f $Database)

    if($LASTEXITCODE -ne 0){
        throw "Failed to create TEST database '$Database'."
    }
}

Write-Host "DYNETIC WMS TEST database ready: $HostName`:$Port / $Database"
