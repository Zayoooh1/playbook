#Requires -Version 5.1
<#
.SYNOPSIS
    Pobiera i instaluje Spotify Desktop w kontekscie uzytkownika BEZ elevacji (currentUser).
.DESCRIPTION
    Wymaga wczesniejszego usuniecia wersji Spotify ze Store (wykonane w 02-debloat-appx.yml).
    Po wykryciu %APPDATA%\Spotify\Spotify.exe odczekuje chwile i zamyka auto-uruchomiony proces Spotify.exe.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogPath    = Join-Path $env:TEMP 'playbook-apps.log'
$Url        = 'https://download.spotify.com/SpotifyFullSetup.exe'
$OutFile    = Join-Path $env:TEMP 'SpotifyFullSetup.exe'
$SpotifyExe = Join-Path $env:APPDATA 'Spotify\Spotify.exe'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] [Spotify] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
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
        Write-Log 'Nie udalo sie pobrac instalatora Spotify po 3 probach.'
        exit 1
    }

    Write-Log 'Uruchamiam SpotifyFullSetup.exe /silent (kontekst currentUser)...'
    $setupProc = Start-Process -FilePath $OutFile -ArgumentList '/silent' -PassThru -WindowStyle Hidden

    $deadline = (Get-Date).AddSeconds(120)
    $installed = $false
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $SpotifyExe) -and $setupProc.HasExited) {
            $installed = $true
            break
        }
        Start-Sleep -Seconds 3
    }

    if (-not $setupProc.HasExited) {
        Write-Log 'Instalator Spotify nadal dziala po limicie czasu - wymuszam zamkniecie procesu instalatora.'
        Stop-Process -Id $setupProc.Id -Force -ErrorAction SilentlyContinue
    }

    # Chwila na ewentualny auto-start Spotify.exe, a nastepnie jego zamkniecie
    Start-Sleep -Seconds 5
    Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if ($installed -or (Test-Path -LiteralPath $SpotifyExe)) {
        Write-Log "Spotify zainstalowany pomyslnie ($SpotifyExe)."
        exit 0
    } else {
        Write-Log 'Nie wykryto pliku Spotify.exe po zakonczeniu instalacji.'
        exit 1
    }
} catch {
    Write-Log "Wyjatek podczas instalacji Spotify: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        Write-Log 'Usunieto plik tymczasowy instalatora.'
    }
}
