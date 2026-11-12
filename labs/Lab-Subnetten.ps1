<#
.SYNOPSIS
    Lab - Subnetten: werkt elke oefening van het lab stap voor stap uit.

.DESCRIPTION
    Educatief PowerShell-script voor de opdracht "Lab - Subnetten".
    Het toont voor elke oefening dezelfde redenering als op papier:

        1. Wat heb je?            (prefix, masker, hostbits, aantal adressen)
        2. Hoeveel bits leen je?  (of: hoeveel hostbits heb je nodig?)
        3. Nieuw CIDR
        4. Nieuw subnetmask in decimalen (met de binaire vorm)
        5. Stapgrootte / blokgrootte
        6. De subnetten, met bruikbaar bereik en broadcast
        7. Controle en invulblad

    Onderdelen die het script uitwerkt:
        A  Gelijk verdelen      (A1-A6)
        B  Host based verdelen  (B1-B4)
        C  VLSM                 (C1-C2)
        D  Cases                (groep 1-4)

    Het script rekent zelf (het zijn geen hardcoded antwoorden): draai -Check
    om de rekenkern tegen de gekende uitkomsten van het lab te controleren.

    Bedoeld om je eigen werk na te kijken. Probeer eerst zelf.

.PARAMETER All
    Alle oefeningen na elkaar, zonder menu en zonder pauzes (antwoordsleutel).

.PARAMETER Exercise
    Een enkele oefening, bijvoorbeeld -Exercise A2 of -Exercise D4.

.PARAMETER Step
    Pauzeer na elke stap, zodat je kan meevolgen op papier.

.PARAMETER Theory
    Alleen de theorie: de methode in 6 stappen, de machtentabel en de maskertabel.

.PARAMETER Check
    Zelftest: vergelijkt de berekende uitkomsten met de antwoorden van het lab.
    Exitcode 0 = alles klopt.

.PARAMETER Network
    EIGEN OPDRACHT. Het netwerk dat je wil verdelen, bijvoorbeeld 192.168.10.0/24
    (of met masker: "192.168.10.0 255.255.255.0"). Combineer met precies een van:
    -Subnets, -Hosts of -Vlsm.

.PARAMETER Subnets
    Eigen opdracht, gelijk verdelen: in hoeveel subnetten verdelen?

.PARAMETER Hosts
    Eigen opdracht, host based: hoeveel hosts moet elk subnet bevatten?

.PARAMETER Vlsm
    Eigen opdracht, VLSM: lijst met hosts per subnet, bv. -Vlsm 100,50,30,10   (of tussen aanhalingstekens: "100 50 30 10")

.PARAMETER Show
    Eigen opdracht: welke subnetnummers komen in het invulblad? Bv. -Show 1,2,7

.PARAMETER Full
    Toon altijd alle rijen van elke tabel (standaard worden lange tabellen ingekort).

.PARAMETER NoPause
    Nooit op Enter wachten (handig in een pipeline of in een journaalopname).

.PARAMETER SaveTo
    Schrijf de volledige uitwerking ook naar een tekstbestand.

.EXAMPLE
    pwsh ./labs/Lab-Subnetten.ps1

.EXAMPLE
    pwsh ./labs/Lab-Subnetten.ps1 -Exercise A1 -Step

.EXAMPLE
    pwsh ./labs/Lab-Subnetten.ps1 -All -NoPause -SaveTo antwoordsleutel.txt

.EXAMPLE
    pwsh ./labs/Lab-Subnetten.ps1 -Check

.EXAMPLE
    pwsh ./labs/Lab-Subnetten.ps1 -Network 192.168.10.0/24 -Subnets 5

.EXAMPLE
    pwsh ./labs/Lab-Subnetten.ps1 -Network 172.16.0.0/16 -Hosts 500 -Show 1,2,9

.EXAMPLE
    pwsh ./labs/Lab-Subnetten.ps1 -Network 10.1.0.0/24 -Vlsm 100,50,30,10,10
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$All,
    [string]$Exercise,
    [switch]$Step,
    [switch]$Theory,
    [switch]$Check,
    [switch]$NoPause,
    [string]$SaveTo,
    [string]$Network,
    [long]$Subnets,
    [long]$Hosts,
    [string[]]$Vlsm,
    [string[]]$Show,
    [switch]$Full
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Uitvoerlaag: alles gaat door Out-Line, zodat -SaveTo hetzelfde kan wegschrijven.
# ---------------------------------------------------------------------------

$script:Buffer = $null
$script:KanVragen = $true
try { $script:KanVragen = -not [Console]::IsInputRedirected } catch { $script:KanVragen = $false }
$script:PauzeStap = ($Step.IsPresent -and $script:KanVragen -and -not $NoPause)
$script:PauzeOefening = (-not $NoPause -and -not $All -and $script:KanVragen)
$script:Full = $Full.IsPresent
$script:Invul = $false

# Breedte van het scherm (nodig om lange regels netjes af te breken).
function Get-Breedte {
    $b = 0
    try { $b = [int]$Host.UI.RawUI.WindowSize.Width } catch { $b = 0 }
    if ($b -lt 60) { $b = 100 }
    if ($b -gt 120) { $b = 120 }
    return $b
}

# Breekt een lange regel af op spaties; vervolgregels springen 3 spaties extra in.
function Split-Regel {
    param([string]$Tekst, [int]$Breedte)
    if ($Tekst.Length -le $Breedte) { return @($Tekst) }
    $inspring = $Tekst.Length - $Tekst.TrimStart().Length
    $uit = @()
    $rest = $Tekst
    $voorvoegsel = ''
    while (($voorvoegsel + $rest).Length -gt $Breedte) {
        $ruimte = $Breedte - $voorvoegsel.Length
        $cut = $rest.LastIndexOf(' ', [math]::Min($ruimte, $rest.Length - 1))
        if ($cut -le ($inspring + 8)) { $cut = $ruimte }
        $uit += ($voorvoegsel + $rest.Substring(0, $cut).TrimEnd())
        $rest = $rest.Substring($cut).TrimStart()
        $voorvoegsel = (' ' * ($inspring + 3))
    }
    if ($rest.Length -gt 0) { $uit += ($voorvoegsel + $rest) }
    return $uit
}

function Out-Line {
    param(
        [string]$Text = '',
        [string]$Kleur = '',
        [switch]$NoWrap
    )
    $regels = @($Text)
    if (-not $NoWrap) { $regels = @(Split-Regel $Text (Get-Breedte)) }
    foreach ($regel in $regels) {
        if ($null -ne $script:Buffer) { [void]$script:Buffer.AppendLine($regel) }
        if ($Kleur) {
            Write-Host $regel -ForegroundColor $Kleur
        } else {
            Write-Host $regel
        }
    }
}

# Een regel met meerdere kleuren. Elk deel: @(tekst, voorgrond, achtergrond).
function Out-Segs {
    param([object[]]$Delen)
    $plat = ''
    foreach ($d in $Delen) {
        $plat += [string]$d[0]
        $opties = @{ NoNewline = $true; Object = [string]$d[0] }
        if ($d.Count -gt 1 -and $d[1]) { $opties['ForegroundColor'] = $d[1] }
        if ($d.Count -gt 2 -and $d[2]) { $opties['BackgroundColor'] = $d[2] }
        Write-Host @opties
    }
    Write-Host ''
    if ($null -ne $script:Buffer) { [void]$script:Buffer.AppendLine($plat) }
}

function Out-Kop {
    param([string]$Label, [string]$Titel, [string]$Onder = '')
    $script:Invul = $false
    Out-Line ''
    Out-Segs @(@('  '), @((' ' + $Label + ' '), 'Black', 'Yellow'), @(('  ' + $Titel), 'Yellow'))
    if ($Onder) { Out-Line ('  ' + $Onder) 'White' }
    Out-Line ('  ' + ('-' * ((Get-Breedte) - 4))) 'DarkGray' -NoWrap
}

function Get-OpdrachtLabel {
    param([string]$Id)
    if ($Id -eq 'EIGEN') { return 'EIGEN OPDRACHT' }
    return ('OPDRACHT ' + $Id)
}

function Wait-Stap {
    if (-not $script:PauzeStap) { return }
    [void](Read-Host '   [Enter] voor de volgende stap')
}

function Wait-Oefening {
    if (-not $script:PauzeOefening) { return }
    [void](Read-Host "`n   [Enter] om verder te gaan")
}

# ---------------------------------------------------------------------------
# Getallen en adressen
# ---------------------------------------------------------------------------

function Format-Getal {
    param([long]$Waarde)
    $tekst = [string]$Waarde
    $negatief = $false
    if ($tekst.StartsWith('-')) { $negatief = $true; $tekst = $tekst.Substring(1) }
    $uit = ''
    while ($tekst.Length -gt 3) {
        $uit = '.' + $tekst.Substring($tekst.Length - 3) + $uit
        $tekst = $tekst.Substring(0, $tekst.Length - 3)
    }
    if ($negatief) { return '-' + $tekst + $uit }
    return $tekst + $uit
}

function ConvertFrom-IPv4 {
    param([string]$Adres)
    $delen = $Adres.Split('.')
    if ($delen.Count -ne 4) { throw "Ongeldig IPv4-adres: $Adres" }
    [long]$waarde = 0
    foreach ($deel in $delen) {
        $getal = 0
        if (-not [int]::TryParse($deel, [ref]$getal)) { throw "Ongeldig IPv4-adres: $Adres" }
        if ($getal -lt 0 -or $getal -gt 255) { throw "Ongeldig IPv4-adres: $Adres" }
        $waarde = ($waarde * 256) + $getal
    }
    return $waarde
}

function ConvertTo-IPv4 {
    param([long]$Waarde)
    $o1 = [int](($Waarde -shr 24) -band 255)
    $o2 = [int](($Waarde -shr 16) -band 255)
    $o3 = [int](($Waarde -shr 8) -band 255)
    $o4 = [int]($Waarde -band 255)
    return ('{0}.{1}.{2}.{3}' -f $o1, $o2, $o3, $o4)
}

function Get-Blokgrootte {
    param([int]$Prefix)
    return [long][math]::Pow(2, 32 - $Prefix)
}

function Get-Masker {
    param([int]$Prefix)
    [long]$blok = Get-Blokgrootte $Prefix
    [long]$masker = [long]4294967295 - ($blok - 1)
    return (ConvertTo-IPv4 $masker)
}

function Get-MaskerBinair {
    param([int]$Prefix)
    $bits = ('1' * $Prefix) + ('0' * (32 - $Prefix))
    return ('{0}.{1}.{2}.{3}' -f $bits.Substring(0, 8), $bits.Substring(8, 8), $bits.Substring(16, 8), $bits.Substring(24, 8))
}

function Get-BruikbaarAantal {
    param([int]$Prefix)
    [long]$blok = Get-Blokgrootte $Prefix
    if ($Prefix -eq 32) { return [long]1 }
    if ($Prefix -eq 31) { return [long]2 }
    return $blok - 2
}

# Kleinste aantal bits n met 2^n >= Aantal  (aantal subnetten)
function Get-BitsVoorAantal {
    param([long]$Aantal)
    $bits = 0
    [long]$capaciteit = 1
    while ($capaciteit -lt $Aantal) {
        $bits++
        $capaciteit = $capaciteit * 2
    }
    return $bits
}

# Kleinste aantal hostbits h met 2^h - 2 >= Hosts
function Get-HostBitsVoorHosts {
    param([long]$Hosts)
    $h = 1
    [long]$adressen = 2
    while (($adressen - 2) -lt $Hosts) {
        $h++
        $adressen = $adressen * 2
    }
    return $h
}

function New-Subnet {
    param(
        [long]$Netwerk,
        [int]$Prefix,
        [int]$Nr = 0
    )
    [long]$blok = Get-Blokgrootte $Prefix
    [long]$broadcast = $Netwerk + $blok - 1
    if ($Prefix -ge 31) {
        $eerste = $Netwerk
        $laatste = $broadcast
    } else {
        $eerste = $Netwerk + 1
        $laatste = $broadcast - 1
    }
    return [pscustomobject]@{
        Nr        = $Nr
        Netwerk   = $Netwerk
        Prefix    = $Prefix
        Cidr      = ('{0}/{1}' -f (ConvertTo-IPv4 $Netwerk), $Prefix)
        Masker    = (Get-Masker $Prefix)
        Gateway   = (ConvertTo-IPv4 $eerste)
        Eerste    = $eerste
        Laatste   = $laatste
        Broadcast = $broadcast
        Bereik    = ('{0} - {1}' -f (ConvertTo-IPv4 $eerste), (ConvertTo-IPv4 $laatste))
        Bruikbaar = (Get-BruikbaarAantal $Prefix)
    }
}

# ---------------------------------------------------------------------------
# Tabelhulpjes
# ---------------------------------------------------------------------------

function Out-Rij {
    param(
        [string[]]$Cellen,
        [int[]]$Breedtes,
        [string]$Kleur = ''
    )
    $stukken = @()
    for ($i = 0; $i -lt $Cellen.Count; $i++) {
        $stukken += $Cellen[$i].PadRight($Breedtes[$i])
    }
    Out-Line ('  ' + (($stukken -join '  ').TrimEnd())) $Kleur -NoWrap
}

function Out-TabelLijn {
    param([int[]]$Breedtes)
    $totaal = 0
    foreach ($b in $Breedtes) { $totaal += $b }
    $totaal += (($Breedtes.Count - 1) * 2)
    Out-Line ('  ' + ('-' * $totaal)) 'DarkGray' -NoWrap
}

# Subnettabel. Lange tabellen worden ingekort (eerste 3, laatste 2 en de rijen
# die je moet invullen); met -Full zie je alles. Gemarkeerde rijen: '>' + groen.
function Out-SubnetTabel {
    param(
        [object[]]$Subnetten,
        [string]$Titel = '',
        [int[]]$Markeer = @()
    )
    if ($Titel) {
        Out-Line ''
        Out-Line "  $Titel" 'Cyan'
    }
    $prefixen = @($Subnetten | ForEach-Object { $_.Prefix } | Select-Object -Unique)
    $metMasker = ($prefixen.Count -gt 1) -or ((Get-Breedte) -ge 104)
    if ($metMasker) {
        $b = @(5, 18, 15, 33, 15, 7)
        $kop = @('nr', 'netwerk/CIDR', 'subnetmask', 'bruikbaar bereik', 'broadcast', 'hosts')
    } else {
        $b = @(5, 18, 33, 15, 7)
        $kop = @('nr', 'netwerk/CIDR', 'bruikbaar bereik', 'broadcast', 'hosts')
    }
    Out-TabelLijn $b
    Out-Rij $kop $b 'DarkGray'
    Out-TabelLijn $b

    $totaal = @($Subnetten).Count
    $toon = New-Object System.Collections.Generic.List[int]
    if ($script:Full -or $totaal -le 16) {
        for ($i = 1; $i -le $totaal; $i++) { $toon.Add($i) }
    } else {
        $kandidaten = @(1, 2, 3, ($totaal - 1), $totaal) + @($Markeer)
        foreach ($k in ($kandidaten | Sort-Object -Unique)) { if ($k -ge 1 -and $k -le $totaal) { $toon.Add([int]$k) } }
    }
    $vorige = 0
    foreach ($nr in $toon) {
        if ($nr -gt ($vorige + 1)) {
            Out-Line ('  {0,5}  ... {1} overgeslagen ...' -f '', ($nr - $vorige - 1)) 'DarkGray' -NoWrap
        }
        $s = $Subnetten[$nr - 1]
        $vlag = [string]$s.Nr
        $kleur = ''
        if ($Markeer -contains $nr) { $vlag = '> ' + $s.Nr; $kleur = 'Green' }
        if ($metMasker) {
            $cellen = @($vlag, $s.Cidr, $s.Masker, $s.Bereik, (ConvertTo-IPv4 $s.Broadcast), (Format-Getal $s.Bruikbaar))
        } else {
            $cellen = @($vlag, $s.Cidr, $s.Bereik, (ConvertTo-IPv4 $s.Broadcast), (Format-Getal $s.Bruikbaar))
        }
        Out-Rij $cellen $b $kleur
        $vorige = $nr
    }
    Out-TabelLijn $b
    if ($toon.Count -lt $totaal) {
        Out-Line ("  Tabel ingekort: {0} van {1} subnetten getoond. Alles zien: voeg -Full toe." -f $toon.Count, (Format-Getal $totaal)) 'DarkGray'
    }
    if (@($Markeer).Count -gt 0) {
        Out-Line '  > = de subnetten die je moet invullen' 'DarkGray'
    }
}

function Out-Stap {
    param(
        [int]$Nummer,
        [string]$Titel
    )
    Wait-Stap
    $script:Invul = $false
    Out-Line ''
    Out-Segs @(@('  '), @((' STAP {0} ' -f $Nummer), 'Black', 'Cyan'), @(('  ' + $Titel), 'Cyan'))
}

function Out-Uitleg {
    param([string]$Tekst, [string]$Kleur = '')
    Out-Line ("     $Tekst") $Kleur
}

# Label ........ antwoord   (extra uitleg tussen haakjes komt in het grijs erachter,
# of eronder als het niet op de regel past). In het invulblad is het antwoord groen.
function Out-Antwoord {
    param([string]$Label, [string]$Waarde)
    $extra = ''
    if ($Waarde -match '^(\S+)\s{2,}(\(.*\))$') { $Waarde = $Matches[1]; $extra = $Matches[2] }
    $kleur = 'White'
    if ($script:Invul) { $kleur = 'Green' }
    $labelBreedte = 42
    $stuk = $Label + ' '
    if ($stuk.Length -lt $labelBreedte) { $stuk = $stuk + ('.' * ($labelBreedte - $stuk.Length - 1)) + ' ' }
    $delen = @(@('     '), @($stuk, 'Gray'), @($Waarde, $kleur))
    $breedte = Get-Breedte
    $inline = (5 + $stuk.Length + $Waarde.Length + 2 + $extra.Length) -le $breedte
    if ($extra -and $inline) { $delen += , @(('  ' + $extra), 'DarkGray') }
    Out-Segs $delen
    if ($extra -and -not $inline) {
        Out-Line (('       ') + $extra) 'DarkGray' -NoWrap
    }
}

function Out-InvulbladKop {
    param([string]$Titel = 'INVULBLAD')
    $script:Invul = $true
    Out-Line ''
    Out-Segs @(@('  '), @((' ' + $Titel + ' '), 'Black', 'Yellow'), @('  vul dit in op papier', 'DarkGray'))
}

function Out-Machten {
    param([long]$Doel)
    for ($i = 0; $i -le 16; $i++) {
        [long]$waarde = [long][math]::Pow(2, $i)
        $tekst = '     2^{0} = {1,-7}' -f $i, (Format-Getal $waarde)
        if ($waarde -ge $Doel) {
            Out-Line ($tekst + "  >= $Doel   --> GENOEG") 'Green'
            return
        }
        Out-Line ($tekst + "  <  $Doel   --> te weinig") 'DarkGray'
    }
}

function Out-HostMachten {
    param([long]$Hosts)
    for ($h = 1; $h -le 24; $h++) {
        [long]$adressen = [long][math]::Pow(2, $h)
        [long]$bruikbaar = $adressen - 2
        $tekst = '     2^{0} - 2 = {1,-7}' -f $h, (Format-Getal $bruikbaar)
        if ($bruikbaar -ge $Hosts) {
            Out-Line ($tekst + "  >= $Hosts hosts   --> GENOEG") 'Green'
            return
        }
        Out-Line ($tekst + "  <  $Hosts hosts   --> te weinig") 'DarkGray'
    }
}

# ---------------------------------------------------------------------------
# De planners: de rekenkern. Tonen en -Check gebruiken dezelfde code.
# ---------------------------------------------------------------------------

function New-GelijkPlan {
    param(
        [string]$Netwerk,
        [int]$Prefix,
        [long]$Aantal
    )
    [long]$bits = Get-BitsVoorAantal $Aantal
    [long]$blokken = [long][math]::Pow(2, $bits)
    $nieuwPrefix = $Prefix + $bits
    if ($nieuwPrefix -gt 32) { throw "Deze range kan niet in $Aantal subnetten verdeeld worden." }
    [long]$blok = Get-Blokgrootte $nieuwPrefix
    [long]$start = ConvertFrom-IPv4 $Netwerk
    $subnetten = @()
    for ($i = 0; $i -lt $blokken; $i++) {
        $subnetten += (New-Subnet -Netwerk ($start + ($i * $blok)) -Prefix $nieuwPrefix -Nr ($i + 1))
    }
    return [pscustomobject]@{
        Netwerk     = $Netwerk
        Prefix      = $Prefix
        Aantal      = $Aantal
        Bits        = $bits
        Blokken     = $blokken
        NieuwPrefix = $nieuwPrefix
        Blok        = $blok
        Subnetten   = $subnetten
    }
}

function New-HostPlan {
    param(
        [string]$Netwerk,
        [int]$Prefix,
        [long]$Hosts
    )
    [long]$hostBits = Get-HostBitsVoorHosts $Hosts
    $nieuwPrefix = 32 - $hostBits
    if ($nieuwPrefix -lt $Prefix) { throw "Deze range is te klein voor $Hosts hosts per subnet." }
    $geleend = $nieuwPrefix - $Prefix
    [long]$aantal = [long][math]::Pow(2, $geleend)
    [long]$blok = Get-Blokgrootte $nieuwPrefix
    [long]$start = ConvertFrom-IPv4 $Netwerk
    $subnetten = @()
    for ($i = 0; $i -lt $aantal; $i++) {
        $subnetten += (New-Subnet -Netwerk ($start + ($i * $blok)) -Prefix $nieuwPrefix -Nr ($i + 1))
    }
    return [pscustomobject]@{
        Netwerk     = $Netwerk
        Prefix      = $Prefix
        Hosts       = $Hosts
        HostBits    = $hostBits
        Geleend     = $geleend
        Aantal      = $aantal
        NieuwPrefix = $nieuwPrefix
        Blok        = $blok
        Subnetten   = $subnetten
    }
}

function New-VlsmPlan {
    param(
        [string]$Netwerk,
        [int]$Prefix,
        [long[]]$Hosts
    )
    [long]$start = ConvertFrom-IPv4 $Netwerk
    [long]$totaal = Get-Blokgrootte $Prefix
    [long]$einde = $start + $totaal - 1
    [long]$cursor = $start

    # VLSM: eerst het grootste subnet, dan het volgende, zodat kleine blokken
    # in de gaatjes passen. Dit is de standaardregel voor VLSM.
    $gesorteerd = @($Hosts | Sort-Object -Descending)
    $plan = @()
    $nr = 1
    foreach ($h in $gesorteerd) {
        [long]$hostBits = Get-HostBitsVoorHosts $h
        $nieuwPrefix = 32 - $hostBits
        [long]$blok = Get-Blokgrootte $nieuwPrefix
        $uitgelijnd = $false
        if (($cursor % $blok) -ne 0) {
            $cursor = $cursor + ($blok - ($cursor % $blok))
            $uitgelijnd = $true
        }
        [long]$netEinde = $cursor + $blok - 1
        $past = ($netEinde -le $einde)
        $plan += [pscustomobject]@{
            Nr          = $nr
            Gevraagd    = $h
            HostBits    = $hostBits
            Prefix      = $nieuwPrefix
            Blok        = $blok
            Uitgelijnd  = $uitgelijnd
            Past        = $past
            Subnet      = (New-Subnet -Netwerk $cursor -Prefix $nieuwPrefix -Nr $nr)
        }
        $cursor = $netEinde + 1
        $nr++
    }
    return [pscustomobject]@{
        Netwerk   = $Netwerk
        Prefix    = $Prefix
        Start     = $start
        Einde     = $einde
        Totaal    = $totaal
        Plan      = $plan
        VrijVanaf = $cursor
        Vrij      = $einde - $cursor + 1
    }
}

# ---------------------------------------------------------------------------
# De opgaven van het lab
# ---------------------------------------------------------------------------

$script:GelijkVerdelen = @(
    @{ Id = 'A1'; Netwerk = '10.0.1.0';      Prefix = 24; Aantal = 3;  Toon = @(1, 2, 3) },
    @{ Id = 'A2'; Netwerk = '209.68.221.128'; Prefix = 25; Aantal = 23; Toon = @(1, 2, 5) },
    @{ Id = 'A3'; Netwerk = '184.2.146.128';  Prefix = 25; Aantal = 11; Toon = @(1, 2, 10, 11) },
    @{ Id = 'A4'; Netwerk = '214.42.37.192';  Prefix = 27; Aantal = 3;  Toon = @(1, 2, 3) },
    @{ Id = 'A5'; Netwerk = '160.155.148.0';  Prefix = 24; Aantal = 21; Toon = @(1, 2, 11) },
    @{ Id = 'A6'; Netwerk = '111.190.164.64'; Prefix = 27; Aantal = 7;  Toon = @(1, 2, 3, 4) }
)

$script:HostBased = @(
    @{ Id = 'B1'; Netwerk = '93.54.240.0';    Prefix = 24; Hosts = 15;  Toon = @(1, 2, 5) },
    @{ Id = 'B2'; Netwerk = '169.174.246.0';  Prefix = 24; Hosts = 30;  Toon = @(1, 2, 6) },
    @{ Id = 'B3'; Netwerk = '13.95.240.0';    Prefix = 20; Hosts = 213; Toon = @(1, 2, 7) },
    @{ Id = 'B4'; Netwerk = '32.38.231.0';    Prefix = 24; Hosts = 12;  Toon = @(1, 2, 11) }
)

$script:VlsmOefeningen = @(
    @{ Id = 'C1'; Netwerk = '193.168.50.0'; Prefix = 24; Hosts = @(100, 50, 30, 10, 10) },
    @{ Id = 'C2'; Netwerk = '172.10.0.0';   Prefix = 18; Hosts = @(5000, 2000, 2000) }
)

$script:Cases = @(
    @{
        Id       = 'D1'
        Groep    = 'Groep 1'
        Titel    = 'IT-bedrijf'
        Supernet = '10.11.0.0/16'
        Situatie = @(
            'Er is een DMZ met 2 servers.',
            'Een server LAN.',
            'Een workstation LAN.',
            'Een wireless LAN.',
            'Een wireless netwerk voor mobiele toestellen.'
        )
        Segmenten = @(
            @{ Vlan = 10; Naam = 'DMZ'; Toestellen = 2; Prefix = 28; Motivatie = '2 servers: /28 geeft 14 bruikbare adressen. Klein houden, want de DMZ staat het dichtst bij het internet.' },
            @{ Vlan = 20; Naam = 'Server-LAN'; Toestellen = 10; Prefix = 27; Motivatie = '10 interne servers (DC, fileserver, backup, monitoring ...): /27 geeft 30 adressen, genoeg marge.' },
            @{ Vlan = 30; Naam = 'Workstation-LAN'; Toestellen = 50; Prefix = 26; Motivatie = '50 werkplekken: /26 geeft 62 adressen. Een /27 (30) is te klein, een /25 (126) verspilt te veel.' },
            @{ Vlan = 40; Naam = 'Wireless medewerkers'; Toestellen = 80; Prefix = 25; Motivatie = '80 clients (laptop, gsm, tablet per medewerker): /25 geeft 126 adressen, ruim genoeg voor groei.' },
            @{ Vlan = 50; Naam = 'Wireless mobiel/gasten'; Toestellen = 120; Prefix = 25; Motivatie = '120 mobiele toestellen: /25 geeft 126 adressen. Apart VLAN, zodat gasten het interne net niet zien.' }
        )
        Extra = @(
            'De DMZ staat in een apart VLAN achter de firewall; alleen de poorten die nodig zijn gaan open.',
            'Gasten en mobiele toestellen krijgen geen route naar het server-LAN: client isolation.',
            'De /16 hierboven laat nog 65.000 adressen vrij: plaats voor nieuwe sites, VoIP of camera''s.'
        )
    },
    @{
        Id       = 'D2'
        Groep    = 'Groep 2'
        Titel    = 'School'
        Supernet = '10.12.0.0/16'
        Situatie = @(
            'Er is een onthaal met 1 PC.',
            'Er is een secretariaat met 2 PC''s en een printer.',
            'Er zijn drie aparte lokalen met computers.',
            'Houd ook rekening met de modernisering: smartboards.'
        )
        Segmenten = @(
            @{ Vlan = 10; Naam = 'Onthaal'; Toestellen = 4; Prefix = 28; Motivatie = '1 PC plus bezoekersbalie en groei: /28 geeft 14 adressen.' },
            @{ Vlan = 20; Naam = 'Secretariaat'; Toestellen = 5; Prefix = 28; Motivatie = '2 PC''s + printer + 2 reserve: /28 geeft 14 adressen. Printers horen bij het secretariaat, niet bij de leerlingen.' },
            @{ Vlan = 30; Naam = 'Lokaal A'; Toestellen = 26; Prefix = 27; Motivatie = '25 leerling-PC''s + leerkracht-PC: /27 geeft 30 adressen.' },
            @{ Vlan = 31; Naam = 'Lokaal B'; Toestellen = 26; Prefix = 27; Motivatie = 'Idem lokaal A: /27. Elk lokaal een eigen VLAN, zodat je apart kan filteren en tellen.' },
            @{ Vlan = 32; Naam = 'Lokaal C'; Toestellen = 26; Prefix = 27; Motivatie = 'Idem lokaal A: /27. Groei met 4 toestellen blijft mogelijk.' },
            @{ Vlan = 40; Naam = 'Smartboards / IoT'; Toestellen = 20; Prefix = 26; Motivatie = '15 smartboards nu + groei: /26 geeft 62 adressen. Apart VLAN: smartboards hoeven niet bij de leerling-PC''s te staan.' }
        )
        Extra = @(
            'De modernisering zit in VLAN 40: nieuwe smartboards, beamers en displays krijgen daar een DHCP-reservatie.',
            'Leerlingen-LAN''s worden meestal via VLAN + ACL gescheiden van het secretariaat (cijfers!).',
            'Er blijft een volledig /16 vrij voor een tweede gebouw of een draadloos net voor leerlingen.'
        )
    },
    @{
        Id       = 'D3'
        Groep    = 'Groep 3'
        Titel    = 'Bedrijf met twee verdiepen'
        Supernet = '10.13.0.0/16'
        Situatie = @(
            'Er is een receptie met 2 PC''s.',
            'Er is een wireless voor bezoekers.',
            'Er is een wireless voor interne medewerkers.',
            'Er is een LAN voor de medewerkers op de begane grond.',
            'Er is een LAN voor de medewerkers op het 1e verdiep.',
            'Er is een conference room met projector, smartboard en 2 smartscreens.'
        )
        Segmenten = @(
            @{ Vlan = 10; Naam = 'Receptie'; Toestellen = 4; Prefix = 28; Motivatie = '2 PC''s + marge: /28 geeft 14 adressen.' },
            @{ Vlan = 20; Naam = 'Wireless bezoekers'; Toestellen = 100; Prefix = 25; Motivatie = '100 gasten: /25 geeft 126 adressen, met captive portal en geen toegang tot het interne net.' },
            @{ Vlan = 30; Naam = 'Wireless medewerkers'; Toestellen = 80; Prefix = 25; Motivatie = '80 clients: /25 geeft 126 adressen. Apart van het bedrade LAN, zodat je apart kan beveiligen.' },
            @{ Vlan = 40; Naam = 'LAN begane grond'; Toestellen = 40; Prefix = 26; Motivatie = '40 bedrade werkplekken: /26 geeft 62 adressen.' },
            @{ Vlan = 50; Naam = 'LAN 1e verdiep'; Toestellen = 40; Prefix = 26; Motivatie = '40 bedrade werkplekken: /26 geeft 62 adressen. Per verdiep een eigen VLAN = per verdiep een eigen storingsdomein.' },
            @{ Vlan = 60; Naam = 'Conference room'; Toestellen = 12; Prefix = 27; Motivatie = 'Projector, smartboard, 2 smartscreens, gastenlaptops: /27 geeft 30 adressen.' }
        )
        Extra = @(
            'Bezoekers en medewerkers zitten altijd in aparte VLAN''s: dezelfde SSID voor iedereen is een slecht ontwerp.',
            'De conference room is een eigen VLAN zodat presentaties nooit het productienet kunnen raken.'
        )
    },
    @{
        Id       = 'D4'
        Groep    = 'Groep 4'
        Titel    = 'Hotel'
        Supernet = '10.14.0.0/16'
        Situatie = @(
            'Er is een receptie met 1 PC en 1 printer; het management zit op hetzelfde LAN.',
            'Er zijn 5 verdiepen en elk verdiep heeft 30 kamers.',
            'Elke kamer heeft een smart TV en een IP-telefoon.',
            'Er zijn plannen voor smart devices in het restaurant, de 2 vergaderzalen en de polyvalente zaal.'
        )
        Segmenten = @(
            @{ Vlan = 10; Naam = 'Receptie + management'; Toestellen = 8; Prefix = 28; Motivatie = '1 PC + printer + 2 managementwerkplekken + marge: /28 geeft 14 adressen.' },
            @{ Vlan = 20; Naam = 'Kamers verdiep 1'; Toestellen = 60; Prefix = 25; Motivatie = '30 kamers x (TV + IP-telefoon) = 60 toestellen: /25 geeft 126 adressen, plaats voor AP''s en groei.' },
            @{ Vlan = 21; Naam = 'Kamers verdiep 2'; Toestellen = 60; Prefix = 25; Motivatie = 'Idem verdiep 1: /25. Per verdiep een eigen VLAN = een storing op verdiep 3 legt verdiep 4 niet plat.' },
            @{ Vlan = 22; Naam = 'Kamers verdiep 3'; Toestellen = 60; Prefix = 25; Motivatie = 'Idem verdiep 1: /25.' },
            @{ Vlan = 23; Naam = 'Kamers verdiep 4'; Toestellen = 60; Prefix = 25; Motivatie = 'Idem verdiep 1: /25.' },
            @{ Vlan = 24; Naam = 'Kamers verdiep 5'; Toestellen = 60; Prefix = 25; Motivatie = 'Idem verdiep 1: /25.' },
            @{ Vlan = 60; Naam = 'Restaurant'; Toestellen = 20; Prefix = 27; Motivatie = '20 smart devices (kassa, displays, sensoren): /27 geeft 30 adressen.' },
            @{ Vlan = 61; Naam = 'Vergaderzaal 1'; Toestellen = 15; Prefix = 27; Motivatie = '15 devices: /27 geeft 30 adressen.' },
            @{ Vlan = 62; Naam = 'Vergaderzaal 2'; Toestellen = 15; Prefix = 27; Motivatie = '15 devices: /27 geeft 30 adressen.' },
            @{ Vlan = 63; Naam = 'Polyvalente zaal'; Toestellen = 80; Prefix = 25; Motivatie = '80 devices bij events: /25 geeft 126 adressen.' }
        )
        Extra = @(
            'Gasten die met hun eigen gsm op de kamer willen, horen op een apart gasten-VLAN met client isolation; TV en IP-telefoon blijven dan in het kamer-VLAN.',
            'In een echt hotelnetwerk zet je VoIP vaak nog apart (eigen VLAN met QoS), maar voor deze oefening mag telefonie bij het kamer-VLAN.',
            'De nummering 10.14.<vlan>.0 maakt het netwerk leesbaar: het derde octet is het VLAN-nummer.'
        )
    }
)

# ---------------------------------------------------------------------------
# Weergave: theorie
# ---------------------------------------------------------------------------

function Show-Theorie {
    Out-Line ''
    Out-Line ('=' * 78) 'DarkGray'
    Out-Line '  THEORIE - de methode in 6 stappen' 'Yellow'
    Out-Line ('=' * 78) 'DarkGray'

    Out-Line ''
    Out-Line '  1. Lees het masker.' 'Cyan'
    Out-Uitleg '/24 = 24 netwerkbits + 8 hostbits. Met 8 hostbits heb je 2^8 = 256 adressen.'
    Out-Uitleg 'Bruikbaar per subnet = 2^hostbits - 2 (netwerkadres en broadcast mag je niet gebruiken).'

    Out-Line ''
    Out-Line '  2. Bepaal wat je moet berekenen.' 'Cyan'
    Out-Uitleg 'Gelijk verdelen  -> aantal subnetten is gegeven: kleinste n met 2^n >= aantal.'
    Out-Uitleg 'Host based       -> aantal hosts per subnet is gegeven: kleinste h met 2^h - 2 >= hosts.'
    Out-Uitleg 'VLSM             -> meerdere groottes: eerst het grootste subnet, dan kleiner.'

    Out-Line ''
    Out-Line '  3. Nieuw prefix (CIDR).' 'Cyan'
    Out-Uitleg 'Gelijk verdelen: nieuw prefix = oud prefix + n  (n = geleende hostbits).'
    Out-Uitleg 'Host based:      nieuw prefix = 32 - h        (h = hostbits die je nodig hebt).'
    Out-Uitleg 'De bits die je "leent" gaan van hostbits naar netwerkbits.'

    Out-Line ''
    Out-Line '  4. Nieuw subnetmask in decimalen.' 'Cyan'
    Out-Uitleg 'Schrijf prefix enen, dan nullen, en reken per octet om. Sneller:'
    Out-Uitleg 'het octet waarin je knipt wordt 256 - blokgrootte.'

    Out-Line ''
    Out-Line '  5. Stapgrootte (blokgrootte).' 'Cyan'
    Out-Uitleg 'blok = 2^(32 - prefix). De subnetadressen verspringen met die stap.'
    Out-Uitleg 'Voorbeeld: /26 -> blok 64 -> 0, 64, 128, 192.'

    Out-Line ''
    Out-Line '  6. Subnetten opsommen.' 'Cyan'
    Out-Uitleg 'Start bij het netwerkadres van de range en tel per stap. Bij VLSM begin je'
    Out-Uitleg 'telkens bij het eerste vrije adres na het vorige subnet (en lijnt uit op de blokgrens).'
    Out-Uitleg 'Gateway: spreek een vaste regel af, hier altijd het eerste bruikbare adres (.1).'

    Out-Line ''
    Out-Line '  Machten van 2 (uit je hoofd kennen)' 'Cyan'
    Out-Line ('     ' + (0..12 | ForEach-Object { '2^{0}={1}' -f $_, [long][math]::Pow(2, $_) }) -join '  ')
    Out-Line ''
    Out-Line '  Maskertabel' 'Cyan'
    Out-Line '     prefix  masker            blok    hosts   binair (laatste octet)'
    $maskers = @(
        @(24, '255.255.255.0', 256, 254, '00000000'),
        @(25, '255.255.255.128', 128, 126, '10000000'),
        @(26, '255.255.255.192', 64, 62, '11000000'),
        @(27, '255.255.255.224', 32, 30, '11100000'),
        @(28, '255.255.255.240', 16, 14, '11110000'),
        @(29, '255.255.255.248', 8, 6, '11111000'),
        @(30, '255.255.255.252', 4, 2, '11111100'),
        @(31, '255.255.255.254', 2, 2, '11111110'),
        @(32, '255.255.255.255', 1, 1, '11111111')
    )
    foreach ($m in $maskers) {
        Out-Line ('     /{0,-6} {1,-18} {2,-7} {3,-7} {4}' -f $m[0], $m[1], $m[2], $m[3], $m[4])
    }

    Out-Line ''
    Out-Line '  Private adresruimte (voor de cases)' 'Cyan'
    Out-Line '     10.0.0.0/8        10.0.0.0    - 10.255.255.255'
    Out-Line '     172.16.0.0/12     172.16.0.0  - 172.31.255.255'
    Out-Line '     192.168.0.0/16    192.168.0.0 - 192.168.255.255'
    Out-Line ''
    Out-Line '  Alles staat of valt bij de vraag: hoeveel bits heb ik nodig?' 'Yellow'
    Out-Line '  Subnetten: 2^n >= aantal.   Hosts: 2^h - 2 >= aantal.' 'Yellow'
    Out-Line ''
}

# ---------------------------------------------------------------------------
# Weergave: gelijk verdelen
# ---------------------------------------------------------------------------

function Show-GelijkVerdelen {
    param($Ex)

    $plan = New-GelijkPlan -Netwerk $Ex.Netwerk -Prefix $Ex.Prefix -Aantal $Ex.Aantal
    [long]$huidigBlok = Get-Blokgrootte $Ex.Prefix
    [long]$huidigBruikbaar = Get-BruikbaarAantal $Ex.Prefix

    Out-Kop (Get-OpdrachtLabel $Ex.Id) 'GELIJK VERDELEN' ("Verdeel {0}/{1} in {2} subnetten." -f $Ex.Netwerk, $Ex.Prefix, (Format-Getal $Ex.Aantal))

    Out-Stap 1 'Wat heb je?'
    Out-Antwoord 'Netwerk' ('{0}/{1}' -f $Ex.Netwerk, $Ex.Prefix)
    Out-Antwoord 'Subnetmask in decimalen' ((Get-Masker $Ex.Prefix) + ('  (binair {0})' -f (Get-MaskerBinair $Ex.Prefix)))
    Out-Uitleg ("prefix /{0} = {0} netwerkbits + {1} hostbits" -f $Ex.Prefix, (32 - $Ex.Prefix))
    Out-Uitleg ("adressen in de range: 2^{0} = {1}" -f (32 - $Ex.Prefix), (Format-Getal $huidigBlok))
    Out-Uitleg ("bruikbaar in de range: {0} - 2 = {1}" -f (Format-Getal $huidigBlok), (Format-Getal $huidigBruikbaar))

    Out-Stap 2 'Hoeveel host-bits moet je lenen?'
    Out-Uitleg ("Je hebt {0} subnetten nodig. Zoek de kleinste macht van 2 die >= {0} is:" -f (Format-Getal $Ex.Aantal))
    Out-Machten $Ex.Aantal
    Out-Uitleg ''
    Out-Uitleg ("Je leent dus {0} hostbits: met {0} bits maak je 2^{0} = {1} blokken." -f $plan.Bits, (Format-Getal $plan.Blokken)) 'Green'
    Out-Uitleg ("Je gebruikt er {0}; {1} blok(ken) blijft/blijven ongebruikt (reserve)." -f (Format-Getal $Ex.Aantal), (Format-Getal ($plan.Blokken - $Ex.Aantal)))
    if ($plan.Bits -ge 1) {
        $vorige = [long][math]::Pow(2, $plan.Bits - 1)
        Out-Uitleg ("Met {0} bits had je maar {1} blokken gehad: te weinig. {2} bits is het minimum." -f ($plan.Bits - 1), (Format-Getal $vorige), $plan.Bits)
    }

    Out-Stap 3 'Wat wordt je CIDR?'
    Out-Uitleg ("nieuw prefix = oud prefix + geleende bits = {0} + {1} = /{2}" -f $Ex.Prefix, $plan.Bits, $plan.NieuwPrefix) 'White'
    Out-Antwoord 'CIDR van de subnetten' ('/{0}' -f $plan.NieuwPrefix)

    Out-Stap 4 'Nieuw subnetmask in decimalen'
    Out-Uitleg ("/{0}: {0} enen en {1} nullen" -f $plan.NieuwPrefix, (32 - $plan.NieuwPrefix))
    Out-Uitleg ('binair:   ' + (Get-MaskerBinair $plan.NieuwPrefix))
    Out-Line ('     decimaal: ' + (Get-Masker $plan.NieuwPrefix)) 'White'
    Out-Uitleg ("hostbits die overblijven: {0} -> 2^{0} - 2 = {1} bruikbare adressen per subnet" -f (32 - $plan.NieuwPrefix), (Format-Getal (Get-BruikbaarAantal $plan.NieuwPrefix)))
    Out-Antwoord 'nieuwe subnetmask' ('{0}  (/{1})' -f (Get-Masker $plan.NieuwPrefix), $plan.NieuwPrefix)

    Out-Stap 5 'Stapgrootte (blokgrootte)'
    Out-Uitleg ("blok = 2^(32 - {0}) = 2^{1} = {2} adressen per subnet" -f $plan.NieuwPrefix, (32 - $plan.NieuwPrefix), (Format-Getal $plan.Blok))
    $startOctet = ((ConvertTo-IPv4 (ConvertFrom-IPv4 $Ex.Netwerk)).Split('.'))
    $stappen = @()
    foreach ($s in $plan.Subnetten) { $stappen += (ConvertTo-IPv4 $s.Netwerk).Split('.')[3] }
    Out-Uitleg ("de subnetadressen verspringen met {0} in het laatste octet:" -f $plan.Blok)
    Out-Line ('     ' + ($stappen -join ', '))

    Out-Stap 6 'De subnetten'
    Out-SubnetTabel -Subnetten $plan.Subnetten -Titel 'Alle blokken in deze range' -Markeer $Ex.Toon

    Out-Stap 7 'Controle en invulblad'
    $gebruikt = $plan.Blokken * $plan.Blok
    Out-Uitleg ("{0} blokken x {1} adressen = {2} adressen, samen de volledige /{3}." -f (Format-Getal $plan.Blokken), (Format-Getal $plan.Blok), (Format-Getal $gebruikt), $Ex.Prefix)
    Out-Uitleg ("Je vult {0} subnetten in; de rest van de blokken laat je leeg of noteer je als reserve." -f (Format-Getal $Ex.Aantal))
    Out-Uitleg 'Controleer altijd: elk volgend subnet = vorig netwerkadres + blokgrootte.'

    Out-InvulbladKop
    Out-Antwoord 'subnetmask in decimalen' (Get-Masker $Ex.Prefix)
    Out-Antwoord 'Hoeveel host-bits moet je lenen?' ([string]$plan.Bits)
    Out-Antwoord 'Wat wordt je CIDR voor deze subnetten?' ('/{0}' -f $plan.NieuwPrefix)
    Out-Antwoord 'nieuwe subnetmask' ('{0}  (/{1})' -f (Get-Masker $plan.NieuwPrefix), $plan.NieuwPrefix)
    foreach ($nr in $Ex.Toon) {
        if ($nr -le $plan.Subnetten.Count) {
            $s = $plan.Subnetten[$nr - 1]
            Out-Antwoord ("subnet{0}" -f $nr) ('{0}   (bruikbaar {1}, broadcast {2})' -f $s.Cidr, $s.Bereik, (ConvertTo-IPv4 $s.Broadcast))
        }
    }
    Out-Line ''
}

# ---------------------------------------------------------------------------
# Weergave: host based verdelen
# ---------------------------------------------------------------------------

function Show-HostBased {
    param($Ex)

    $plan = New-HostPlan -Netwerk $Ex.Netwerk -Prefix $Ex.Prefix -Hosts $Ex.Hosts
    [long]$huidigBlok = Get-Blokgrootte $Ex.Prefix

    Out-Kop (Get-OpdrachtLabel $Ex.Id) 'HOST BASED VERDELEN' ("Verdeel {0}/{1} zodat elk subnet {2} hosts bevat." -f $Ex.Netwerk, $Ex.Prefix, (Format-Getal $Ex.Hosts))

    Out-Stap 1 'Wat heb je?'
    Out-Antwoord 'Netwerk' ('{0}/{1}' -f $Ex.Netwerk, $Ex.Prefix)
    Out-Antwoord 'Subnetmask in decimalen' ((Get-Masker $Ex.Prefix) + ('  (binair {0})' -f (Get-MaskerBinair $Ex.Prefix)))
    Out-Uitleg ("prefix /{0} = {0} netwerkbits + {1} hostbits" -f $Ex.Prefix, (32 - $Ex.Prefix))
    Out-Uitleg ("adressen in de range: {0}, bruikbaar: {1}" -f (Format-Getal $huidigBlok), (Format-Getal (Get-BruikbaarAantal $Ex.Prefix)))

    Out-Stap 2 'Hoeveel hostbits heb je nodig (en hoeveel moet je dus lenen)?'
    Out-Uitleg ("Elk subnet moet {0} hosts aankunnen. Zoek de kleinste h met 2^h - 2 >= {0}:" -f (Format-Getal $Ex.Hosts))
    Out-HostMachten $Ex.Hosts
    Out-Uitleg ''
    Out-Uitleg ("Je hebt {0} hostbits nodig: 2^{0} - 2 = {1} >= {2}." -f $plan.HostBits, (Format-Getal ((Get-BruikbaarAantal $plan.NieuwPrefix))), (Format-Getal $Ex.Hosts)) 'Green'
    Out-Uitleg ("Je leent {0} van de {1} hostbits die je had: de rest ({0}) blijven hostbits." -f $plan.Geleend, (32 - $Ex.Prefix))
    Out-Uitleg ("Daarmee maak je 2^{0} = {1} subnetten in deze range." -f $plan.Geleend, (Format-Getal $plan.Aantal))

    Out-Stap 3 'Wat wordt je CIDR?'
    Out-Uitleg ("nieuw prefix = 32 - hostbits = 32 - {0} = /{1}" -f $plan.HostBits, $plan.NieuwPrefix) 'White'
    Out-Antwoord 'CIDR van de subnetten' ('/{0}' -f $plan.NieuwPrefix)

    Out-Stap 4 'Nieuw subnetmask in decimalen'
    Out-Uitleg ('binair:   ' + (Get-MaskerBinair $plan.NieuwPrefix))
    Out-Line ('     decimaal: ' + (Get-Masker $plan.NieuwPrefix)) 'White'
    Out-Antwoord 'nieuwe subnetmask' ('{0}  (/{1})' -f (Get-Masker $plan.NieuwPrefix), $plan.NieuwPrefix)

    Out-Stap 5 'Stapgrootte (blokgrootte)'
    Out-Uitleg ("blok = 2^{0} = {1} adressen per subnet" -f $plan.HostBits, (Format-Getal $plan.Blok))
    Out-Uitleg ("controle: {0} hosts gevraagd, {1} bruikbaar -> past." -f (Format-Getal $Ex.Hosts), (Format-Getal (Get-BruikbaarAantal $plan.NieuwPrefix)))

    Out-Stap 6 'De subnetten'
    Out-SubnetTabel -Subnetten $plan.Subnetten -Titel ("Alle {0} subnetten in deze range" -f (Format-Getal $plan.Aantal)) -Markeer $Ex.Toon

    Out-Stap 7 'Controle en invulblad'
    $laatste = $plan.Subnetten[$plan.Subnetten.Count - 1]
    [long]$gebruikt = $plan.Aantal * $plan.Blok
    Out-Uitleg ("laatste subnet {0}: {1} tot {2} -> valt binnen /{3}." -f $plan.Aantal, (ConvertTo-IPv4 $laatste.Netwerk), (ConvertTo-IPv4 $laatste.Broadcast), $Ex.Prefix)
    Out-Uitleg ("gebruikt: {0} van {1} adressen; {2} blijft vrij." -f (Format-Getal $gebruikt), (Format-Getal $huidigBlok), (Format-Getal ($huidigBlok - $gebruikt)))

    Out-InvulbladKop
    Out-Antwoord 'subnetmask in decimalen' (Get-Masker $Ex.Prefix)
    Out-Antwoord 'Hoeveel host-bits moet je lenen?' ([string]$plan.Geleend)
    Out-Antwoord 'Wat wordt je CIDR voor deze subnetten?' ('/{0}' -f $plan.NieuwPrefix)
    Out-Antwoord 'nieuwe subnetmask' ('{0}  (/{1})' -f (Get-Masker $plan.NieuwPrefix), $plan.NieuwPrefix)
    foreach ($nr in $Ex.Toon) {
        if ($nr -le $plan.Subnetten.Count) {
            $s = $plan.Subnetten[$nr - 1]
            Out-Antwoord ("subnet{0}" -f $nr) ('{0}   (bruikbaar {1})' -f $s.Cidr, $s.Bereik)
        }
    }
    Out-Line ''
}

# ---------------------------------------------------------------------------
# Weergave: VLSM
# ---------------------------------------------------------------------------

function Show-Vlsm {
    param($Ex)

    $plan = New-VlsmPlan -Netwerk $Ex.Netwerk -Prefix $Ex.Prefix -Hosts $Ex.Hosts
    [long]$huidigBlok = Get-Blokgrootte $Ex.Prefix
    $gevraagd = ($Ex.Hosts | ForEach-Object { Format-Getal $_ }) -join ', '

    Out-Kop (Get-OpdrachtLabel $Ex.Id) 'VLSM' ("Verdeel {0}/{1} in subnetten van {2} hosts." -f $Ex.Netwerk, $Ex.Prefix, $gevraagd)

    Out-Stap 1 'Wat heb je en wat is de regel bij VLSM?'
    Out-Antwoord 'Netwerk' ('{0}/{1}' -f $Ex.Netwerk, $Ex.Prefix)
    Out-Antwoord 'subnetmask in decimalen' ((Get-Masker $Ex.Prefix) + ('  (/ {0})' -f $Ex.Prefix))
    Out-Uitleg ("adressen in de range: 2^{0} = {1}; bruikbaar: {2}" -f (32 - $Ex.Prefix), (Format-Getal $huidigBlok), (Format-Getal (Get-BruikbaarAantal $Ex.Prefix)))
    Out-Uitleg 'Bij VLSM krijgt elk subnet precies de grootte die het nodig heeft.'
    Out-Uitleg 'Regel: verdeel van GROOT naar KLEIN, anders passen de kleine blokken niet meer.'

    Out-Stap 2 'Bereken per gevraagde grootte de hostbits, het CIDR en het masker'
    $b = @(10, 10, 12, 8, 18, 10)
    Out-TabelLijn $b
    Out-Rij @('gevraagd', 'hostbits', '2^h - 2', 'CIDR', 'subnetmask', 'blok') $b 'DarkGray'
    Out-TabelLijn $b
    foreach ($rij in $plan.Plan) {
        if (-not $rij.Past) { continue }
        Out-Rij @(
            ((Format-Getal $rij.Gevraagd) + ' hosts'),
            [string]$rij.HostBits,
            (Format-Getal (Get-BruikbaarAantal $rij.Prefix)),
            ('/' + $rij.Prefix),
            $rij.Subnet.Masker,
            (Format-Getal $rij.Blok)
        ) $b
    }
    Out-TabelLijn $b
    Out-Uitleg 'De eerste rij die genoeg hosts geeft, is je antwoord: 2^h - 2 moet >= het gevraagde zijn.'

    Out-Stap 3 'Verdeel de adressen: van groot naar klein'
    foreach ($rij in $plan.Plan) {
        if (-not $rij.Past) {
            Out-Line ("     subnet{0}: PAST NIET MEER in {1}/{2}" -f $rij.Nr, $Ex.Netwerk, $Ex.Prefix) 'Red'
            continue
        }
        $vorigeEinde = $rij.Subnet.Netwerk - 1
        Out-Line ("     subnet{0}: {1} hosts -> /{2} -> blok {3}" -f $rij.Nr, (Format-Getal $rij.Gevraagd), $rij.Prefix, (Format-Getal $rij.Blok)) 'White'
        if ($rij.Nr -eq 1) {
            Out-Uitleg ("begin bij het netwerkadres {0}" -f $Ex.Netwerk)
        } else {
            if ($rij.Uitgelijnd) {
                Out-Uitleg ("vrij vanaf {0}; dat is geen veelvoud van {1}, dus schuif op naar de blokgrens {2}" -f (ConvertTo-IPv4 $vorigeEinde + 1), (Format-Getal $rij.Blok), (ConvertTo-IPv4 $rij.Subnet.Netwerk))
            } else {
                Out-Uitleg ("vrij vanaf {0}; dat is al een veelvoud van {1}" -f (ConvertTo-IPv4 $rij.Subnet.Netwerk), (Format-Getal $rij.Blok))
            }
        }
        Out-Uitleg ("-> {0}   (bruikbaar {1}, broadcast {2})" -f $rij.Subnet.Cidr, $rij.Subnet.Bereik, (ConvertTo-IPv4 $rij.Subnet.Broadcast)) 'Green'
    }

    Out-Stap 4 'De subnetten naast elkaar'
    $subnetten = @()
    foreach ($rij in $plan.Plan) { if ($rij.Past) { $subnetten += $rij.Subnet } }
    Out-SubnetTabel -Subnetten $subnetten -Titel 'Gebruikte subnetten'

    Out-Stap 5 'Controle: past alles en wat blijft over?'
    [long]$gebruikt = 0
    foreach ($rij in $plan.Plan) { if ($rij.Past) { $gebruikt += $rij.Blok } }
    Out-Uitleg ("gebruikt: {0} adressen van {1} in de /{2}." -f (Format-Getal $gebruikt), (Format-Getal $plan.Totaal), $Ex.Prefix)
    if ($plan.Vrij -gt 0) {
        Out-Uitleg ("vrij: {0} adressen, vanaf {1} tot {2}." -f (Format-Getal $plan.Vrij), (ConvertTo-IPv4 $plan.VrijVanaf), (ConvertTo-IPv4 $plan.Einde)) 'Green'
        Out-Uitleg 'Die ruimte hou je vrij voor een volgend subnet of groei.'
    } else {
        Out-Uitleg 'De range is volledig opgebruikt.' 'Green'
    }
    Out-Uitleg 'Gateway per subnet: het eerste bruikbare adres (conventie in dit lab).'

    Out-Stap 6 'Invulblad'
    Out-InvulbladKop
    Out-Antwoord 'subnetmask in decimalen' ((Get-Masker $Ex.Prefix) + ('   (de originele /{0})' -f $Ex.Prefix))
    foreach ($rij in $plan.Plan) {
        if (-not $rij.Past) { continue }
        Out-Antwoord ("subnet{0} + CIDR" -f $rij.Nr) $rij.Subnet.Cidr
        Out-Antwoord ("subnet{0} subnetmask" -f $rij.Nr) $rij.Subnet.Masker
    }
    Out-Line ''
}

# ---------------------------------------------------------------------------
# Weergave: cases
# ---------------------------------------------------------------------------

function Show-Case {
    param($Case)

    $delen = $Case.Supernet.Split('/')
    $basis = $delen[0].Split('.')
    $prefix = [int]$delen[1]

    Out-Kop ('CASE ' + $Case.Id) ('{0} ({1})' -f $Case.Titel, $Case.Groep) ('Supernet: {0}   (privaat, /{1})' -f $Case.Supernet, $prefix)

    Out-Stap 1 'De omgeving'
    foreach ($regel in $Case.Situatie) { Out-Uitleg ('- ' + $regel) }

    Out-Stap 2 'Ontwerpregels'
    Out-Uitleg '1. Alles in private adresruimte: 10.0.0.0/8, 172.16.0.0/12 of 192.168.0.0/16.'
    Out-Uitleg '2. Elk segment (VLAN) krijgt zijn eigen subnet, met een leesbaar nummer.'
    Out-Uitleg '3. Kies het masker op het aantal toestellen: 2^h - 2 >= toestellen, plus marge.'
    Out-Uitleg '4. Geef elk subnet een gateway: het eerste bruikbare adres (.1).'
    Out-Uitleg ("5. Hier: {0} = 10.{1}.<vlan>.0, dus het derde octet is het VLAN-nummer." -f $Case.Supernet, $basis[1])

    Out-Stap 3 'Het IP-design'
    $b = @(5, 28, 10, 20, 16, 15, 7, 7)
    Out-TabelLijn $b
    Out-Rij @('VLAN', 'segment', 'toestellen', 'netwerk/CIDR', 'subnetmask', 'gateway', 'hosts', 'marge') $b 'DarkGray'
    Out-TabelLijn $b
    $ontwerp = @()
    [long]$totaalGebruikt = 0
    foreach ($seg in $Case.Segmenten) {
        $netwerkTekst = '{0}.{1}.{2}.0' -f $basis[0], $basis[1], $seg.Vlan
        $subnet = New-Subnet -Netwerk (ConvertFrom-IPv4 $netwerkTekst) -Prefix $seg.Prefix
        $marge = $subnet.Bruikbaar - $seg.Toestellen
        $ontwerp += [pscustomobject]@{ Segment = $seg; Subnet = $subnet; Marge = $marge }
        $totaalGebruikt += $subnet.Bruikbaar
        Out-Rij @(
            ('VLAN ' + $seg.Vlan),
            $seg.Naam,
            (Format-Getal $seg.Toestellen),
            $subnet.Cidr,
            $subnet.Masker,
            $subnet.Gateway,
            (Format-Getal $subnet.Bruikbaar),
            (Format-Getal $marge)
        ) $b
    }
    Out-TabelLijn $b
    Out-Uitleg ("samen {0} bruikbare adressen in gebruik; de rest van de /{1} blijft vrij." -f (Format-Getal $totaalGebruikt), $prefix)

    Out-Stap 4 'Motivering per subnet'
    foreach ($rij in $ontwerp) {
        $seg = $rij.Segment
        if ($rij.Marge -lt 0) {
            Out-Line ("     VLAN {0} {1}: /{2} is TE KLEIN ({3} hosts gevraagd, {4} bruikbaar)." -f $seg.Vlan, $seg.Naam, $seg.Prefix, (Format-Getal $seg.Toestellen), (Format-Getal $rij.Subnet.Bruikbaar)) 'Red'
        } else {
            Out-Line ("     VLAN {0} {1}: /{2}  ({3} hosts gevraagd, {4} bruikbaar, marge {5})" -f $seg.Vlan, $seg.Naam, $seg.Prefix, (Format-Getal $seg.Toestellen), (Format-Getal $rij.Subnet.Bruikbaar), (Format-Getal $rij.Marge)) 'White'
        }
        Out-Uitleg $seg.Motivatie
        Out-Uitleg ("bereik {0}, broadcast {1}" -f $rij.Subnet.Bereik, (ConvertTo-IPv4 $rij.Subnet.Broadcast))
    }

    Out-Stap 5 'Verder denken'
    foreach ($regel in $Case.Extra) { Out-Uitleg ('- ' + $regel) }
    Out-Uitleg '- Groei: kies je masker niet op de dag van vandaag, maar op over drie jaar.'
    Out-Line ''
}

# ---------------------------------------------------------------------------
# Eigen opdrachten: je geeft zelf netwerk + opgave in
# ---------------------------------------------------------------------------

# Leest "192.168.10.0/24", "192.168.10.0 /24" of "192.168.10.0 255.255.255.0".
function ConvertFrom-NetwerkTekst {
    param([string]$Tekst)
    $t = ([string]$Tekst).Trim()
    if (-not $t) { throw 'Je hebt geen netwerk ingevuld.' }
    $adres = $null
    $prefix = 0
    if ($t -match '^(\d{1,3}(?:\.\d{1,3}){3})\s*/\s*(\d{1,2})$') {
        $adres = $Matches[1]
        $prefix = [int]$Matches[2]
    }
    elseif ($t -match '^(\d{1,3}(?:\.\d{1,3}){3})\s*[/ ]\s*(\d{1,3}(?:\.\d{1,3}){3})$') {
        $adres = $Matches[1]
        [long]$m = ConvertFrom-IPv4 $Matches[2]
        [long]$inv = 4294967295 - $m
        if (($inv -band ($inv + 1)) -ne 0) { throw ("Het subnetmask {0} is ongeldig (enen moeten aaneengesloten vooraan staan)." -f $Matches[2]) }
        $prefix = 32 - (Get-BitsVoorAantal ($inv + 1))
    }
    else {
        throw ("Ik begrijp '{0}' niet. Schrijf het zo: 192.168.10.0/24  (of: 192.168.10.0 255.255.255.0)" -f $t)
    }
    if ($prefix -gt 30) { throw ("/{0} is te klein om te verdelen: je hebt minstens /30 nodig." -f $prefix) }
    [long]$a = ConvertFrom-IPv4 $adres
    [long]$blok = Get-Blokgrootte $prefix
    [long]$netwerk = $a - ($a % $blok)
    $opmerking = ''
    if ($netwerk -ne $a) {
        $opmerking = ("Let op: {0} is geen netwerkadres van een /{1}. Ik reken met het netwerkadres {2}/{1}." -f $adres, $prefix, (ConvertTo-IPv4 $netwerk))
    }
    return [pscustomobject]@{ Netwerk = (ConvertTo-IPv4 $netwerk); Prefix = $prefix; Opmerking = $opmerking }
}

function ConvertFrom-GetallenTekst {
    param([string]$Tekst)
    $uit = @()
    foreach ($stuk in ([string]$Tekst -split '[,;\s]+')) {
        if (-not $stuk) { continue }
        [long]$n = 0
        if (-not [long]::TryParse($stuk, [ref]$n)) { throw ("'{0}' is geen getal." -f $stuk) }
        $uit += $n
    }
    if ($uit.Count -eq 0) { throw 'Je hebt geen getallen ingevuld.' }
    return $uit
}

# Bouwt een opdracht-object dat de Show-functies kunnen tonen.
# Soort: gelijk | host | vlsm
function New-EigenOpdracht {
    param(
        [string]$Soort,
        [string]$NetwerkTekst,
        [long]$Aantal = 0,
        [long[]]$Hosts = @(),
        [int[]]$Show = @()
    )
    $Hosts = @($Hosts | Where-Object { $null -ne $_ })
    $Show = @($Show | Where-Object { $null -ne $_ })
    $n = ConvertFrom-NetwerkTekst $NetwerkTekst
    $ex = @{ Id = 'EIGEN'; Netwerk = $n.Netwerk; Prefix = $n.Prefix; Opmerking = $n.Opmerking; Soort = $Soort }
    [long]$aantalSubnetten = 0

    if ($Soort -eq 'gelijk') {
        if ($Aantal -lt 2) { throw 'Bij gelijk verdelen heb je minstens 2 subnetten nodig.' }
        [long]$bits = Get-BitsVoorAantal $Aantal
        if ($bits -gt 12) { throw 'Dat zijn te veel subnetten om uit te schrijven (maximaal 4.096).' }
        if (($n.Prefix + $bits) -gt 30) {
            throw ("Een /{0} kan je niet in {1} subnetten verdelen: je zou /{2} krijgen en dan blijven er geen bruikbare hosts over (maximaal /30)." -f $n.Prefix, (Format-Getal $Aantal), ($n.Prefix + $bits))
        }
        $ex['Aantal'] = $Aantal
        $aantalSubnetten = [long][math]::Pow(2, $bits)
        $laatste = $Aantal
    }
    elseif ($Soort -eq 'host') {
        if ($Hosts.Count -lt 1 -or $Hosts[0] -lt 1) { throw 'Geef het aantal hosts per subnet op (minstens 1).' }
        [long]$h = $Hosts[0]
        if ($h -gt 4294967294) { throw 'Dat zijn te veel hosts voor een IPv4-subnet.' }
        [long]$hostBits = Get-HostBitsVoorHosts $h
        $nieuwPrefix = 32 - $hostBits
        if ($nieuwPrefix -lt $n.Prefix) {
            throw ("Een /{0} heeft maar {1} bruikbare adressen; dat is te klein voor subnetten van {2} hosts." -f $n.Prefix, (Format-Getal (Get-BruikbaarAantal $n.Prefix)), (Format-Getal $h))
        }
        if (($nieuwPrefix - $n.Prefix) -gt 12) { throw 'Dat geeft te veel subnetten om uit te schrijven (maximaal 4.096). Kies een groter netwerk of meer hosts.' }
        $ex['Hosts'] = $h
        $aantalSubnetten = [long][math]::Pow(2, ($nieuwPrefix - $n.Prefix))
        $laatste = $aantalSubnetten
    }
    elseif ($Soort -eq 'vlsm') {
        if ($Hosts.Count -lt 1) { throw 'Geef minstens 1 aantal hosts op.' }
        if ($Hosts.Count -gt 100) { throw 'Maximaal 100 subnetten bij VLSM.' }
        foreach ($h in $Hosts) {
            if ($h -lt 1 -or $h -gt 4294967294) { throw ("Ongeldig aantal hosts: {0}." -f $h) }
            if ((Get-HostBitsVoorHosts $h) -gt (32 - $n.Prefix)) {
                throw ("Een subnet voor {0} hosts past niet eens in /{1}." -f (Format-Getal $h), $n.Prefix)
            }
        }
        $ex['Hosts'] = $Hosts
    }
    else { throw "Onbekend soort opdracht: $Soort" }

    if ($Soort -ne 'vlsm') {
        if ($Show.Count -gt 0) { $ex['Toon'] = @($Show) }
        elseif ($laatste -le 8) { $ex['Toon'] = @(1..[int]$laatste) }
        else { $ex['Toon'] = @(1, 2, [int]$laatste) }
    }
    return $ex
}

function Show-Eigen {
    param($Ex)
    if ($Ex.Opmerking) { Out-Line ''; Out-Line ('  ' + $Ex.Opmerking) 'Yellow' }
    if ($Ex.Soort -eq 'gelijk') { Show-GelijkVerdelen $Ex }
    elseif ($Ex.Soort -eq 'host') { Show-HostBased $Ex }
    else { Show-Vlsm $Ex }
}

function Read-Invoer {
    param([string]$Vraag)
    $r = Read-Host $Vraag
    if ($null -eq $r) { return 'q' }
    return $r.Trim()
}

# Invoerscherm: vraagt stap voor stap wat je wil laten uitrekenen.
function Start-EigenOpdracht {
    while ($true) {
        Out-Line ''
        Out-Segs @(@('  '), @(' EIGEN OPDRACHT ', 'Black', 'Yellow'), @('  vul zelf een opgave in', 'DarkGray'))
        Out-Line ''
        Out-Segs @(@('   '), @('1', 'Yellow'), @('  Gelijk verdelen   - je kent het aantal subnetten'))
        Out-Segs @(@('   '), @('2', 'Yellow'), @('  Host based        - je kent het aantal hosts per subnet'))
        Out-Segs @(@('   '), @('3', 'Yellow'), @('  VLSM              - lijst van hosts per subnet (100, 50, 30 ...)'))
        Out-Line '   Enter  terug naar het menu' 'DarkGray'
        $soort = Read-Invoer '  Welk soort opdracht'
        if ($soort -in @('', 'q', '0')) { return }
        if ($soort -notin @('1', '2', '3')) { Out-Line '  Kies 1, 2 of 3.' 'Red'; continue }

        $netwerk = ''
        while (-not $netwerk) {
            $t = Read-Invoer '  Netwerk (bv. 192.168.10.0/24)'
            if ($t -in @('', 'q')) { return }
            try { [void](ConvertFrom-NetwerkTekst $t); $netwerk = $t }
            catch { Out-Line ('  ' + $_.Exception.Message) 'Red' }
        }

        try {
            if ($soort -eq '1') {
                $v = Read-Invoer '  In hoeveel subnetten verdelen'
                if ($v -in @('', 'q')) { continue }
                $ex = New-EigenOpdracht -Soort gelijk -NetwerkTekst $netwerk -Aantal (ConvertFrom-GetallenTekst $v)[0]
            }
            elseif ($soort -eq '2') {
                $v = Read-Invoer '  Hoeveel hosts moet elk subnet bevatten'
                if ($v -in @('', 'q')) { continue }
                $ex = New-EigenOpdracht -Soort host -NetwerkTekst $netwerk -Hosts (ConvertFrom-GetallenTekst $v)[0]
            }
            else {
                $v = Read-Invoer '  Hosts per subnet, gescheiden door komma (bv. 100, 50, 30, 10)'
                if ($v -in @('', 'q')) { continue }
                $ex = New-EigenOpdracht -Soort vlsm -NetwerkTekst $netwerk -Hosts (ConvertFrom-GetallenTekst $v)
            }
            Show-Eigen $ex
        }
        catch {
            Out-Line ''
            Out-Line ('  ' + $_.Exception.Message) 'Red'
        }
        $nog = Read-Invoer '  Nog een eigen opdracht? (Enter = ja, n = terug naar het menu)'
        if ($nog -in @('n', 'N', 'q', 'nee')) { return }
    }
}

# ---------------------------------------------------------------------------
# Alles, zelftest, menu
# ---------------------------------------------------------------------------

function Show-Alles {
    Out-Line ('#' * 78) 'DarkGray'
    Out-Line '  LAB - SUBNETTEN   volledige uitwerking, stap voor stap' 'Yellow'
    Out-Line '  Onderdelen: A gelijk verdelen | B host based | C VLSM | D cases' 'DarkGray'
    Out-Line ('#' * 78) 'DarkGray'
    if (-not $NoPause -and $script:KanVragen -and -not $All) {
        Out-Line '  (Enter om te starten)'
        [void](Read-Host)
    }

    foreach ($ex in $script:GelijkVerdelen) { Show-GelijkVerdelen $ex }
    foreach ($ex in $script:HostBased) { Show-HostBased $ex }
    foreach ($ex in $script:VlsmOefeningen) { Show-Vlsm $ex }
    foreach ($case in $script:Cases) { Show-Case $case }

    Out-Line ''
    Out-Line ('#' * 78) 'DarkGray'
    Out-Line '  KLAAR' 'Green'
    Out-Line '  Vergelijk je eigen antwoorden met de invulbladen hierboven.' 'White'
    Out-Line '  Eigen opdracht? Kies 8 in het menu of gebruik -Network ... -Subnets/-Hosts/-Vlsm.' 'White'
    Out-Line '  Klopt iets niet? Draai -Check om de rekenkern te controleren,' 'White'
    Out-Line '  of -Theory voor de methode in 6 stappen.' 'White'
    Out-Line ('#' * 78) 'DarkGray'
}

function Show-ExerciseById {
    param([string]$Id)
    $idBoven = $Id.ToUpper()
    foreach ($ex in $script:GelijkVerdelen) { if ($ex.Id -eq $idBoven) { Show-GelijkVerdelen $ex; return $true } }
    foreach ($ex in $script:HostBased) { if ($ex.Id -eq $idBoven) { Show-HostBased $ex; return $true } }
    foreach ($ex in $script:VlsmOefeningen) { if ($ex.Id -eq $idBoven) { Show-Vlsm $ex; return $true } }
    foreach ($case in $script:Cases) { if ($case.Id -eq $idBoven) { Show-Case $case; return $true } }
    return $false
}

# Verwacht: de uitkomsten van het lab, onafhankelijk van de planner opgeschreven.
$script:Verwacht = @(
    @{ Id = 'A1'; Soort = 'Gelijk'; Bits = 2; Prefix = 26; Masker = '255.255.255.192'; Subnet = @{ 3 = '10.0.1.128' } },
    @{ Id = 'A2'; Soort = 'Gelijk'; Bits = 5; Prefix = 30; Masker = '255.255.255.252'; Subnet = @{ 5 = '209.68.221.144' } },
    @{ Id = 'A3'; Soort = 'Gelijk'; Bits = 4; Prefix = 29; Masker = '255.255.255.248'; Subnet = @{ 10 = '184.2.146.200'; 11 = '184.2.146.208' } },
    @{ Id = 'A4'; Soort = 'Gelijk'; Bits = 2; Prefix = 29; Masker = '255.255.255.248'; Subnet = @{ 3 = '214.42.37.208' } },
    @{ Id = 'A5'; Soort = 'Gelijk'; Bits = 5; Prefix = 29; Masker = '255.255.255.248'; Subnet = @{ 11 = '160.155.148.80' } },
    @{ Id = 'A6'; Soort = 'Gelijk'; Bits = 3; Prefix = 30; Masker = '255.255.255.252'; Subnet = @{ 4 = '111.190.164.76' } },
    @{ Id = 'B1'; Soort = 'Host';   Bits = 3; Prefix = 27; Masker = '255.255.255.224'; Subnet = @{ 5 = '93.54.240.128' } },
    @{ Id = 'B2'; Soort = 'Host';   Bits = 3; Prefix = 27; Masker = '255.255.255.224'; Subnet = @{ 6 = '169.174.246.160' } },
    @{ Id = 'B3'; Soort = 'Host';   Bits = 4; Prefix = 24; Masker = '255.255.255.0';   Subnet = @{ 7 = '13.95.246.0' } },
    @{ Id = 'B4'; Soort = 'Host';   Bits = 4; Prefix = 28; Masker = '255.255.255.240'; Subnet = @{ 11 = '32.38.231.160' } },
    @{ Id = 'C1'; Soort = 'Vlsm';   Prefix = @(25, 26, 27, 28, 28); Masker = @('255.255.255.128', '255.255.255.192', '255.255.255.224', '255.255.255.240', '255.255.255.240'); Subnet = @{ 1 = '193.168.50.0'; 2 = '193.168.50.128'; 3 = '193.168.50.192'; 4 = '193.168.50.224'; 5 = '193.168.50.240' } },
    @{ Id = 'C2'; Soort = 'Vlsm';   Prefix = @(19, 21, 21); Masker = @('255.255.224.0', '255.255.248.0', '255.255.248.0'); Subnet = @{ 1 = '172.10.0.0'; 2 = '172.10.32.0'; 3 = '172.10.40.0' } }
)

function Test-Berekenen {
    $fouten = @()
    $regels = @()

    foreach ($verw in $script:Verwacht) {
        $soort = $verw.Soort
        if ($soort -eq 'Gelijk') {
            $ex = $script:GelijkVerdelen | Where-Object { $_.Id -eq $verw.Id } | Select-Object -First 1
            $plan = New-GelijkPlan -Netwerk $ex.Netwerk -Prefix $ex.Prefix -Aantal $ex.Aantal
            $bits = $plan.Bits
            $prefix = $plan.NieuwPrefix
        } elseif ($soort -eq 'Host') {
            $ex = $script:HostBased | Where-Object { $_.Id -eq $verw.Id } | Select-Object -First 1
            $plan = New-HostPlan -Netwerk $ex.Netwerk -Prefix $ex.Prefix -Hosts $ex.Hosts
            $bits = $plan.Geleend
            $prefix = $plan.NieuwPrefix
        } else {
            $ex = $script:VlsmOefeningen | Where-Object { $_.Id -eq $verw.Id } | Select-Object -First 1
            $plan = New-VlsmPlan -Netwerk $ex.Netwerk -Prefix $ex.Prefix -Hosts $ex.Hosts
            $bits = $null
            $prefix = @($plan.Plan | ForEach-Object { $_.Prefix })
        }

        $ok = $true
        $detail = @()

        if ($null -ne $verw.Prefix -and $verw.Prefix -is [array]) {
            for ($i = 0; $i -lt $verw.Prefix.Count; $i++) {
                if ($plan.Plan[$i].Prefix -ne $verw.Prefix[$i]) { $ok = $false; $detail += ('prefix subnet{0} = /{1}, verwacht /{2}' -f ($i + 1), $plan.Plan[$i].Prefix, $verw.Prefix[$i]) }
                if ($plan.Plan[$i].Subnet.Masker -ne $verw.Masker[$i]) { $ok = $false; $detail += ('masker subnet{0} = {1}, verwacht {2}' -f ($i + 1), $plan.Plan[$i].Subnet.Masker, $verw.Masker[$i]) }
            }
        } else {
            if ($prefix -ne $verw.Prefix) { $ok = $false; $detail += ("prefix = /$prefix, verwacht /$($verw.Prefix)") }
            if ($null -ne $verw.Bits -and $bits -ne $verw.Bits) { $ok = $false; $detail += ("bits = $bits, verwacht $($verw.Bits)") }
        }

        foreach ($nr in $verw.Subnet.Keys) {
            $verwachtAdres = $verw.Subnet[$nr]
            $werkelijk = $null
            if ($soort -eq 'Vlsm') {
                if ($nr -le $plan.Plan.Count) { $werkelijk = (ConvertTo-IPv4 $plan.Plan[$nr - 1].Subnet.Netwerk) }
                if ($nr -le $plan.Plan.Count -and $plan.Plan[$nr - 1].Subnet.Masker -ne $verw.Masker[$nr - 1]) { $ok = $false; $detail += ('masker subnet{0} = {1}, verwacht {2}' -f $nr, $plan.Plan[$nr - 1].Subnet.Masker, $verw.Masker[$nr - 1]) }
            } else {
                if ($nr -le $plan.Subnetten.Count) { $werkelijk = (ConvertTo-IPv4 $plan.Subnetten[$nr - 1].Netwerk) }
            }
            if ($werkelijk -ne $verwachtAdres) {
                $ok = $false
                $detail += ("subnet$nr = $werkelijk, verwacht $verwachtAdres")
            }
        }

        if ($ok) {
            $regels += ('  OK    {0}' -f $verw.Id)
        } else {
            $regels += ('  FOUT  {0}: {1}' -f $verw.Id, ($detail -join '; '))
            $fouten += $verw.Id
        }
    }

    Out-Line ''
    Out-Line ('=' * 78) 'DarkGray'
    Out-Line '  ZELFTEST - rekenkern tegen de antwoorden van het lab' 'Yellow'
    Out-Line ('=' * 78) 'DarkGray'
    foreach ($regel in $regels) {
        if ($regel.StartsWith('  OK')) { Out-Line $regel 'Green' } else { Out-Line $regel 'Red' }
    }
    Out-Line ''
    if ($fouten.Count -eq 0) {
        Out-Line ('  {0}/{0} oefeningen kloppen.' -f $script:Verwacht.Count) 'Green'
        return 0
    }
    Out-Line ('  {0} van {1} oefeningen klopt niet.' -f $fouten.Count, $script:Verwacht.Count) 'Red'
    return 1
}

function Show-Menu {
    Out-Line ''
    Out-Segs @(@('  '), @(' LAB - SUBNETTEN ', 'Black', 'Cyan'))
    Out-Line ''
    $items = @(
        @('8', 'Eigen opdracht invoeren   <-- zelf netwerk + opgave typen'),
        @('1', 'Theorie: de methode in 6 stappen'),
        @('2', 'Gelijk verdelen           (A1 - A6)'),
        @('3', 'Host based verdelen       (B1 - B4)'),
        @('4', 'VLSM                      (C1 - C2)'),
        @('5', 'Cases                     (D1 - D4)'),
        @('6', 'Alles na elkaar           (antwoordsleutel)'),
        @('7', 'Zelftest van het script'),
        @('0', 'Stoppen')
    )
    foreach ($it in $items) {
        Out-Segs @(@('   '), @($it[0], 'Yellow'), @(('  ' + $it[1])))
    }
    Out-Line '   (of typ direct een oefening: A2, B4, C1, D3)' 'DarkGray'
    Out-Line ''
}

function Start-Menu {
    while ($true) {
        Show-Menu
        $keuze = (Read-Host '  Maak een keuze').Trim()
        Out-Line ''
        switch -Regex ($keuze) {
            '^0$' { return }
            '^1$' { Show-Theorie }
            '^2$' { foreach ($ex in $script:GelijkVerdelen) { Show-GelijkVerdelen $ex; Wait-Oefening } }
            '^3$' { foreach ($ex in $script:HostBased) { Show-HostBased $ex; Wait-Oefening } }
            '^4$' { foreach ($ex in $script:VlsmOefeningen) { Show-Vlsm $ex; Wait-Oefening } }
            '^5$' { foreach ($case in $script:Cases) { Show-Case $case; Wait-Oefening } }
            '^6$' { Show-Alles }
            '^7$' { [void](Test-Berekenen) }
            '^(8|e|eigen)$' { Start-EigenOpdracht }
            '^[A-Da-d][0-9]+$' {
                if (-not (Show-ExerciseById $keuze)) { Out-Line '  Die oefening bestaat niet (A1-A6, B1-B4, C1-C2, D1-D4).' 'Red' }
            }
            default { Out-Line '  Onbekende keuze.' 'Red' }
        }
    }
}

# ---------------------------------------------------------------------------
# Hoofdprogramma
# ---------------------------------------------------------------------------

$exitCode = 0
try {
    if ($SaveTo) { $script:Buffer = New-Object System.Text.StringBuilder }

    if ($Check) {
        $exitCode = Test-Berekenen
    }
    elseif ($PSBoundParameters.ContainsKey('Network') -or $PSBoundParameters.ContainsKey('Subnets') -or $PSBoundParameters.ContainsKey('Hosts') -or $PSBoundParameters.ContainsKey('Vlsm')) {
        if (-not $PSBoundParameters.ContainsKey('Network')) { throw 'Geef ook het netwerk op, bv.  -Network 192.168.10.0/24' }
        $gekozen = @(@('Subnets', 'Hosts', 'Vlsm') | Where-Object { $PSBoundParameters.ContainsKey($_) })
        if ($gekozen.Count -ne 1) { throw 'Kies precies een van: -Subnets <aantal>, -Hosts <aantal> of -Vlsm <lijst>.' }
        $toonLijst = @()
        if ($PSBoundParameters.ContainsKey('Show')) { $toonLijst = [int[]](ConvertFrom-GetallenTekst ($Show -join ',')) }
        if ($PSBoundParameters.ContainsKey('Subnets')) { $eigen = New-EigenOpdracht -Soort gelijk -NetwerkTekst $Network -Aantal $Subnets -Show $toonLijst }
        elseif ($PSBoundParameters.ContainsKey('Hosts')) { $eigen = New-EigenOpdracht -Soort host -NetwerkTekst $Network -Hosts @($Hosts) -Show $toonLijst }
        else { $eigen = New-EigenOpdracht -Soort vlsm -NetwerkTekst $Network -Hosts ([long[]](ConvertFrom-GetallenTekst ($Vlsm -join ','))) }
        Show-Eigen $eigen
    }
    elseif ($Exercise) {
        Out-Line ''
        if (-not (Show-ExerciseById $Exercise)) {
            Out-Line ("  Oefening '{0}' bestaat niet. Kies uit: A1-A6, B1-B4, C1-C2, D1-D4." -f $Exercise) 'Red'
            $exitCode = 1
        }
    }
    elseif ($Theory) {
        Show-Theorie
    }
    elseif ($All -or -not $script:KanVragen) {
        Show-Alles
    }
    else {
        Start-Menu
    }
}
catch {
    Out-Line ''
    Out-Line ('  FOUT: ' + $_.Exception.Message) 'Red'
    $exitCode = 1
}
finally {
    if ($null -ne $script:Buffer) {
        $pad = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SaveTo)
        Set-Content -Path $pad -Value $script:Buffer.ToString() -Encoding UTF8
        Write-Host ''
        Write-Host ("  Uitwerking bewaard in: $pad") -ForegroundColor Green
    }
}

exit $exitCode
