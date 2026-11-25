#Requires -Version 5.1
<#
.SYNOPSIS
    Usuwa wylacznie przegladarke Microsoft Edge, zachowujac w pelni Microsoft Edge WebView2 Runtime.
.DESCRIPTION
    Uruchamiany w kontekscie trustedInstaller. Odblokowuje deinstalacje w EdgeUpdateDev,
    usuwa flage NoRemove, uruchamia natywny setup.exe Edge z flagami --uninstall --force-uninstall,
    czysci skroty oraz zadania aktualizacji samej przegladarki. NIE usuwa folderu ani kluczy EdgeWebView.
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$LogPath = Join-Path $env:SystemRoot 'Temp\playbook-edge.log'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $line
}

Write-Log 'Rozpoczynam usuwanie przegladarki Microsoft Edge (z zachowaniem WebView2 Runtime).'

# 1. Zezwolenie na deinstalacje Edge
try {
    $edgeDevKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev'
    if (-not (Test-Path $edgeDevKey)) {
        New-Item -Path $edgeDevKey -Force | Out-Null
    }
    New-ItemProperty -Path $edgeDevKey -Name 'AllowUninstall' -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Log 'Ustawiono EdgeUpdateDev\AllowUninstall = 1.'
} catch {
    Write-Log "Ostrzezenie EdgeUpdateDev: $($_.Exception.Message)"
}

# 2. Usuniecie blokady NoRemove z klucza odinstalowywania Edge (NIE dotykamy klucza EdgeWebView!)
$uninstallKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
)
foreach ($key in $uninstallKeys) {
    if (Test-Path $key) {
        try {
            Remove-ItemProperty -Path $key -Name 'NoRemove' -ErrorAction SilentlyContinue
            Write-Log "Usunieto NoRemove z: $key"
        } catch {
            Write-Log "Ostrzezenie przy czyszczeniu NoRemove ($key): $($_.Exception.Message)"
        }
    }
}

# 3. Wykrycie i wywolanie instalatora setup.exe przegladarki Edge (wylacznie folder Edge, NIE EdgeWebView)
$edgeRoots = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application')
)

$setupFound = $false
foreach ($root in $edgeRoots) {
    if (-not (Test-Path $root)) { continue }
    $setups = Get-ChildItem -Path $root -Filter 'setup.exe' -Recurse -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -like '*\Installer\setup.exe' }

    foreach ($setup in $setups) {
        $setupFound = $true
        Write-Log "Uruchamiam deinstalator Edge: $($setup.FullName)"
        try {
            $proc = Start-Process -FilePath $setup.FullName `
                -ArgumentList '--uninstall --system-level --verbose-logging --force-uninstall --delete-profile' `
                -Wait -PassThru -WindowStyle Hidden
            Write-Log "Kod wyjscia setup.exe: $($proc.ExitCode)"
        } catch {
            Write-Log "Blad uruchamiania setup.exe: $($_.Exception.Message)"
        }
    }
}

if (-not $setupFound) {
    Write-Log 'Nie znaleziono setup.exe przegladarki Edge (prawdopodobnie juz usunieta).'
}

# 4. Sprzatanie pozostalych skrotow Microsoft Edge (Public + profile uzytkownikow)
$shortcutTargets = @(
    'C:\Users\Public\Desktop\Microsoft Edge.lnk',
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk'
)

$userDirs = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('Public', 'All Users', 'Default User') }

foreach ($u in $userDirs) {
    $shortcutTargets += (Join-Path $u.FullName 'Desktop\Microsoft Edge.lnk')
    $shortcutTargets += (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk')
    $shortcutTargets += (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk')
}

foreach ($lnk in $shortcutTargets) {
    if (Test-Path -LiteralPath $lnk) {
        try {
            Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
            Write-Log "Usunieto skrot: $lnk"
        } catch {
            Write-Log "Nie udalo sie usunac skrotu ${lnk}: $($_.Exception.Message)"
        }
    }
}

# 5. Wylaczenie zaplanowanych zadan aktualizujacych sama przegladarke Edge
try {
    $edgeTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -like 'MicrosoftEdgeUpdateBrowserReplacement*' -or
        $_.TaskName -like 'MicrosoftEdgeUpdateTaskMachine*'
    }
    foreach ($t in $edgeTasks) {
        try {
            Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Wylaczono zadanie harmonogramu Edge: $($t.TaskPath)$($t.TaskName)"
        } catch {
            Write-Log "Ostrzezenie przy wylaczaniu zadania $($t.TaskName): $($_.Exception.Message)"
        }
    }
} catch {
    Write-Log "Ostrzezenie przy listowaniu zadan Edge: $($_.Exception.Message)"
}

# 6. Weryfikacja zachowania WebView2 Runtime
$webView2Path = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeWebView\Application'
if (Test-Path $webView2Path) {
    Write-Log "POTWIERDZONO: Microsoft Edge WebView2 Runtime pozostal nienaruszony ($webView2Path)."
} else {
    Write-Log 'Informacja: Katalog EdgeWebView nie istnial przed operacja (zostanie zainstalowany przy razie potrzeby np. przez Roblox).'
}

Write-Log 'Zakonczono usuwanie przegladarki Microsoft Edge.'
exit 0
