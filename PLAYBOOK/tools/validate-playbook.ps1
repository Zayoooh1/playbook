#Requires -Version 5.1
<#
.SYNOPSIS
    Waliduje strukture i poprawnosc playbooka AME Wizard w katalogu src/.
.DESCRIPTION
    Sprawdza:
    - Poprawnosc parsowania src/playbook.conf jako XML
    - Wymagane tagi metadanych, format Version (1 / 0.1 / 0.0.1) i poprawny UUIDv4 w UniqueId
    - Obslugiwane nazwy Requirements oraz spojnosc FeaturePages (w tym DefaultOption dla RadioPage)
    - Brak przestarzalego custom.yml oraz sekcji tasks:
    - Wylacznie 15 oficjalnych akcji AME Wizard w plikach YAML (brak !defender, !lineInFile, !user, !shortcut, !update)
    - Brak niedozwolonych parametrow (architectures, minBuild, maxBuild)
    - Brak pulapek parsera (laczenie & z ! w option:, same negacje w builds:/options:)
    - Spojnosc opcji option:/options: w YAML z <Name> w FeaturePages
    - Poprawny prefix \ dla !scheduledTask oraz jawne wait: dla !powerShell i !cmd
    - Fizyczne istnienie wszystkich plikow wskazywanych przez !task oraz exeDir: true
#>

[CmdletBinding()]
param(
    [string]$SrcDir = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SrcDir)) {
    $SrcDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
}

$errors   = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Add-Error   { param([string]$Msg) $errors.Add($Msg);   Write-Host "  [ERROR] $Msg" -ForegroundColor Red }
function Add-Warning { param([string]$Msg) $warnings.Add($Msg); Write-Host "  [WARN]  $Msg" -ForegroundColor Yellow }
function Add-Ok      { param([string]$Msg) Write-Host "  [OK]    $Msg" -ForegroundColor Green }

Write-Host "=== Walidacja playbooka AME Wizard ===" -ForegroundColor Cyan
Write-Host "Katalog zrodlowy: $SrcDir`n"

if (-not (Test-Path -LiteralPath $SrcDir)) {
    Add-Error "Katalog zrodlowy nie istnieje: $SrcDir"
    exit 1
}

# ==============================================================================
# 1. WALIDACJA src/playbook.conf (XML)
# ==============================================================================
Write-Host "[1/4] Sprawdzanie src/playbook.conf..." -ForegroundColor Cyan
$confPath = Join-Path $SrcDir 'playbook.conf'
$declaredOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

if (-not (Test-Path -LiteralPath $confPath)) {
    Add-Error "Brak wymaganego pliku: $confPath"
} else {
    try {
        [xml]$xml = Get-Content -LiteralPath $confPath -Raw -Encoding UTF8
        Add-Ok 'Poprawna skladnia XML playbook.conf.'
    } catch {
        Add-Error "Blad parsowania XML w playbook.conf: $($_.Exception.Message)"
        $xml = $null
    }

    if ($null -ne $xml) {
        if ($xml.DocumentElement.LocalName -ne 'Playbook') {
            Add-Error "Glowny tag XML musi miec nazwe <Playbook>, znaleziono: <$($xml.DocumentElement.LocalName)>"
        }

        $pb = $xml.Playbook
        $requiredMeta = @('Name', 'Username', 'ShortDescription', 'Title', 'Description', 'Details', 'Version', 'UniqueId')
        foreach ($tag in $requiredMeta) {
            $val = $pb.$tag
            if ([string]::IsNullOrWhiteSpace($val)) {
                Add-Error "Brak lub pusta wartosc wymaganego tagu <$tag> w playbook.conf."
            }
        }

        # Format Version: 1, 0.1 lub 0.0.1
        if ($pb.Version -notmatch '^\d+(\.\d+){0,2}$') {
            Add-Error "Nieprawidlowy format <Version>: '$($pb.Version)' (wymagany format: 1, 0.1 lub 0.0.1)."
        } else {
            Add-Ok "Poprawny format Version: $($pb.Version)"
        }

        # Format UUIDv4
        if ($pb.UniqueId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') {
            Add-Error "Nieprawidlowy UUIDv4 w <UniqueId>: '$($pb.UniqueId)'."
        } else {
            Add-Ok "Poprawny UUIDv4 UniqueId: $($pb.UniqueId)"
        }

        # SupportedBuilds
        $buildsNodes = @($pb.SupportedBuilds.string)
        if ($buildsNodes.Count -eq 0) {
            Add-Warning 'Brak wpisow w <SupportedBuilds>.'
        } else {
            foreach ($b in $buildsNodes) {
                if ($b -notmatch '^\d{5}$') {
                    Add-Error "Nieprawidlowy numer builda w <SupportedBuilds>: '$b'"
                }
            }
            Add-Ok "Obslugiwane buildy: $($buildsNodes -join ', ')"
        }

        # Requirements
        $validRequirements = @(
            'DefenderToggled', 'DefenderDisabled', 'UCPDDisabled',
            'Internet', 'NoAntivirus', 'NoPendingUpdates', 'PluggedIn'
        )
        $reqNodes = @($pb.Requirements.Requirement)
        foreach ($req in $reqNodes) {
            if ($req -notin $validRequirements) {
                Add-Error "Nieznany lub nieobslugiwany <Requirement>: '$req'"
            }
        }
        Add-Ok "Zweryfikowano Requirements ($($reqNodes.Count) szt.): $($reqNodes -join ', ')"

        # FeaturePages
        $validPageTypes = @('CheckboxPage', 'RadioPage', 'RadioImagePage')
        if ($null -ne $pb.FeaturePages) {
            foreach ($page in $pb.FeaturePages.ChildNodes) {
                if ($page.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                if ($page.LocalName -notin $validPageTypes) {
                    Add-Error "Nieobslugiwany typ strony w <FeaturePages>: <$($page.LocalName)>"
                    continue
                }

                $desc = $page.GetAttribute('Description')
                if ([string]::IsNullOrWhiteSpace($desc)) {
                    Add-Error "Strona <$($page.LocalName)> nie posiada atrybutu Description."
                } elseif ($desc.Length -lt 50 -or $desc.Length -gt 85) {
                    Add-Warning "Atrybut Description strony <$($page.LocalName)> ma $($desc.Length) znakow (zalecane 50-85)."
                }

                $pageOptionNames = [System.Collections.Generic.List[string]]::new()
                if ($null -ne $page.Options) {
                    foreach ($opt in $page.Options.ChildNodes) {
                        if ($opt.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                        $optName = $opt.Name
                        if ([string]::IsNullOrWhiteSpace($optName)) {
                            Add-Error "Opcja w <$($page.LocalName)> nie posiada tagu <Name>."
                        } else {
                            if (-not $declaredOptions.Add($optName)) {
                                Add-Error "Zduplikowana nazwa opcji w FeaturePages: '$optName'."
                            }
                            $pageOptionNames.Add($optName)
                        }
                        if ([string]::IsNullOrWhiteSpace($opt.Text)) {
                            Add-Error "Opcja '$optName' nie posiada tagu <Text>."
                        }
                    }
                }

                if ($page.LocalName -in @('RadioPage', 'RadioImagePage')) {
                    $defOpt = $page.GetAttribute('DefaultOption')
                    if ([string]::IsNullOrWhiteSpace($defOpt) -or ($defOpt -notin $pageOptionNames)) {
                        Add-Error "Strona <$($page.LocalName)> ma nieprawidlowy DefaultOption='$defOpt' (musi odpowiadac <Name> jednej z opcji)."
                    }
                }
            }
            Add-Ok "Zweryfikowano FeaturePages ($($declaredOptions.Count) opcji: $(@($declaredOptions) -join ', '))."
        }
    }
}

# ==============================================================================
# 2. STRUKTURA KATALOGOW CONFIGURATION I EXECUTABLES
# ==============================================================================
Write-Host "`n[2/4] Sprawdzanie struktury Configuration/ i Executables/..." -ForegroundColor Cyan
$configDir = Join-Path $SrcDir 'Configuration'
$execDir   = Join-Path $SrcDir 'Executables'
$mainYml   = Join-Path $configDir 'main.yml'
$legacyYml = Join-Path $configDir 'custom.yml'

if (-not (Test-Path -LiteralPath $mainYml)) {
    Add-Error "Brak glownego pliku wejsciowego: $mainYml"
} else {
    Add-Ok 'Znaleziono Configuration/main.yml.'
}

if (Test-Path -LiteralPath $legacyYml) {
    Add-Error 'Wykryto przestarzaly plik Configuration/custom.yml - uzywaj wylacznie main.yml!'
}

if (-not (Test-Path -LiteralPath $execDir)) {
    Add-Error "Brak katalogu skryptow: $execDir"
}

# ==============================================================================
# 3. WALIDACJA WSZYSTKICH PLIKOW YAML
# ==============================================================================
Write-Host "`n[3/4] Sprawdzanie wszystkich plikow YAML..." -ForegroundColor Cyan

$allowedActions = @(
    '!task', '!status', '!writeStatus', '!registryValue', '!registryKey',
    '!service', '!scheduledTask', '!appx', '!file', '!taskKill',
    '!run', '!powerShell', '!cmd', '!systemPackage', '!download', '!software'
)
$forbiddenActions = @('!defender', '!lineInFile', '!user', '!shortcut', '!update')
$forbiddenParams  = @('architectures', 'minBuild', 'maxBuild')

$yamlFiles = @(Get-ChildItem -Path $configDir -Filter '*.yml' -Recurse -File | Sort-Object FullName)
if ($yamlFiles.Count -eq 0) {
    Add-Error "Nie znaleziono zadnych plikow .yml w $configDir"
}

$referencedTasks   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$referencedScripts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($file in $yamlFiles) {
    $relPath = $file.FullName.Substring($SrcDir.Length).TrimStart('\')
    $lines   = Get-Content -LiteralPath $file.FullName -Encoding UTF8
    $rawText = $lines -join "`n"

    # Podstawowe sprawdzenia YAML
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
        Add-Error "${relPath}: Plik YAML powinien zaczynac sie od '---'."
    }
    if ($rawText -notmatch '(?m)^actions:\s*$') {
        Add-Error "${relPath}: Brak sekcji 'actions:'."
    }
    if ($rawText -match '(?m)^tasks:\s*$') {
        Add-Error "${relPath}: Uzyto przestarzalej sekcji 'tasks:' zamiast 'actions:'."
    }
    if ($rawText -match '(?i)(#\s*TODO|FIXME|\bTODO:)') {
        Add-Error "${relPath}: Wykryto placeholder TODO/FIXME."
    }

    # Sledzenie biezacego bloku akcji (wieloliniowe akcje YAML)
    $currentActionTag   = $null
    $currentBlockStart  = 0
    $currentBlockLines  = [System.Collections.Generic.List[string]]::new()

    $validateActionBlock = {
        param([string]$Tag, [int]$StartLine, [string[]]$BlockLines, [string]$RelFile)
        if ([string]::IsNullOrEmpty($Tag)) { return }
        $joined = $BlockLines -join "`n"

        # 1. !task -> sprawdz czy plik docelowy istnieje
        if ($Tag -eq '!task') {
            if ($joined -match "path:\s*['""]?([^'""}\r\n,]+)['""]?") {
                $tPath = $Matches[1].Trim()
                $fullTaskPath = Join-Path $configDir ($tPath -replace '/', '\')
                if (-not (Test-Path -LiteralPath $fullTaskPath)) {
                    Add-Error "${RelFile}:${StartLine}: !task wskazuje nieistniejacy plik '$tPath'."
                } else {
                    [void]$referencedTasks.Add($fullTaskPath)
                }
            } else {
                Add-Error "${RelFile}:${StartLine}: Akcja !task nie zawiera parametru path:."
            }
        }

        # 2. !scheduledTask -> path musi zaczynac sie od \
        if ($Tag -eq '!scheduledTask') {
            if ($joined -match "path:\s*['""]([^'""]+)['""]") {
                $stPath = $Matches[1]
                if (-not $stPath.StartsWith('\')) {
                    Add-Error "${RelFile}:${StartLine}: !scheduledTask path musi zaczynac sie od '\' (znaleziono '$stPath')."
                }
            } else {
                Add-Error "${RelFile}:${StartLine}: !scheduledTask bez poprawnego parametru path w cudzyslowach."
            }
        }

        # 3. !powerShell i !cmd -> jawne wait: true
        if ($Tag -in @('!powerShell', '!cmd')) {
            if ($joined -notmatch '\bwait:\s*(true|false)\b') {
                Add-Error "${RelFile}:${StartLine}: Akcja $Tag powinna jawnie okreslac wait: true."
            }
        }

        # 4. exeDir: true -> sprawdz czy wywolywany skrypt/exe istnieje w src/Executables/
        if ($joined -match '\bexeDir:\s*true\b') {
            $scriptMatches = [regex]::Matches($joined, '([A-Za-z0-9_.\-]+\.(?:ps1|cmd|bat))')
            if ($scriptMatches.Count -eq 0) {
                Add-Warning "${RelFile}:${StartLine}: exeDir: true bez wykrytej nazwy skryptu .ps1/.cmd/.bat."
            } else {
                foreach ($m in $scriptMatches) {
                    $scriptName = $m.Groups[1].Value
                    $scriptFull = Join-Path $execDir $scriptName
                    if (-not (Test-Path -LiteralPath $scriptFull)) {
                        Add-Error "${RelFile}:${StartLine}: Brak skryptu '$scriptName' w src/Executables/."
                    } else {
                        [void]$referencedScripts.Add($scriptFull)
                    }
                }
            }
        }

        # 5. Walidacja option: (zakaz laczenia & z !, sprawdzanie z FeaturePages)
        if ($joined -match "\boption:\s*['""]([^'""]+)['""]") {
            $optExpr = $Matches[1].Trim()
            if ($optExpr.Contains('&') -and $optExpr.Contains('!')) {
                Add-Error "${RelFile}:${StartLine}: Pulapka parsera - option: '$optExpr' laczy '&' oraz '!'."
            }
            $tokens = $optExpr -split '[&|]'
            foreach ($tok in $tokens) {
                $clean = $tok.Trim().TrimStart('!').Trim()
                if (-not [string]::IsNullOrEmpty($clean) -and -not $declaredOptions.Contains($clean)) {
                    Add-Error "${RelFile}:${StartLine}: Opcja '$clean' w option: nie istnieje w FeaturePages w playbook.conf."
                }
            }
        }

        # 6. Walidacja options: [...] (zakaz samych negacji, sprawdzanie z FeaturePages)
        if ($joined -match '\boptions:\s*\[([^\]]+)\]') {
            $items = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { $_ -ne '' }
            $hasPositive = $false
            foreach ($it in $items) {
                if (-not $it.StartsWith('!')) { $hasPositive = $true }
                $clean = $it.TrimStart('!').Trim()
                if (-not $declaredOptions.Contains($clean)) {
                    Add-Error "${RelFile}:${StartLine}: Opcja '$clean' w options: nie istnieje w FeaturePages w playbook.conf."
                }
            }
            if ($items.Count -gt 0 -and -not $hasPositive) {
                Add-Error "${RelFile}:${StartLine}: Pulapka parsera - options: zawiera wylacznie negacje (!) bez warunku pozytywnego."
            }
        }

        # 7. Walidacja builds: [...] (zakaz samych negacji)
        if ($joined -match '\bbuilds:\s*\[([^\]]+)\]') {
            $bItems = $Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { $_ -ne '' }
            $hasPosBuild = $false
            foreach ($bi in $bItems) {
                if (-not $bi.StartsWith('!')) { $hasPosBuild = $true }
            }
            if ($bItems.Count -gt 0 -and -not $hasPosBuild) {
                Add-Error "${RelFile}:${StartLine}: Pulapka parsera - builds: zawiera wylacznie negacje (!) bez warunku pozytywnego."
            }
        }
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNum = $i + 1
        $line    = $lines[$i]

        # Zakaz tabulatorow w YAML
        if ($line -match "^\t") {
            Add-Error "${relPath}:${lineNum}: Wykryto znak tabulacji (TAB) na poczatku linii YAML."
        }

        # Pomin komentarze
        if ($line -match '^\s*#') { continue }

        # Zakazane parametry
        foreach ($fp in $forbiddenParams) {
            if ($line -match "(?:^|[\s{,])$fp\s*:") {
                Add-Error "${relPath}:${lineNum}: Zakazany parametr '$fp' (nie istnieje w AME Wizard)."
            }
        }

        # Wykrywanie nowego wpisu akcji "- !tag:"
        if ($line -match '^\s*-\s+(![A-Za-z0-9_]+)\s*:') {
            # Zwaliduj poprzedni blok
            & $validateActionBlock $currentActionTag $currentBlockStart $currentBlockLines.ToArray() $relPath

            $tag = $Matches[1]
            if ($tag -in $forbiddenActions) {
                Add-Error "${relPath}:${lineNum}: ZAKAZANY tag akcji '$tag' (nieaktywny/nieistniejacy w TrustedUninstaller)."
            } elseif ($tag -notin $allowedActions) {
                Add-Error "${relPath}:${lineNum}: Nieznany tag akcji '$tag' spoza 15 wspieranych akcji AME Wizard."
            }

            $currentActionTag  = $tag
            $currentBlockStart = $lineNum
            $currentBlockLines.Clear()
            $currentBlockLines.Add($line)
        } elseif ($null -ne $currentActionTag -and $line -match '^\s+\S') {
            $currentBlockLines.Add($line)
        }
    }

    # Zwaliduj ostatni blok w pliku
    & $validateActionBlock $currentActionTag $currentBlockStart $currentBlockLines.ToArray() $relPath
    Add-Ok "Zwalidowano $relPath"
}

# ==============================================================================
# 4. SPRAWDZENIE KOLEJNOSCI W main.yml ORAZ OSJIEROCONYCH PLIKOW
# ==============================================================================
Write-Host "`n[4/4] Sprawdzanie kolejnosci zadan i spojnosci plikow..." -ForegroundColor Cyan

if (Test-Path -LiteralPath $mainYml) {
    $mainContent = Get-Content -LiteralPath $mainYml -Raw -Encoding UTF8
    $taskOrder = [regex]::Matches($mainContent, "!task:\s*\{\s*path:\s*'([^']+)'\s*\}") | ForEach-Object { $_.Groups[1].Value }
    if ($taskOrder.Count -gt 0) {
        if ($taskOrder[0] -ne 'Tasks/01-locale-pl.yml') {
            Add-Error "Pierwszym zadaniem w main.yml musi byc 'Tasks/01-locale-pl.yml' (znaleziono: '$($taskOrder[0])')."
        } else {
            Add-Ok 'Pierwsze zadanie w main.yml to Tasks/01-locale-pl.yml (przed blokada WU).'
        }
        if ($taskOrder[-1] -ne 'Tasks/11-windows-update-lock.yml') {
            Add-Error "Ostatnim zadaniem w main.yml musi byc 'Tasks/11-windows-update-lock.yml' (znaleziono: '$($taskOrder[-1])')."
        } else {
            Add-Ok 'Ostatnie zadanie w main.yml to Tasks/11-windows-update-lock.yml.'
        }
    }
}

# Sprawdzenie czy wszystkie pliki w Tasks/ sa wywolane z main.yml
$allTaskFiles = Get-ChildItem -Path (Join-Path $configDir 'Tasks') -Filter '*.yml' -File -ErrorAction SilentlyContinue
foreach ($tf in $allTaskFiles) {
    if (-not $referencedTasks.Contains($tf.FullName)) {
        Add-Warning "Plik zadania nie jest wywolywany przez !task: Tasks/$($tf.Name)"
    }
}

# Sprawdzenie skladni PowerShell wszystkich skryptow w src/Executables/
$allScripts = Get-ChildItem -Path $execDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($sc in $allScripts) {
    $parseErrors = $null
    $tokens      = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($sc.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        foreach ($pe in $parseErrors) {
            Add-Error "Blad skladni PowerShell w Executables/$($sc.Name):$($pe.Extent.StartLineNumber): $($pe.Message)"
        }
    } else {
        Add-Ok "Poprawna skladnia PowerShell: Executables/$($sc.Name)"
    }
    if (-not $referencedScripts.Contains($sc.FullName)) {
        Add-Warning "Skrypt nie jest wywolywany z zadnego pliku YAML (exeDir: true): Executables/$($sc.Name)"
    }
}

# ==============================================================================
# PODSUMOWANIE
# ==============================================================================
Write-Host "`n=== Podsumowanie walidacji ===" -ForegroundColor Cyan
Write-Host "Bledy:       $($errors.Count)"
Write-Host "Ostrzezenia: $($warnings.Count)"

if ($errors.Count -gt 0) {
    Write-Host "`nWALIDACJA NIEUDANA! Popraw powyzsze bledy przed zbudowaniem .apbx." -ForegroundColor Red
    exit 1
}

Write-Host "`nWALIDACJA ZAKONCZONA SUKCESEM." -ForegroundColor Green
exit 0
