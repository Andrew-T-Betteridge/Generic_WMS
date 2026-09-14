$script:DyneticPsql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

function Assert-DyneticDatabaseName {
    param(
        [Parameter(Mandatory=$true)][string]$Database,
        [Parameter(Mandatory=$true)][ValidateSet('DEVELOPMENT','TEST','PRODUCTION')][string]$Environment
    )
    $expected = switch ($Environment) {
        'DEVELOPMENT' { 'fulfilment_dev' }
        'TEST'        { 'fulfilment_test' }
        'PRODUCTION'  { 'fulfilment_prod' }
    }
    if ($Database -ne $expected) {
        throw "Environment guard blocked operation: $Environment must use database '$expected', not '$Database'."
    }
}

function Invoke-DyneticPsql {
    param(
        [Parameter(Mandatory=$true)][string]$Database,
        [Parameter(Mandatory=$true)][string]$DbUser,
        [string]$Command,
        [string]$File
    )
    if (-not (Test-Path $script:DyneticPsql)) { throw "psql not found at $script:DyneticPsql" }
    if ($File) {
        & $script:DyneticPsql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -P pager=off -f $File
    } else {
        & $script:DyneticPsql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -P pager=off -c $Command
    }
    if ($LASTEXITCODE -ne 0) { throw "PostgreSQL command failed against $Database." }
}
