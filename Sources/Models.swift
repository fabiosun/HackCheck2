import Foundation

enum CheckStatus { case ok, warn, fail, info }

struct Check: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var status: CheckStatus
}

struct PropertyRow: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var value: String
    var raw: Data? = nil          // valore originale (per l'esportazione in plist)
}

struct USBPort: Identifiable {
    var id: String
    var name = ""                 // es. HS01, SS02
    var number = 0
    var connector = 0             // UsbConnector: 0/3 Type-A, 8/9/10 Type-C, 255 interno
    var used = false
    var deviceName = ""
    var deviceID = ""
    var speed = ""

    var connectorText: String {
        switch connector {
        case 0: return "Type-A (USB 2.0)"
        case 3: return "Type-A (USB 3.x)"
        case 8, 9, 10: return "Type-C"
        case 255: return tr("Interno (Bluetooth / Hub / RGB)")
        default: return "Type \(connector)"
        }
    }
}

struct USBController: Identifiable {
    var id: String
    var title = ""
    var vendor = ""
    var idString = ""
    var location = ""
    var ports: [USBPort] = []
}

struct PCIDevice: Identifiable, Hashable {
    var id: String
    var name: String
    var vendorID: UInt16 = 0
    var deviceID: UInt16 = 0
    var subVendorID: UInt16?
    var subDeviceID: UInt16?
    var revision: UInt8?
    var classCode: UInt32 = 0
    var vendorName = ""
    var deviceName = ""
    var className = ""
    var baseClassName = ""
    var subclassName = ""
    var aspm = ""
    var ioregName = ""
    var ioName = ""
    var devicePath = ""
    var location = ""
    var linkStatus = ""
    var acpiPath = ""
    var builtIn = false
    var drivers: [String] = []
    var properties: [PropertyRow] = []

    var idString: String { Fmt.hex(vendorID, 4) + ":" + Fmt.hex(deviceID, 4) }
    var baseClass: UInt32 { classCode >> 16 }
    var subClass16: UInt32 { classCode >> 8 }

    /// Riga in stile `lspci -nn`
    var lspci: String {
        var s = "\(location) \(className) [\(Fmt.hex(subClass16, 4))]: \(vendorName) \(deviceName) [\(idString)]"
        if let r = revision { s += " (rev \(Fmt.hex(r, 2)))" }
        return s
    }
}

struct GPUInfo: Identifiable {
    var id: String
    var name = ""
    var vendor = ""
    var pciID = ""
    var subsystem = ""
    var location = ""
    var link = ""
    var accelerator = ""
    var metalPlugin = ""
    var gvaCodec = ""
    var hevcDecode = ""
    var hevcEncode = ""
    var platformID = ""
    var framebuffers = 0
}

struct AudioInfo: Identifiable {
    var id: String
    var name = ""
    var vendor = ""
    var location = ""
    var layoutID = ""
    var driver = ""
}

struct NetIface: Identifiable {
    var id: String
    var bsd = ""
    var port = ""
    var mac = ""
    var ip = ""
    var controller = ""
    var builtIn = false
}

struct KextInfo: Identifiable {
    var id: String
    var version: String
}

struct CodecInfo: Identifiable {
    var id: String
    var name: String
    var supported: Bool
}

struct AudioDeviceInfo: Identifiable {
    var id: String
    var name = ""
    var manufacturer = ""
    var transport = ""
    var source = ""

    var isUSB: Bool {
        if transport.caseInsensitiveCompare("USB") == .orderedSame { return true }
        return transport.lowercased().contains("usb")
    }
}

struct DevicePropGroup: Identifiable {
    var id: String
    var path: String
    var location = ""            // es. 00:02.0, se ricavabile dal device path
    var rows: [PropertyRow] = []
}

struct BootInfo {
    var loader = ""              // vuoto = non rilevato
    var loaderVersion = ""
    var loaderSource = ""        // da dove è stato dedotto
    var bootArgs = ""
    var sipStatus = ""
    var csrHex = ""
    var csrFlags: [String] = []
    var bootLog = ""
    var nvram = ""
    var signals: [String] = []   // diagnostica del rilevamento
    var deviceProps: [DevicePropGroup] = []
    var devicePropsNote = ""
    var xhciPortLimit: Bool? = nil   // Kernel → Quirks → XhciPortLimit dal config.plist trovato
    var configSource = ""

    var loaderName: String { loader.isEmpty ? tr("Non rilevato") : loader }

    var sipStatusDisplay: String {
        guard !sipStatus.isEmpty else { return "" }
        let stripped = sipStatus.replacingOccurrences(of: "System Integrity Protection status:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let lower = stripped.lowercased()
        switch lower {
        case "enabled":
            return tr("Attivo")
        case "disabled":
            return tr("Disattivato")
        case "unknown (custom configuration)":
            return tr("Sconosciuto (configurazione personalizzata)")
        case "enabled (custom configuration)":
            return tr("Attivo (configurazione personalizzata)")
        case "disabled (custom configuration)":
            return tr("Disattivato (configurazione personalizzata)")
        default:
            if lower.contains("unknown") && lower.contains("custom configuration") {
                return tr("Sconosciuto (configurazione personalizzata)")
            }
            if lower.contains("enabled") && lower.contains("custom configuration") {
                return tr("Attivo (configurazione personalizzata)")
            }
            if lower.contains("disabled") && lower.contains("custom configuration") {
                return tr("Disattivato (configurazione personalizzata)")
            }
            return stripped.isEmpty ? sipStatus : stripped
        }
    }
}

struct SystemInfo {
    var model = ""
    var macOS = ""
    var build = ""
    var kernel = ""
    var hostname = ""
    var uptime = ""
    var boardID = ""
    var serial = ""
    var uuid = ""
    var manufacturer = ""
    var arch = ""

    var macOSName: String {
        switch Int(macOS.split(separator: ".").first ?? "") ?? 0 {
        case 13: return "macOS Ventura"
        case 14: return "macOS Sonoma"
        case 15: return "macOS Sequoia"
        case 26: return "macOS Tahoe"
        default: return "macOS"
        }
    }
}

struct CPUInfo {
    var brand = ""
    var vendor = ""
    var cores = 0
    var threads = 0
    var family = ""
    var model = ""
    var stepping = ""
    var l2 = ""
    var l3 = ""
    var ram = ""
    var features: [String] = []
    var microarch = ""            // dedotta da family/model/stepping
    var generation = ""           // dedotta dal nome (es. 9th Gen)
}

struct MemoryModule: Identifiable {
    var id: String
    var slot = ""
    var size = ""
    var type = ""
    var speed = ""
    var manufacturer = ""
    var partNumber = ""
}

struct Snapshot {
    var system = SystemInfo()
    var cpu = CPUInfo()
    var pci: [PCIDevice] = []
    var gpus: [GPUInfo] = []
    var metalDevices: [String] = []
    var codecs: [CodecInfo] = []
    var audio: [AudioInfo] = []
    var audioCodecs: [String] = []
    var audioDevices: [AudioDeviceInfo] = []
    var network: [NetIface] = []
    var kexts: [KextInfo] = []
    var boot = BootInfo()
    var acpiDevices: [String] = []
    var usb: [USBController] = []
    var memory: [MemoryModule] = []
    var usbPower = ""            // nome del device ACPI che fornisce le proprietà di alimentazione USB (es. USBX)
    var usbPowerDetail = ""
    /// Calcolati al momento della visualizzazione, così seguono la lingua scelta.
    var checks: [Check] { Collector.checks(self) }
}
