# HackCheck 2

HackCheck 2 is an app inspired by the original HackCheck, created by **Gengik84** and **foskvs**, restored and rewritten in **SwiftUI** by **fabiosun** and **Anto65**.

## Supported macOS versions
- macOS 13.0 (Ventura) or later

## Description
HackCheck 2 collects and displays system and hardware information, useful also in Hackintosh environments:

- **Overview**: general system summary and quick checks.
- **CPU & memory**: details about the processor, cache, instruction sets, and RAM modules.
- **Sensors**: temperatures, fans, voltages, power, and current (via SMC/VirtualSMC and related plugins).
- **Graphics**: GPUs, Metal acceleration, and hardware video codecs.
- **Network & Wi-Fi**: interfaces and network adapters.
- **Audio**: HDA codecs, PCI controllers, and detected audio devices.
- **Storage**: controllers and disk/partition management, including EFI partitions (mount, unmount, open in Finder).
- **USB**: controllers, ports, and connected devices.
- **PCI devices**: detailed list with copy and export options.
- **Device Properties**: view and export in OpenCore format (`DeviceProperties → Add`).
- **Kexts**: loaded non-Apple kexts and related information.
- **Boot & SIP**: bootloader status, SIP, boot arguments, diagnostics, and NVRAM/log data when available.
- **ACPI**: exposed devices and error scan from logs.
- **System Details**: `system_profiler` data and full report export.

The app lets you copy information for the currently open tab and export reports; in the full report export, sensitive data (such as serial number and UUID) is redacted.

## Credits
- Original creators: Gengik84 and foskvs
- Original icon: Ciro82 and fabiosun
- App restored in SwiftUI by: fabiosun and Anto65
- PCI database: [PCI ID Repository](https://pci-ids.ucw.cz)

© macOS86 2026