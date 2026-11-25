#Requires -Version 5.1
<#
.SYNOPSIS
    Konfiguruje jednorazowe zadanie startowe ustawiajace typ uruchomienia uslugi MDCoreSvc na Disabled (Start = 4) po pierwszym restarcie.
.DESCRIPTION
    Wzorzec stosowany w AtlasOS dla Windows 11, gdzie wartosc Start uslugi MDCoreSvc moze wymagac
    ponownego zastosowania po pierwszym uruchomieniu systemu. Zadanie po wykonaniu usuwa siebie i plik skryptu.
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$LogPath = Join-Path $env:SystemRoot 'Temp\playbook-postboot-setup.log'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $line
}

Write-Log 'Konfigurowanie jednorazowego zadania post-boot dla MDCoreSvc.'

# 1. Proba bezposredniego ustawienia Start = 4 juz teraz
$mdCoreReg = 'HKLM:\SYSTEM\CurrentControlSet\Services\MDCoreSvc'
if (Test-Path -LiteralPath $mdCoreReg) {
    try {
        Set-ItemProperty -Path $mdCoreReg -Name 'Start' -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log 'Zastosowano biezaca wartosc Start = 4 dla MDCoreSvc.'
    } catch {
        Write-Log "Biezacy zapis MDCoreSvc pominiety (zostanie zastosowany po restarcie): $($_.Exception.Message)"
    }
}

# 2. Zapisanie samousuwajacego sie skryptu post-boot w %SystemRoot%\Setup\Scripts
$scriptsDir = Join-Path $env:SystemRoot 'Setup\Scripts'
if (-not (Test-Path -LiteralPath $scriptsDir)) {
    New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
}

$postBootScript = Join-Path $scriptsDir 'custom-playbook-mdcore-postboot.ps1'
$scriptBody = @'
$ErrorActionPreference = 'SilentlyContinue'
$log = Join-Path $env:SystemRoot 'Temp\playbook-postboot.log'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Add-Content -Path $log -Value "[$stamp] Start zadania post-boot MDCoreSvc."

$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\MDCoreSvc'
if (Test-Path -LiteralPath $regPath) {
    Set-ItemProperty -Path $regPath -Name 'Start' -Value 4 -Type DWord -Force
    Stop-Service -Name 'MDCoreSvc' -Force -ErrorAction SilentlyContinue
    Add-Content -Path $log -Value "[$stamp] Ustawiono MDCoreSvc Start = 4."
}

Unregister-ScheduledTask -TaskName 'DisableMDCorePostBoot' -TaskPath '\CustomPlaybook\' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
'@

Set-Content -Path $postBootScript -Value $scriptBody -Encoding UTF8 -Force
Write-Log "Utworzono skrypt post-boot: $postBootScript"

# 3. Rejestracja jednorazowego zadania Harmonogramu Zadan (AtStartup jako SYSTEM)
try {
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$postBootScript`""
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName 'DisableMDCorePostBoot' `
        -TaskPath '\CustomPlaybook\' `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null

    Write-Log 'Zarejestrowano zadanie harmonogramu \CustomPlaybook\DisableMDCorePostBoot.'
} catch {
    Write-Log "Blad rejestracji zadania post-boot: $($_.Exception.Message)"
}

exit 0
