#Requires -Version 5.1
<#
.SYNOPSIS
    Konfiguruje serwery DNS Cloudflare (IPv4 oraz IPv6) na aktywnych fizycznych kartach sieciowych
    oraz wlacza bezpieczny natywny DoH (z fallbackiem do UDP) na Windows 11.
.DESCRIPTION
    Uruchamiany w kontekscie currentUserElevated. Niezalezny od jezyka systemu Windows
    (nie polega na nazwach "Ethernet" / "Wi-Fi", tylko na Get-NetAdapter -Physical ze statusem Up).
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$LogPath = Join-Path $env:TEMP 'playbook-dns.log'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $line
}

$ipv4Servers = @('1.1.1.1', '1.0.0.1')
$ipv6Servers = @('2606:4700:4700::1111', '2606:4700:4700::1001')
$allServers  = $ipv4Servers + $ipv6Servers
$dohTemplate = 'https://cloudflare-dns.com/dns-query'

Write-Log 'Rozpoczynam konfiguracje DNS Cloudflare.'

# 1. Konfiguracja adresow DNS na wszystkich aktywnych fizycznych adapterach sieciowych
try {
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
    if (-not $adapters) {
        Write-Log 'Nie znaleziono zadnego aktywnego fizycznego adaptera sieciowego (Status = Up).'
    }

    foreach ($nic in $adapters) {
        try {
            $ipv6Binding = Get-NetAdapterBinding -Name $nic.Name -ComponentID 'ms_tcpip6' -ErrorAction SilentlyContinue
            $hasIpv6 = ($null -ne $ipv6Binding -and $ipv6Binding.Enabled -eq $true)

            if ($hasIpv6) {
                Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $allServers -ErrorAction Stop
                Write-Log "Ustawiono DNS IPv4+IPv6 Cloudflare na karcie '$($nic.Name)' (ifIndex=$($nic.ifIndex))."
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $ipv4Servers -ErrorAction Stop
                Write-Log "Ustawiono DNS IPv4 Cloudflare na karcie '$($nic.Name)' (ifIndex=$($nic.ifIndex), IPv6 wylaczone)."
            }
        } catch {
            Write-Log "Blad konfiguracji DNS na karcie '$($nic.Name)': $($_.Exception.Message)"
        }
    }
} catch {
    Write-Log "Blad pobierania kart sieciowych: $($_.Exception.Message)"
}

# 2. Natywny DoH Cloudflare na Windows 11 (Build >= 22000) z bezpiecznym fallbackiem do UDP
$osBuild = [System.Environment]::OSVersion.Version.Build
Write-Log "Wykryty build systemu Windows: $osBuild"

if ($osBuild -ge 22000) {
    $getDohCmd = Get-Command -Name 'Get-DnsClientDohServerAddress' -ErrorAction SilentlyContinue
    if ($null -ne $getDohCmd) {
        foreach ($ip in $allServers) {
            try {
                $existing = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
                if ($null -ne $existing) {
                    Set-DnsClientDohServerAddress -ServerAddress $ip `
                        -DohTemplate $dohTemplate `
                        -AutoUpgrade $true `
                        -AllowFallbackToUdp $true `
                        -ErrorAction Stop
                    Write-Log "Zaktualizowano wpis DoH dla $ip (AutoUpgrade=True, AllowFallbackToUdp=True)."
                } else {
                    Add-DnsClientDohServerAddress -ServerAddress $ip `
                        -DohTemplate $dohTemplate `
                        -AutoUpgrade $true `
                        -AllowFallbackToUdp $true `
                        -ErrorAction Stop
                    Write-Log "Dodano wpis DoH dla $ip (AutoUpgrade=True, AllowFallbackToUdp=True)."
                }
            } catch {
                Write-Log "Ostrzezenie DoH dla ${ip}: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Log 'Cmdlety DnsClientDohServerAddress niedostepne - pomijam DoH.'
    }
} else {
    Write-Log 'System Windows 10 (<22000) - pomijam natywna konfiguracje DoH.'
}

# 3. Czyszczenie pamieci podrecznej DNS
try {
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Log 'Wyczyszczono cache klienta DNS.'
} catch {
    Write-Log "Ostrzezenie Clear-DnsClientCache: $($_.Exception.Message)"
}

Write-Log 'Zakonczono konfiguracje DNS Cloudflare.'
exit 0
