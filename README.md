# HackCheck 2

HackCheck 2 è un’app ispirata all’originale HackCheck, creata da **Gengik84** e **foskvs**, restaurata e riscritta in **SwiftUI** da **fabiosun** e **Anto65**.

## Versioni di macOS supportate
- macOS 13.0 (Ventura) o successivo

## Descrizione
HackCheck 2 raccoglie e mostra informazioni sul sistema e sull’hardware, utili anche in ambito Hackintosh:

- **Panoramica**: riepilogo generale del sistema e controlli rapidi.
- **CPU e memoria**: dettagli su processore, cache, istruzioni e moduli RAM.
- **Sensori**: temperature, ventole, tensioni, potenza e corrente (tramite SMC/VirtualSMC e relativi plugin).
- **Grafica**: GPU, accelerazione Metal e codec video hardware.
- **Rete e Wi-Fi**: interfacce e schede di rete.
- **Audio**: codec HDA, controller PCI e dispositivi audio rilevati.
- **Archiviazione**: controller e gestione di dischi/partizioni, incluse EFI (monta, smonta, apri nel Finder).
- **USB**: controller, porte e dispositivi collegati.
- **Dispositivi PCI**: elenco dettagliato con copia ed esportazione.
- **Device Properties**: visualizzazione ed esportazione in formato OpenCore (`DeviceProperties → Add`).
- **Kext**: kext non Apple caricate e informazioni correlate.
- **Boot e SIP**: stato bootloader, SIP, argomenti di boot, diagnostica e dati NVRAM/log quando disponibili.
- **ACPI**: dispositivi esposti e scansione degli errori dal log.
- **Dettagli di sistema**: dati `system_profiler` ed esportazione del report completo.

L’app consente di copiare le informazioni della scheda aperta ed esportare report; nell’esportazione del report completo i dati sensibili (ad esempio seriale e UUID) vengono oscurati.

## Crediti
- Creatori originali: Gengik84 e foskvs
- Icona originale: Ciro82 e fabiosun
- App restaurata in SwiftUI da: fabiosun e Anto65
- Database PCI: [PCI ID Repository](https://pci-ids.ucw.cz)

© macOS86 2026