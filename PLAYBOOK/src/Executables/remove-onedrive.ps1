#Requires -Version 5.1
<#
.SYNOPSIS
    Odinstalowuje Microsoft OneDrive, usuwa zaplanowane zadania i czysci wpisy autostartu.
.DESCRIPTION
    Uruchamiany w kontekscie trustedInstaller. Sprawdza OneDriveSetup.exe w SysWOW64 i System32,
    usuwa zadania harmonogramu OneDrive oraz usuwa OneDriveSetup z Default User NTUSER.DAT.
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$LogPath = Join-Path $env:SystemRoot 'Temp\playbook-onedrive.log'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $line
}

Write-Log 'Rozpoczynam usuwanie Microsoft OneDrive.'

# 1. Zatrzymanie procesow OneDrive
Get-Process -Name 'OneDrive*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 2. Uruchomienie OneDriveSetup.exe /uninstall (SysWOW64 oraz System32)
$setupPaths = @(
    (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
    (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
)

foreach ($exe in $setupPaths) {
    if (Test-Path -LiteralPath $exe) {
        Write-Log "Wywoluje deinstalator: $exe /uninstall"
        try {
            $proc = Start-Process -FilePath $exe -ArgumentList '/uninstall' -Wait -PassThru -WindowStyle Hidden
            Write-Log "Kod wyjscia ($exe): $($proc.ExitCode)"
        } catch {
            Write-Log "Blad przy deinstalacji ($exe): $($_.Exception.Message)"
        }
    }
}

# 3. Usuniecie zaplanowanych zadan OneDrive
try {
    $odTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -like '*OneDrive*' -or $_.TaskPath -like '*OneDrive*'
    }
    foreach ($task in $odTasks) {
        try {
            Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Usunieto zadanie OneDrive: $($task.TaskPath)$($task.TaskName)"
        } catch {
            Write-Log "Nie udalo sie usunac zadania $($task.TaskName): $($_.Exception.Message)"
        }
    }
} catch {
    Write-Log "Ostrzezenie przy listowaniu zadan OneDrive: $($_.Exception.Message)"
}

# 4. Usuniecie OneDriveSetup z galezi Run profilu domyslnego (Default User)
$defaultHive = 'C:\Users\Default\NTUSER.DAT'
if (Test-Path -LiteralPath $defaultHive) {
    $mountKey = 'HKU\CustomPlaybookDefault'
    try {
        & reg.exe load $mountKey $defaultHive | Out-Null
        if ($LASTEXITCODE -eq 0) {
            & reg.exe delete "$mountKey\Software\Microsoft\Windows\CurrentVersion\Run" /v 'OneDriveSetup' /f 2>$null | Out-Null
            Write-Log 'Usunieto OneDriveSetup z autostartu Default User.'
        }
    } catch {
        Write-Log "Ostrzezenie Default User NTUSER.DAT: $($_.Exception.Message)"
    } finally {
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        & reg.exe unload $mountKey 2>$null | Out-Null
    }
}

# 5. Czyszczenie pozostalych skrotow OneDrive w Menu Start
$userDirs = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('Public', 'All Users', 'Default User') }

foreach ($u in $userDirs) {
    $odShortcut = Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk'
    if (Test-Path -LiteralPath $odShortcut) {
        Remove-Item -LiteralPath $odShortcut -Force -ErrorAction SilentlyContinue
        Write-Log "Usunieto skrot: $odShortcut"
    }
}

Write-Log 'Zakonczono usuwanie Microsoft OneDrive.'
exit 0
