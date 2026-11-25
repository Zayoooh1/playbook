#Requires -Version 5.1
<#
.SYNOPSIS
    Konfiguruje jezyk pl-PL, uklad klawiatury Polski (programisty), GeoID 191 i strefe czasowa Warszawa.
.DESCRIPTION
    Uruchamiany w kontekscie currentUserElevated PRZED blokada Windows Update.
    Na angielskim ISO Windows 11 probuje bezpiecznie doinstalowac pakiet jezykowy pl-PL
    przez Install-Language (w try/catch). Wszystkie pozostale ustawienia dzialaja w 100% offline.
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$LogPath = Join-Path $env:TEMP 'playbook-locale.log'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $line
}

Write-Log 'Start konfiguracji lokalizacji pl-PL.'

# 1. Opcjonalne doinstalowanie pakietu jezykowego pl-PL na angielskim ISO (Windows 11, zanim WU zostanie zablokowany)
try {
    $currentUI = (Get-UICulture).Name
    Write-Log "Biezacy jezyk UI: $currentUI"
    if ($currentUI -ne 'pl-PL') {
        $installCmd = Get-Command -Name 'Install-Language' -ErrorAction SilentlyContinue
        if ($null -ne $installCmd) {
            Write-Log 'Wykryto inny jezyk UI niz pl-PL oraz cmdlet Install-Language. Proba instalacji pakietu pl-PL...'
            Install-Language -Language 'pl-PL' -CopyToSettings -ErrorAction Stop
            Write-Log 'Pakiet jezykowy pl-PL zostal zainstalowany.'
        } else {
            Write-Log 'Cmdlet Install-Language niedostepny (np. Windows 10) - pomijam pobieranie pakietu UI.'
        }
    } else {
        Write-Log 'System posiada juz jezyk UI pl-PL.'
    }
} catch {
    Write-Log "Ostrzezenie: Install-Language nie powiodlo sie (brak sieci lub niedostepna paczka) - kontynuuje offline. Szczegoly: $($_.Exception.Message)"
}

# 2. Ustawienia wykonywane zawsze lokalnie (100% offline)
try {
    Set-Culture -CultureInfo 'pl-PL'
    Write-Log 'Ustawiono Culture: pl-PL'
} catch {
    Write-Log "Blad Set-Culture: $($_.Exception.Message)"
}

try {
    Set-WinSystemLocale -SystemLocale 'pl-PL'
    Write-Log 'Ustawiono WinSystemLocale: pl-PL'
} catch {
    Write-Log "Blad Set-WinSystemLocale: $($_.Exception.Message)"
}

try {
    Set-WinHomeLocation -GeoId 191
    Write-Log 'Ustawiono WinHomeLocation GeoId: 191 (Polska)'
} catch {
    Write-Log "Blad Set-WinHomeLocation: $($_.Exception.Message)"
}

# 3. Wylaczny uklad klawiatury: Polski (programisty) 0415:00000415 (usuniecie en-US i innych)
try {
    $langList = New-WinUserLanguageList -Language 'pl-PL'
    $langList[0].InputMethodTips.Clear()
    $langList[0].InputMethodTips.Add('0415:00000415')
    Set-WinUserLanguageList -LanguageList $langList -Force
    Set-WinDefaultInputMethodOverride -InputTip '0415:00000415'
    Write-Log 'Ustawiono wylaczny uklad klawiatury: pl-PL / 0415:00000415 (Polski programisty)'
} catch {
    Write-Log "Blad konfiguracji klawiatury: $($_.Exception.Message)"
}

# 4. Strefa czasowa: Warszawa
try {
    Set-TimeZone -Id 'Central European Standard Time'
    Write-Log 'Ustawiono strefe czasowa: Central European Standard Time (Warszawa)'
} catch {
    Write-Log "Blad Set-TimeZone: $($_.Exception.Message)"
}

# 5. Kopiowanie ustawien regionalnych na ekran logowania i nowych uzytkownikow
try {
    $copyCmd = Get-Command -Name 'Copy-UserInternationalSettingsToSystem' -ErrorAction SilentlyContinue
    if ($null -ne $copyCmd) {
        Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
        Write-Log 'Skopiowano ustawienia regionalne na ekran logowania i dla nowych uzytkownikow.'
    } else {
        Write-Log 'Copy-UserInternationalSettingsToSystem niedostepne (Windows 10) - stosuje fallback dla .DEFAULT.'
        $defaultPreload = 'Registry::HKEY_USERS\.DEFAULT\Keyboard Layout\Preload'
        if (Test-Path $defaultPreload) {
            Remove-Item -Path $defaultPreload -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $defaultPreload -Force | Out-Null
        New-ItemProperty -Path $defaultPreload -Name '1' -Value '00000415' -PropertyType String -Force | Out-Null
        Write-Log 'Zastosowano fallback klawiatury 00000415 dla .DEFAULT.'
    }
} catch {
    Write-Log "Ostrzezenie przy kopiowaniu ustawien systemowych: $($_.Exception.Message)"
}

Write-Log 'Zakonczono konfiguracje lokalizacji pl-PL.'
exit 0
