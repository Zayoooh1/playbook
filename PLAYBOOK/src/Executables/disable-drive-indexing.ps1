#Requires -Version 5.1
<#
.SYNOPSIS
    Wylacza atrybut indeksowania zawartosci (IndexingEnabled = $false) na wszystkich lokalnych dyskach NTFS.
.DESCRIPTION
    Uruchamiany w kontekscie trustedInstaller. Korzysta z CIM (Win32_Volume, DriveType = 3).
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$LogPath = Join-Path $env:SystemRoot 'Temp\playbook-indexing.log'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $line
}

Write-Log 'Rozpoczynam wylaczanie indeksowania na lokalnych woluminach NTFS.'

try {
    $volumes = Get-CimInstance -ClassName Win32_Volume -Filter "DriveType = 3" -ErrorAction Stop
    foreach ($vol in $volumes) {
        $label = if ($vol.DriveLetter) { $vol.DriveLetter } else { $vol.DeviceID }
        if ($vol.FileSystem -ne 'NTFS') {
            Write-Log "Pomijam wolumin $label (system plikow: $($vol.FileSystem))."
            continue
        }
        if ($vol.IndexingEnabled -eq $true) {
            try {
                Set-CimInstance -InputObject $vol -Property @{ IndexingEnabled = $false } -ErrorAction Stop
                Write-Log "Wylaczono IndexingEnabled na woluminie: $label"
            } catch {
                Write-Log "Ostrzezenie przy wylaczaniu indeksowania na ${label}: $($_.Exception.Message)"
            }
        } else {
            Write-Log "Wolumin $label ma juz wylaczone indeksowanie."
        }
    }
} catch {
    Write-Log "Blad odczytu woluminow CIM Win32_Volume: $($_.Exception.Message)"
}

Write-Log 'Zakonczono wylaczanie indeksowania dyskow.'
exit 0
