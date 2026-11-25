#Requires -Version 5.1
<#
.SYNOPSIS
    Pobiera i instaluje Discord (x64) w kontekscie uzytkownika BEZ elevacji (currentUser).
.DESCRIPTION
    Obsluguje zachowanie instalatora Squirrel (DiscordSetup.exe -s), ktory potrafi wyjsc przed
    zakonczeniem Update.exe - czeka z timeoutem do 120 s na pojawienie sie %LocalAppData%\Discord\Update.exe
    i zakonczenie instalacji, po czym zamyka ewentualnie auto-uruchomiony proces Discord.exe.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogPath    = Join-Path $env:TEMP 'playbook-apps.log'
$Url        = 'https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x64'
$OutFile    = Join-Path $env:TEMP 'DiscordSetup.exe'
$UpdateExe  = Join-Path $env:LOCALAPPDATA 'Discord\Update.exe'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] [Discord] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
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
        Write-Log 'Nie udalo sie pobrac instalatora Discord po 3 probach.'
        exit 1
    }

    Write-Log 'Uruchamiam DiscordSetup.exe -s (kontekst currentUser)...'
    Start-Process -FilePath $OutFile -ArgumentList '-s' -WindowStyle Hidden | Out-Null

    # Oczekiwanie z timeoutem 120 s na pojawienie sie Update.exe oraz zakonczenie procesow instalatora
    $deadline = (Get-Date).AddSeconds(120)
    $installed = $false
    while ((Get-Date) -lt $deadline) {
        $hasUpdate = Test-Path -LiteralPath $UpdateExe
        $hasAppDir = (Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Discord') -Directory -Filter 'app-*' -ErrorAction SilentlyContinue).Count -gt 0
        $setupRunning = $null -ne (Get-Process -Name 'DiscordSetup', 'Update' -ErrorAction SilentlyContinue)

        if ($hasUpdate -and $hasAppDir -and -not $setupRunning) {
            $installed = $true
            break
        }
        Start-Sleep -Seconds 3
    }

    # Zatrzymanie ewentualnie auto-uruchomionego klienta Discord, aby nie blokowal AME Wizard
    Start-Sleep -Seconds 3
    Get-Process -Name 'Discord' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if ($installed -or (Test-Path -LiteralPath $UpdateExe)) {
        Write-Log "Discord zainstalowany pomyslnie ($UpdateExe)."
        exit 0
    } else {
        Write-Log 'Przekroczono limit 120 s podczas oczekiwania na zakonczenie instalacji Discord.'
        exit 1
    }
} catch {
    Write-Log "Wyjatek podczas instalacji Discord: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path -LiteralPath $OutFile) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        Write-Log 'Usunieto plik tymczasowy instalatora.'
    }
}
