#Requires -Version 5.1
<#
.SYNOPSIS
    Instaluje wymagane runtime (VC++ x64 dla CefSharp, .NET 10.0 Desktop Runtime x64) oraz TikStream (WiX MSI).
.DESCRIPTION
    Uruchamiany w kontekscie currentUserElevated.
    Zweryfikowane wymagania TikStream (https://github.com/Zayoooh1/TikStream):
    - VC++ Redistributable x64 (wymagany przez wbudowany CefSharp.OffScreen.NETCore)
    - .NET 10.0 Desktop Runtime x64 (SelfContained=false)
    - TikStreamSetup.msi z GitHub Releases (FFmpeg i node.exe sa juz w MSI)
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogPath       = Join-Path $env:TEMP 'playbook-apps.log'
$VcUrl         = 'https://aka.ms/vc14/vc_redist.x64.exe'
$DotnetUrl     = 'https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe'
$TikStreamUrl  = 'https://github.com/Zayoooh1/TikStream/releases/latest/download/TikStreamSetup.msi'

$VcFile        = Join-Path $env:TEMP 'vc_redist.x64.exe'
$DotnetFile    = Join-Path $env:TEMP 'windowsdesktop-runtime-10-win-x64.exe'
$TikStreamFile = Join-Path $env:TEMP 'TikStreamSetup.msi'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] [TikStream] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
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
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $Destination -UseBasicParsing -TimeoutSec 240
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
    # KROK 1: Visual C++ Redistributable x64 (dla CefSharp)
    if (-not (Invoke-DownloadWithRetry -DownloadUrl $VcUrl -Destination $VcFile)) {
        Write-Log 'Nie udalo sie pobrac vc_redist.x64.exe.'
        exit 1
    }
    Write-Log 'Instaluje Visual C++ Redistributable x64...'
    $vcProc = Start-Process -FilePath $VcFile -ArgumentList '/install /quiet /norestart' -Wait -PassThru -WindowStyle Hidden
    Write-Log "Kod wyjscia VC++ x64: $($vcProc.ExitCode)"
    if ($vcProc.ExitCode -notin @(0, 1638, 3010)) {
        Write-Log "Ostrzezenie: VC++ x64 zwrocilo kod $($vcProc.ExitCode)."
    }

    # KROK 2: .NET 10.0 Desktop Runtime x64
    if (-not (Invoke-DownloadWithRetry -DownloadUrl $DotnetUrl -Destination $DotnetFile)) {
        Write-Log 'Nie udalo sie pobrac .NET 10.0 Desktop Runtime x64.'
        exit 1
    }
    Write-Log 'Instaluje .NET 10.0 Desktop Runtime x64...'
    $dnProc = Start-Process -FilePath $DotnetFile -ArgumentList '/install /quiet /norestart' -Wait -PassThru -WindowStyle Hidden
    Write-Log "Kod wyjscia .NET 10 Desktop Runtime: $($dnProc.ExitCode)"
    if ($dnProc.ExitCode -notin @(0, 1638, 3010)) {
        Write-Log "Ostrzezenie: .NET 10 Desktop Runtime zwrocilo kod $($dnProc.ExitCode)."
    }

    # KROK 3: TikStream WiX MSI
    if (-not (Invoke-DownloadWithRetry -DownloadUrl $TikStreamUrl -Destination $TikStreamFile)) {
        Write-Log 'Nie udalo sie pobrac TikStreamSetup.msi z GitHub Releases.'
        exit 1
    }
    Write-Log 'Instaluje TikStreamSetup.msi...'
    $msiArgs = "/i `"$TikStreamFile`" /qn /norestart LAUNCH_AFTER_INSTALL=0 INSTALL_DESKTOP=1 INSTALL_STARTMENU=1 INSTALL_AUTOSTART=0"
    $tsProc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -WindowStyle Hidden
    Write-Log "Kod wyjscia msiexec TikStream: $($tsProc.ExitCode)"

    if ($tsProc.ExitCode -notin @(0, 3010)) {
        Write-Log "Instalacja TikStream zakonczyla sie bledem: $($tsProc.ExitCode)"
        exit $tsProc.ExitCode
    }

    Write-Log 'TikStream wraz z wymaganymi runtime zainstalowany pomyslnie.'
    exit 0
} catch {
    Write-Log "Wyjatek podczas instalacji TikStream: $($_.Exception.Message)"
    exit 1
} finally {
    foreach ($tmp in @($VcFile, $DotnetFile, $TikStreamFile)) {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Log 'Wyczyszczono pliki tymczasowe instalatorow TikStream/runtime.'
}
