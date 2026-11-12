# Lennie's Amazing CIDR Converter

Een PowerShell-script dat **subnetten stap voor stap uitrekent**, zoals je het op papier
zou doen: hoeveel bits leen je, wat wordt je CIDR en subnetmask, wat is de blokgrootte,
en welke subnetten krijg je (met bruikbaar bereik en broadcast). Geschreven voor het
labo "Subnetten", maar je kan er ook **je eigen opgaven** mee laten uitwerken.

Het script rekent alles zelf uit (geen hardcoded antwoorden) en bevat een zelftest.
Bedoeld om je eigen werk na te kijken: probeer eerst zelf.

## Starten

Vereist PowerShell 7 (`pwsh`). Getest met PowerShell 7 op Linux; Windows PowerShell 5.1
is niet getest.

```
pwsh ./labs/Lab-Subnetten.ps1
```

Je krijgt een menu. Kies **8** om zelf een opgave in te typen.

## Je eigen opdracht ingeven

Via het menu (optie 8) of rechtstreeks met parameters:

| Soort | Voorbeeld |
|---|---|
| Gelijk verdelen: in N subnetten | `pwsh ./labs/Lab-Subnetten.ps1 -Network 192.168.10.0/24 -Subnets 5` |
| Host based: N hosts per subnet | `pwsh ./labs/Lab-Subnetten.ps1 -Network 172.16.0.0/16 -Hosts 500` |
| VLSM: lijst van hosts per subnet | `pwsh ./labs/Lab-Subnetten.ps1 -Network 10.1.0.0/24 -Vlsm 100,50,30,10,10` |

- Het netwerk mag ook met masker: `-Network "192.168.10.0 255.255.255.0"`.
- `-Show 1,2,9` kiest welke subnetnummers in het invulblad komen (anders eerste, tweede en laatste).
- Lange tabellen worden ingekort; met `-Full` zie je alle rijen.
- Een adres dat geen netwerkadres is (`192.168.10.77/24`) wordt gecorrigeerd, met een melding.

## Andere opties

| Commando | Wat het doet |
|---|---|
| `-Exercise A2` | Een oefening van het lab (A1-A6, B1-B4, C1-C2, D1-D4) |
| `-Exercise A1 -Step` | Pauzeert na elke stap |
| `-Theory` | De methode in 6 stappen, machtentabel en maskertabel |
| `-All -NoPause` | Alles na elkaar (antwoordsleutel), zonder pauzes |
| `-SaveTo bestand.txt` | Bewaart de uitwerking ook als tekstbestand |
| `-Check` | Zelftest: rekenkern tegen de antwoorden van het lab, exitcode 0 = alles klopt |

Zonder terminal-invoer (pipe of omleiding) slaat het script het menu over en toont het
de volledige antwoordsleutel.

## Over de ProjectState-bestanden

`AGENTS.md`, `PROJECT.md`, `STATE.yaml`, `evidence/` en `scripts/projectstate_*.py` zijn
coördinatiebestanden van de ProjectState-werkwijze. Het script zelf heeft ze niet nodig.
