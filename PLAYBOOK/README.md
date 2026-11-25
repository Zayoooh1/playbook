# Custom AME Wizard Playbook (Windows 10 22H2 / Windows 11 26H2+)

Kompletny, modularny playbook **AME Wizard** (`.apbx`), wzorowany jakością i architekturą na ReviOS oraz AtlasOS, zaprojektowany specjalnie pod świeże instalacje **Windows 10 22H2 Pro (x64)** oraz **Windows 11 26H2 Pro (x64)** z pełną gotowością na przyszły **Windows 11 27H2**.

---

## 1. Wymagania wstępne przed uruchomieniem AME Wizard

Przed wczytaniem pliku `dist/CustomPlaybook.apbx` w AME Wizard spełnij **wszystkie** poniższe warunki:

1. **Świeża instalacja systemu:** Windows 10 22H2 Pro x64 (`19045`) lub Windows 11 24H2/25H2/26H2 Pro x64 (`26100`, `26200`, `26300`). Nie uruchamiaj playbooka na wieloletnim, zaśmieconym systemie ani po innych modyfikatorach (ReviOS, AtlasOS, skrypty CTT).
2. **Wyłączenie 4 przełączników Windows Security (wymóg `DefenderToggled`):**
   - Otwórz **Zabezpieczenia systemu Windows → Ochrona przed wirusami i zagrożeniami → Zarządzaj ustawieniami**.
   - Wyłącz ręcznie:
     1. *Ochrona w czasie rzeczywistym* (Real-time protection)
     2. *Ochrona dostarczana z chmury* (Cloud-delivered protection)
     3. *Automatyczne przesyłanie próbek* (Automatic sample submission)
     4. *Ochrona przed naruszeniami* (Tamper Protection)
3. **Brak zewnętrznego antywirusa (wymóg `NoAntivirus`):** Odinstaluj wszelkie oprogramowanie AV rejestrujące się w `SecurityCenter2`.
4. **Brak oczekujących aktualizacji (wymóg `NoPendingUpdates`):** Zainstaluj aktualny pakiet zbiorczy i uruchom ponownie komputer, zanim uruchomisz AME Wizard (lub w przypadku czystego ISO bez sieci uruchom po pełnym załadowaniu pulpitu i upewnieniu się, że nie czeka restart WU).
5. **Stabilne połączenie z internetem (wymóg `Internet`):** Potrzebne do opcjonalnego pobrania wybranych w `FeaturePages` aplikacji oraz ewentualnej paczki językowej `pl-PL` na angielskim ISO Windows 11.
6. **Ścieżka konta użytkownika bez znaków spoza ASCII:** Ze względu na znany błąd biblioteki `SharpSevenZip` w AME Wizard, nazwa folderu profilu (`C:\Users\<Nazwa>`) oraz ścieżka, w której leży plik `.apbx`, nie powinny zawierać polskich znaków diakrytycznych (`ą, ć, ę, ł, ń, ó, ś, ź, ż`) ani znaków spoza ASCII.

---

## 2. Budowanie i walidacja pakietu `.apbx`

Wymagany jest **PowerShell 5.1+** oraz zainstalowany **7-Zip** (`7z.exe` w `PATH` lub `C:\Program Files\7-Zip\7z.exe`).

```powershell
# Sama walidacja XML, YAML, opcji FeaturePages, skryptow PS1 i sciezek:
powershell -ExecutionPolicy Bypass -File .\tools\validate-playbook.ps1

# Walidacja + zbudowanie i weryfikacja dist\CustomPlaybook.apbx (7z, haslo: malte):
powershell -ExecutionPolicy Bypass -File .\tools\build-apbx.ps1
```

Wygenerowany plik `dist/CustomPlaybook.apbx` zawiera `playbook.conf`, `Configuration/` oraz `Executables/` bezpośrednio w katalogu głównym (root) archiwum — gotowy do przeciągnięcia do okna AME Wizard.

---

## 3. Gotowość pod Windows 11 27H2

Na dzień tworzenia tego playbooka (listopad 2026) Microsoft nie ogłosił jeszcze finalnego numeru builda GA dla Windows 11 27H2 (wczesne kompilacje preview mieszczą się w przedziale `295xx–297xx`), dlatego w `<SupportedBuilds>` celowo nie wpisano zgadywanego numeru.

Cała logika w plikach YAML opiera się wyłącznie na warunkach `builds: ['>=22000']` (Windows 11) oraz `builds: ['<22000']` (Windows 10). Po premierze 27H2 wystarczy dopisać **jedną linijkę** w `src/playbook.conf`:

```xml
  <SupportedBuilds>
    <string>19045</string>
    <string>26100</string>
    <string>26200</string>
    <string>26300</string>
    <!-- Dopisz ponizej finalny build GA dla 27H2: -->
    <string>XXXXX</string>
  </SupportedBuilds>
```

Żaden plik YAML ani skrypt w `Executables/` nie wymaga modyfikacji. Po dopisaniu numeru przebuduj paczkę przez `tools/build-apbx.ps1`.

---

## 4. Kolejność wykonania i zakres zmian

Kolejność w `src/Configuration/main.yml` jest krytyczna i celowo zaprojektowana:

| Krok | Moduł | Opis zmian |
|---|---|---|
| **01** | `01-locale-pl.yml` | **WYKONYWANY JAKO PIERWSZY (przed blokadą WU).** Próbuje w bezpiecznym `try/catch` doinstalować pakiet UI `pl-PL` przez `Install-Language` na angielskim ISO Win 11. Zawsze lokalnie (100% offline) ustawia `pl-PL`, wyłączny układ klawiatury *Polski (programisty)* (`0415:00000415`, usuwa `en-US`), GeoID `191` (Polska), strefę czasową `Central European Standard Time` (Warszawa) oraz kopiuje ustawienia na ekran logowania. |
| **02** | `02-debloat-appx.yml` | Jawna lista usuwanych pakietów AppX + wpisy `Deprovisioned` w rejestrze. Usuwa Microsoft Store, cały ekosystem Xbox i Game Bar (+ usługi i **fix protokołów `ms-gamingoverlay` / `ms-gamebar`** na `systray.exe`), Copilot i Recall (w tym `DISM /Disable-Feature /FeatureName:Recall`), Widgets, Teams, Cortana, Spotify ze Store oraz OneDrive. |
| **03** | `03-debloat-edge.yml` | Usuwa **wyłącznie przeglądarkę Microsoft Edge** (`setup.exe --uninstall --force-uninstall --delete-profile`), usuwa skróty, blokuje reinstalację przeglądarki (`DoNotUpdateToEdgeWithChromium = 1`, GUID Edge Stable), **zachowując w pełni WebView2 Runtime** oraz pozostawiając usługi `edgeupdate`/`edgeupdatem` jako Manual (`3`). |
| **04** | `04-security-telemetry.yml` | Wyłącza Windows Defender (polityki, usługi, zadania + jednorazowe zadanie post-boot `DisableMDCorePostBoot` wzorem AtlasOS dla `MDCoreSvc`), Security Center, SmartScreen, Smart App Control, telemetrię (`AllowTelemetry = 0`), WER, usługi diagnostyczne, harmonogramy oraz blokady IFEO (`CompatTelRunner.exe`, `DeviceCensus.exe`). |
| **05** | `05-privacy.yml` | Wyłącza wszystkie uprawnienia Windows i aplikacji (`Deny` + polityki `AppPrivacy`), aplikacje w tle oraz automatyczne pobieranie plików / Storage Sense. **Jedyny wyjątek: `webcam` (Camera) i `microphone` (Microphone) pozostają jawnie `Allow`** (również dla aplikacji Win32 `NonPackaged`), a uprawnienia WGC (`graphicsCaptureProgrammatic`, `graphicsCaptureWithoutBorder`) są nietknięte dla poprawnego działania TikStream/streaming. |
| **06** | `06-personalization.yml` | Tapeta `Fill`, pełny tryb Dark (`AppsUseLightTheme = 0`, `SystemUsesLightTheme = 0`), wyłączona przezroczystość i AutoColorization, Lock Screen bez Spotlight (tło na ekranie logowania włączone), oczyszczone Menu Start i Pasek zadań z jawnym podziałem na Windows 10 (`<22000`) i Windows 11 (`>=22000`). |
| **07** | `07-search-indexing.yml` | Zatrzymuje i wyłącza usługę `WSearch` (`Start = 4`), wyłącza `IndexingEnabled` na wszystkich lokalnych dyskach NTFS (`Win32_Volume`) oraz całkowicie blokuje wyszukiwanie Bing/chmurowe w Menu Start. |
| **08** | `08-network-dns.yml` | Ustawia Cloudflare DNS (`1.1.1.1`, `1.0.0.1` + IPv6 `2606:4700:4700::1111`, `2606:4700:4700::1001`, jeśli adapter ma włączone `ms_tcpip6`) na wszystkich aktywnych fizycznych kartach sieciowych (niezależnie od języka systemu). Na Windows 11 włącza bezpieczny natywny **DoH** (`AutoUpgrade = $true`, `AllowFallbackToUdp = $true`). |
| **09** | `09-performance-qol.yml` | Wyłącznie mierzalne tweaki bez placebo: plan zasilania High Performance, wyłączone oszczędzanie energii USB/PCIe/dysków, brak hibernacji, `PowerThrottlingOff = 1`, MMCSS (`SystemResponsiveness = 10`, `NetworkThrottlingIndex = 0xFFFFFFFF`, priorytet `Games`), brak akceleracji myszy, Game Mode ON, HAGS ON (`HwSchMode = 2`), wyłączone zbędne usługi (`SysMain`, `MapsBroker`, `Fax`, `RemoteRegistry`, `RetailDemo`, `WalletService`) + QoL (rozszerzenia plików, Ten komputer, klasyczne menu kontekstowe Win 11, wyłączone Sticky/Filter/Toggle Keys, szybsze zamykanie). |
| **10** | `10-apps-install.yml` | Opcjonalna instalacja aplikacji wybranych w `FeaturePages` (bez Store i bez `winget`): Chrome, Discord, Spotify, Epic Games Launcher, Roblox, TikStream (+ VC++ x64 i .NET 10 Desktop Runtime). Instalatory per-user uruchamiane są **bez elevacji (`currentUser`)**. Logi zapisują się w `%TEMP%\playbook-apps.log`. |
| **11** | `11-windows-update-lock.yml` | **ZAWSZE OSTATNI KROK.** Zatrzymuje i trwale blokuje `wuauserv`, `UsoSvc`, `WaaSMedicSvc`, `DoSvc` (`Start = 4`), czyści ich `FailureActions`, usuwa zaplanowane zadania naprawcze (`WindowsUpdate`, `UpdateOrchestrator`, `WaaSMedic`) oraz ustawia pełne polityki blokujące aktualizacje i pobieranie sterowników. **Usługa `BITS` pozostaje nietknięta.** |

---

## 5. Jawna whitelista zachowanych komponentów

Playbook **nie stosuje** ślepego `Get-AppxPackage | Remove-AppxPackage`. Poniższe komponenty są celowo zachowywane:

| Zachowany komponent / pakiet | Uzasadnienie |
|---|---|
| `Microsoft.AIFabric.CBS.*` | **KRYTYCZNE na Windows 11 26H2 (build `26300`).** Usunięcie tego pakietu psuje okno dialogowe `OpenWith.exe` („Otwórz za pomocą”) oraz wybór aplikacji domyślnych w Ustawieniach (potwierdzony bug `meetrevision/playbook#246`). |
| `Microsoft Edge WebView2 Runtime` (+ `edgeupdate`/`edgeupdatem` jako Manual) | Choć TikStream korzysta z własnego wbudowanego `CefSharp`, z WebView2 korzysta **Roblox** oraz natywne komponenty powłoki Windows 11. Usunięcie samej przeglądarki Edge bez ruszania `EdgeWebView` zapobiega błędom i ponownemu pobieraniu WebView2 w tle. |
| `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`, `Microsoft.WindowsAppRuntime.*`, `Microsoft.NET.Native.*` | Podstawowe biblioteki uruchomieniowe WinUI / C++ / XAML wymagane przez Ustawienia Windows i nowoczesne aplikacje systemowe. |
| `Microsoft.Services.Store.Engagement` | Zależność części natywnych kontrolek UI systemu (zachowana dla uniknięcia błędów zależności). |
| `ShellExperienceHost`, `StartMenuExperienceHost`, `Client.CBS`, `Windows.Search`, `ImmersiveControlPanel` | Rdzeń powłoki graficznej: Menu Start, Pasek zadań, Centrum akcji, lokalne wyszukiwanie plików i aplikacja Ustawienia. |
| Kodeki systemowe i panele sterowników OEM (NVIDIA, AMD, Intel, Realtek) | Niezbędne do poprawnej obsługi paneli sterowania GPU/audio oraz dekodowania multimediów. |
| Usługa `BITS` (Background Intelligent Transfer Service) | Celowo nie jest wyłączana podczas blokady Windows Update, ponieważ korzysta z niej wiele zewnętrznych instalatorów i aplikacji. |

---

## 6. Znane uwagi i konfiguracje opcjonalne

- **HAGS (`HwSchMode = 2`):** Domyślnie włączony (wymagany m.in. pod DLSS Frame Generation na nowoczesnych kartach NVIDIA RTX). Jeśli na konkretnej konfiguracji ze streamingiem (np. OBS / TikStream przy 100% obciążenia GPU) zaobserwujesz gubienie klatek enkodera, przełącz na wartość `1` (wyłączony) i zrestartuj PC:
  ```powershell
  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 1 -Type DWord
  ```
- **Roblox brak flagi full-silent:** `RobloxPlayerInstaller.exe` nie posiada oficjalnego przełącznika `/quiet`, ale działa w trybie unattended (bez klikania) w kontekście `currentUser`. Skrypt `install-roblox.ps1` obsługuje timeout (180 s) i zamyka auto-uruchomione okno klienta po instalacji.
- **Angielskie ISO + pakiet `pl-PL`:** Na Windows 11 angielskim ISO krok `01-locale-pl.yml` próbuje pobrać pakiet językowy `pl-PL` przez `Install-Language` zanim Windows Update zostanie wyłączony. Jeśli brak sieci lub system to Windows 10, krok ten nie przerywa playbooka — format regionalny `pl-PL`, wyłączna klawiatura Polski (programisty), GeoID 191 i strefa czasowa Warszawa są ustawiane w 100% lokalnie.

---

## 7. Checklista testowa na maszynie wirtualnej (VMware / VirtualBox)

Zanim wdrożysz playbook na głównym komputerze, wykonaj pełny test na świeżej VM (zrób snapshot przed uruchomieniem AME Wizard!) i zweryfikuj po kolei:

- [ ] **1. Kamera i mikrofon (wyjątek prywatności):**
  - Otwórz **Ustawienia → Prywatność i zabezpieczenia**: sprawdź, że *Lokalizacja*, *Kontakty*, *Kalendarz*, *Aplikacje w tle* itp. są **Wyłączone**, a **Kamera** i **Mikrofon** są **Włączone** (w tym dostęp dla aplikacji klasycznych).
  - Sprawdź działanie mikrofonu i kamery w Discordzie lub przeglądarce Chrome (np. strona testowa WebRTC).
- [ ] **2. DNS Cloudflare (IPv4/IPv6) oraz DoH na Windows 11:**
  ```powershell
  Get-DnsClientServerAddress | Where-Object { $_.ServerAddresses.Count -gt 0 }
  # Na Windows 11 dodatkowo:
  Get-DnsClientDohServerAddress | Where-Object { $_.ServerAddress -in @('1.1.1.1','1.0.0.1','2606:4700:4700::1111','2606:4700:4700::1001') }
  ```
  Potwierdź obecność `1.1.1.1` / `1.0.0.1` (oraz adresów IPv6, jeśli karta ma IPv6) i `AutoUpgrade = True`, `AllowFallbackToUdp = True` na Win 11.
- [ ] **3. Trwałość blokady Windows Update po 2 pełnych restartach:**
  Po pierwszym i drugim restarcie VM wykonaj:
  ```powershell
  @('wuauserv','UsoSvc','WaaSMedicSvc','DoSvc','BITS') | ForEach-Object {
      $svc = Get-Service $_ -ErrorAction SilentlyContinue
      $reg = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$_" -ErrorAction SilentlyContinue).Start
      [PSCustomObject]@{ Name = $_; Status = $svc.Status; StartReg = $reg }
  }
  ```
  Oczekiwany wynik: `wuauserv`, `UsoSvc`, `WaaSMedicSvc`, `DoSvc` mają `Status = Stopped` i `StartReg = 4`, natomiast `BITS` pozostaje aktywne (nie ma `4`). Sprawdź też, że `MDCoreSvc` ma `Start = 4` po restarcie.
- [ ] **4. Brak wyskakującego błędu `ms-gamingoverlay` / `ms-gamebar`:**
  Uruchom grę lub przetestuj z PowerShell:
  ```powershell
  Start-Process 'ms-gamingoverlay:'
  Start-Process 'ms-gamebar:'
  ```
  Nie powinno pojawić się żadne okno z błędem „Potrzebujesz nowej aplikacji, aby otworzyć ten link ms-gamingoverlay”.
- [ ] **5. Weryfikacja braku regresji `Microsoft.AIFabric.CBS` na Windows 11 26H2:**
  Utwórz dowolny plik `test.txt` na pulpicie, kliknij PPM → **Otwórz za pomocą → Wybierz inną aplikację**. Okno `OpenWith.exe` musi otworzyć się natychmiast i poprawnie wyświetlić listę aplikacji.
- [ ] **6. Działanie opcjonalnych aplikacji (jeśli zaznaczone w `FeaturePages`):**
  Sprawdź uruchomienie każdej wybranej aplikacji oraz log `%TEMP%\playbook-apps.log`:
  - Google Chrome (otwiera strony, działa po DNS Cloudflare)
  - Discord (uruchamia się z `%LocalAppData%\Discord`, wykrywa mikrofon/kamerę)
  - Spotify (uruchamia się z `%APPDATA%\Spotify`, bez konfliktu ze Store)
  - Epic Games Launcher (otwiera okno logowania)
  - Roblox Player (obecny w `%LocalAppData%\Roblox\Versions`, WebView2 obecny w `Program Files (x86)\Microsoft\EdgeWebView`)
  - TikStream (uruchamia się poprawnie, obecne `.NET 10 Desktop Runtime` i `VC++ x64`)
- [ ] **7. Język, klawiatura, strefa czasowa i brak indeksowania:**
  ```powershell
  Get-WinUserLanguageList            # Wylacznie pl-PL z 0415:00000415 (brak en-US!)
  Get-Culture                        # pl-PL
  Get-WinHomeLocation                # GeoId = 191
  Get-TimeZone                       # Central European Standard Time
  Get-Service WSearch                # Status = Stopped, StartType = Disabled
  Get-CimInstance Win32_Volume -Filter "DriveType = 3" | Select-Object DriveLetter, FileSystem, IndexingEnabled
  ```
  Potwierdź `IndexingEnabled = False` na dyskach NTFS, brak wyników z sieci Bing w Menu Start oraz brak przeglądarki Microsoft Edge.
