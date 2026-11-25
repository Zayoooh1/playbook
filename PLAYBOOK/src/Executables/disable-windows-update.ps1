#Requires -Version 5.1
<#
.SYNOPSIS
    Zabezpiecza blokade Windows Update przed samonaprawa (FailureActions, WaaSMedicSvc Start=4, zadania).
.DESCRIPTION
    Uruchamiany w kontekscie trustedInstaller jako czesc ostatniego kroku (11-windows-update-lock.yml).
    Celowo NIE wylacza uslugi BITS, poniewaz korzystaja z niej czesci instalatorow i aplikacji.
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$LogPath = Join-Path $env:SystemRoot 'Temp\playbook-wu-lock.log'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $line
}

Write-Log 'Rozpoczynam utwardzanie blokady Windows Update.'

# 1. Zatrzymanie uslug i wymuszenie Start = 4 w rejestrze (bez dotykania BITS)
$wuServices = @('wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'DoSvc')
foreach ($svc in $wuServices) {
    try {
        $serviceObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($null -ne $serviceObj -and $serviceObj.Status -ne 'Stopped') {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Log "Zatrzymano usluge: $svc"
        }
    } catch {
        Write-Log "Ostrzezenie przy zatrzymywaniu ${svc}: $($_.Exception.Message)"
    }

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
    if (Test-Path -LiteralPath $regPath) {
        try {
            Set-ItemProperty -Path $regPath -Name 'Start' -Value 4 -Type DWord -Force -ErrorAction Stop
            Write-Log "Ustawiono Start = 4 w rejestrze dla: $svc"
        } catch {
            Write-Log "Blad ustawiania Start = 4 dla ${svc}: $($_.Exception.Message)"
        }
    }
}

# 2. Usuniecie mechanizmow samonaprawy (FailureActions) dla wuauserv, UsoSvc i WaaSMedicSvc
$failureServices = @('wuauserv', 'UsoSvc', 'WaaSMedicSvc')
foreach ($svc in $failureServices) {
    try {
        & sc.exe failure $svc reset= 0 actions= "" 2>$null | Out-Null
        Write-Log "Wyczyszczono FailureActions (sc.exe) dla: $svc"
    } catch {
        Write-Log "Ostrzezenie sc.exe failure dla ${svc}: $($_.Exception.Message)"
    }

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
    if (Test-Path -LiteralPath $regPath) {
        Remove-ItemProperty -Path $regPath -Name 'FailureActions' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $regPath -Name 'FailureActionsOnNonCrashFailures' -ErrorAction SilentlyContinue
    }
}

# 3. Dobijanie ewentualnych pozostalych zadan harmonogramu WU / UpdateOrchestrator / WaaSMedic
$taskFolders = @(
    '\Microsoft\Windows\WindowsUpdate\',
    '\Microsoft\Windows\UpdateOrchestrator\',
    '\Microsoft\Windows\WaaSMedic\'
)

foreach ($folder in $taskFolders) {
    try {
        $tasks = Get-ScheduledTask -TaskPath $folder -ErrorAction SilentlyContinue
        foreach ($t in $tasks) {
            try {
                Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null
                Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
                Write-Log "Usunieto zadanie: $($t.TaskPath)$($t.TaskName)"
            } catch {
                Write-Log "Ostrzezenie przy usuwaniu zadania $($t.TaskName): $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Log "Ostrzezenie przy przegladaniu folderu ${folder}: $($_.Exception.Message)"
    }
}

Write-Log 'Zakonczono utwardzanie blokady Windows Update (BITS pozostawione bez zmian).'
exit 0
