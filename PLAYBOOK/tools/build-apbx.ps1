#Requires -Version 5.1
<#
.SYNOPSIS
    Waliduje i pakuje playbook AME Wizard z katalogu src/ do archiwum 7-Zip (.apbx) z haslem 'malte'.
.DESCRIPTION
    1. Uruchamia tools/validate-playbook.ps1 (przerywa build przy bledach).
    2. Wykrywa 7z.exe (PATH lub C:\Program Files\7-Zip\7z.exe).
    3. Pakuje zawartosc src\* bezposrednio do root archiwum dist/CustomPlaybook.apbx (bez folderu src/).
    4. Weryfikuje lista '7z l -pmalte', ze playbook.conf i Configuration\main.yml znajduja sie w root archiwum.
#>

[CmdletBinding()]
param(
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'dist\CustomPlaybook.apbx'
}
$srcDir      = Join-Path $repoRoot 'src'
$validator   = Join-Path $PSScriptRoot 'validate-playbook.ps1'
$archivePass = 'malte'

Write-Host "=== Budowanie pakietu AME Wizard (.apbx) ===`n" -ForegroundColor Cyan

# 1. Walidacja przed budowaniem
Write-Host "[1/4] Uruchamianie walidacji playbooka..." -ForegroundColor Cyan
& $validator -SrcDir $srcDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "`nBuild przerwany: walidacja zakonczyla sie bledem." -ForegroundColor Red
    exit 1
}

# 2. Wykrywanie 7z.exe
Write-Host "`n[2/4] Wykrywanie narzedzia 7-Zip (7z.exe)..." -ForegroundColor Cyan
$sevenZip = $null
$cmd7z = Get-Command -Name '7z' -ErrorAction SilentlyContinue
if ($null -ne $cmd7z) {
    $sevenZip = $cmd7z.Source
} else {
    $candidates = @(
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $sevenZip = $c
            break
        }
    }
}

if ([string]::IsNullOrEmpty($sevenZip)) {
    Write-Host '[ERROR] Nie znaleziono 7z.exe w PATH ani w domyslnych lokalizacjach 7-Zip.' -ForegroundColor Red
    Write-Host 'Zainstaluj 7-Zip (https://www.7-zip.org/) i sprobuj ponownie.' -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] Znaleziono 7-Zip: $sevenZip" -ForegroundColor Green

# 3. Pakowanie zawartosci src\* do root archiwum .apbx
Write-Host "`n[3/4] Pakowanie zawartosci src/ -> $OutputPath..." -ForegroundColor Cyan
$distDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $distDir)) {
    New-Item -Path $distDir -ItemType Directory -Force | Out-Null
}
if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}

Push-Location -LiteralPath $srcDir
try {
    & $sevenZip a -t7z "-p$archivePass" -mx=5 -y $OutputPath '*' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7z.exe zwrocil kod bledu $LASTEXITCODE podczas pakowania."
    }
} finally {
    Pop-Location
}
Write-Host "  [OK] Utworzono archiwum: $OutputPath" -ForegroundColor Green

# 4. Weryfikacja zawartosci archiwum (playbook.conf i Configuration\main.yml musza byc w root)
Write-Host "`n[4/4] Weryfikacja struktury archiwum przez '7z l -p$archivePass'..." -ForegroundColor Cyan
$listOutput = & $sevenZip l "-p$archivePass" $OutputPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Nie udalo sie odczytac listy plikow archiwum (kod: $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}

$listText = $listOutput -join "`n"
$hasRootConf   = $listText -match '(?m)\splaybook\.conf\s*$'
$hasRootMain   = $listText -match '(?m)\sConfiguration\\main\.yml\s*$'
$hasSrcWrapper = $listText -match '(?m)\ssrc\\playbook\.conf\s*$'

if ($hasSrcWrapper) {
    Write-Host '[ERROR] Archiwum zawiera katalog nadrzedny src\ zamiast plikow w root!' -ForegroundColor Red
    exit 1
}
if (-not $hasRootConf) {
    Write-Host '[ERROR] Brak pliku playbook.conf w katalogu glownym archiwum!' -ForegroundColor Red
    exit 1
}
if (-not $hasRootMain) {
    Write-Host '[ERROR] Brak pliku Configuration\main.yml w katalogu glownym archiwum!' -ForegroundColor Red
    exit 1
}

$item = Get-Item -LiteralPath $OutputPath
$hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash

Write-Host "  [OK] Zweryfikowano: playbook.conf oraz Configuration\main.yml znajduja sie w root archiwum." -ForegroundColor Green
Write-Host "`n=== BUILD ZAKONCZONY SUKCESEM ===" -ForegroundColor Green
Write-Host ("Plik:    {0}" -f $item.FullName)
Write-Host ("Rozmiar: {0:N2} KB" -f ($item.Length / 1KB))
Write-Host ("SHA-256: {0}" -f $hash)
exit 0
