#Requires -Version 5.1
<#
.SYNOPSIS
    Pobiera i instaluje Roblox Player w kontekscie uzytkownika BEZ elevacji (currentUser).
.DESCRIPTION
    RobloxPlayerInstaller.exe nie posiada oficjalnej flagi full-silent, ale instaluje sie
    automatycznie bez interakcji w %LocalAppData%\Roblox. Skrypt czeka z timeoutem 180 s na
    zakonczenie instalatora oraz utworzenie %LocalAppData%\Roblox\Versions, po czym zamyka
    ewentualnie uruchomiony proces RobloxPlayerBeta.exe.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogPath     = Join-Path $env:TEMP 'playbook-apps.log'
$Url         = 'https://www.roblox.com/download/client?os=win'
$OutFile     = Join-Path $env:TEMP 'RobloxPlayerInstaller.exe'
$VersionsDir = Join-Path $env:LOCALAPPDATA 'Roblox\Versions'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] [Roblox] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $line
}

function Invoke-DownloadWithRetry {
    param(
        [string]$DownloadUrl,
        [string]$Destination,
        [int]$MaxRetries = 3
    )
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-Log "Pobieranie (proba $attempt/$MaxRetries): $DownloadUrl"
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $Destination -UseBasicParsing -TimeoutSec 180
            if ((Test-Path -LiteralPath $Destination) -and ((Get-Item -LiteralPath $Destination).Length -gt 0)) {
                return $true
            }
        } catch {
            Write-Log "Blad pobierania (proba $attempt): $($_.Exception.Message)"
            if ($attempt -lt $MaxRetries) { Start-Sleep -Seconds 5 }
        }
    }
    return $false
}

try {
    if (-not (Invoke-DownloadWithRetry -DownloadUrl $Url -Destination $OutFile)) {
        Write-Log 'Nie udalo sie pobrac instalatora Roblox po 3 probach.'
        exit 1
    }

    Write-Log 'Uruchamiam RobloxPlayerInstaller.exe (kontekst currentUser, unattended)...'
    $installerProc = Start-Process -FilePath $OutFile -PassThru

    $deadline = (Get-Date).AddSeconds(180)
    $installed = $false
    while ((Get-Date) -lt $deadline) {
        $hasVersions = (Test-Path -LiteralPath $VersionsDir) -and
                       ((Get-ChildItem -Path $VersionsDir -Directory -ErrorAction SilentlyContinue).Count -gt 0)
        $installerStillRunning = $null -ne (Get-Process -Name 'RobloxPlayerInstaller' -ErrorAction SilentlyContinue)

        if ($hasVersions -and -not $installerStillRunning) {
            $installed = $true
            break
        }
        Start-Sleep -Seconds 3
    }

    # Sprzatanie ewentualnie otwartych okien klienta lub zawieszonego instalatora
    Start-Sleep -Seconds 3
    Get-Process -Name 'RobloxPlayerBeta', 'RobloxPlayerLauncher', 'RobloxPlayerInstaller' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    if ($installed -or (Test-Path -LiteralPath $VersionsDir)) {
        Write-Log "Roblox zainstalowany pomyslnie ($VersionsDir)."
        exit 0
    } else {
        Write-Log 'Przekroczono limit 180 s podczas oczekiwania na instalacje Roblox.'
        exit 1
    }
} catch {
    Write-Log "Wyjatek podczas instalacji Roblox: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        Write-Log 'Usunieto plik tymczasowy instalatora.'
    }
}
