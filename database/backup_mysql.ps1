param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_]+$')]
    [string]$Database,

    [string]$OutputPath,
    [string]$LoginPath = 'drogueria-backup',
    [string]$HostName = $(if ($env:DB_HOST) { $env:DB_HOST } else { '127.0.0.1' }),
    [int]$Port = $(if ($env:DB_PORT) { [int]$env:DB_PORT } else { 3306 })
)

$ErrorActionPreference = 'Stop'
$mysqldump = Get-Command mysqldump.exe -ErrorAction Stop

if (-not $OutputPath) {
    $root = Split-Path -Parent $PSScriptRoot
    $backupDir = Join-Path $root 'docs/entrega/backup'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $OutputPath = Join-Path $backupDir "${Database}_${stamp}.sql"
}

$absoluteOutput = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $absoluteOutput) | Out-Null

$arguments = @(
    "--login-path=$LoginPath",
    "--host=$HostName",
    "--port=$Port",
    '--single-transaction',
    '--hex-blob',
    '--no-tablespaces',
    '--routines',
    '--triggers',
    '--events',
    '--default-character-set=utf8mb4',
    '--set-gtid-purged=OFF',
    '--databases',
    $Database,
    "--result-file=$absoluteOutput"
)

& $mysqldump.Source @arguments
if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $absoluteOutput -Force -ErrorAction SilentlyContinue
    throw "mysqldump terminó con código $LASTEXITCODE. No se conservó un backup incompleto."
}

$file = Get-Item -LiteralPath $absoluteOutput
if ($file.Length -eq 0) {
    Remove-Item -LiteralPath $absoluteOutput -Force
    throw 'mysqldump produjo un archivo vacío.'
}

Write-Output "Backup creado: $($file.FullName) ($($file.Length) bytes)"
