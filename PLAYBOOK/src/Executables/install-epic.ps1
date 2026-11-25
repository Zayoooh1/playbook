#Requires -Version 5.1
<#
.SYNOPSIS
    Pobiera i cicho instaluje Epic Games Launcher (MSI).
.DESCRIPTION
    Uruchamiany w kontekscie currentUserElevated. Bez Microsoft Store i bez winget.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogPath = Join-Path $env:TEMP 'playbook-apps.log'
$Url     = 'https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi'
$OutFile = Join-Path $env:TEMP 'EpicGamesLauncherInstaller.msi'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] [EpicGames] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
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
        Write-Log 'Nie udalo sie pobrac instalatora Epic Games Launcher po 3 probach.'
        exit 1
    }

    Write-Log 'Uruchamiam cicha instalacje MSI Epic Games Launcher...'
    $proc = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList "/i `"$OutFile`" /qn /norestart" `
        -Wait -PassThru -WindowStyle Hidden

    Write-Log "Kod wyjscia msiexec: $($proc.ExitCode)"
    if ($proc.ExitCode -notin @(0, 3010)) {
        Write-Log "Instalacja zakonczyla sie nieoczekiwanym kodem: $($proc.ExitCode)"
        exit $proc.ExitCode
    }

    # Zamkniecie ewentualnie uruchomionego EpicGamesLauncher
    Get-Process -Name 'EpicGamesLauncher' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Log 'Epic Games Launcher zainstalowany pomyslnie.'
    exit 0
} catch {
    Write-Log "Wyjatek podczas instalacji Epic Games Launcher: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        Write-Log 'Usunieto plik tymczasowy instalatora.'
    }
}
