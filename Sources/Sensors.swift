import SwiftUI
import IOKit
import Foundation

// MARK: - Lettura SMC (AppleSMC / VirtualSMC)

struct SMCParam {
    struct Vers { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
    struct PLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpu: UInt32 = 0; var gpu: UInt32 = 0; var mem: UInt32 = 0 }
    struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }

    var key: UInt32 = 0
    var vers = Vers()
    var pLimit = PLimit()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

final class SMCConnection {
    private var conn: io_connect_t = 0

    init?() {
        guard MemoryLayout<SMCParam>.stride == 80 else { return nil }   // layout identico alla struct C del kernel
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(conn) }

    static func code(_ s: String) -> UInt32 {
        var v: UInt32 = 0
        for u in s.utf8.prefix(4) { v = (v << 8) | UInt32(u) }
        return v
    }

    static func name(_ c: UInt32) -> String {
        String(decoding: [UInt8((c >> 24) & 0xFF), UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF)], as: UTF8.self)
    }

    private func call(_ input: SMCParam) -> SMCParam? {
        var inp = input
        var out = SMCParam()
        var size = MemoryLayout<SMCParam>.stride
        let r = IOConnectCallStructMethod(conn, 2, &inp, MemoryLayout<SMCParam>.stride, &out, &size)
        return (r == KERN_SUCCESS && out.result == 0) ? out : nil
    }

    func readRaw(_ key: String) -> (type: String, bytes: [UInt8])? {
        var p = SMCParam()
        p.key = SMCConnection.code(key)
        p.data8 = 9                                   // GetKeyInfo
        guard let info = call(p) else { return nil }
        var q = SMCParam()
        q.key = p.key
        q.keyInfo.dataSize = info.keyInfo.dataSize
        q.data8 = 5                                   // ReadKey
        guard let o = call(q) else { return nil }
        let n = min(Int(info.keyInfo.dataSize), 32)
        var arr: [UInt8] = []
        withUnsafeBytes(of: o.bytes) { arr = Array($0.prefix(n)) }
        return (SMCConnection.name(info.keyInfo.dataType), arr)
    }

    func keyCount() -> Int {
        guard let r = readRaw("#KEY"), r.bytes.count >= 4 else { return 0 }
        return (Int(r.bytes[0]) << 24) | (Int(r.bytes[1]) << 16) | (Int(r.bytes[2]) << 8) | Int(r.bytes[3])
    }

    func key(at index: Int) -> String? {
        var p = SMCParam()
        p.data8 = 8                                   // ReadIndex
        p.data32 = UInt32(index)
        guard let o = call(p) else { return nil }
        return SMCConnection.name(o.key)
    }
}

// MARK: - Interpretazione dei valori

struct SensorReading: Identifiable {
    let id: String
    var name: String
    var value: Double
    var unit: String
    var category: Int          // 0 temp SMC, 1 ventole SMC, 2 tensioni, 3 potenza, 4 corrente,
                               // 5 ventole GPU, 6 temp GPU, 7 temp dischi
    var aliases: [String] = [] // chiavi SMC equivalenti, fuse in questa riga
}

enum SensorReader {
    private static let tempNames: [String: String] = [
        "TC0P": "CPU Proximity", "TC0D": "CPU Die", "TC0E": "CPU Die (E)", "TC0F": "CPU Die (F)", "TC0H": "CPU Heatsink",
        "TC0J": "CPU Package", "TC0T": "CPU Package (T)", "TC0p": "CPU Proximity (alt)",
        "TC1C": "CPU Core 1", "TC1c": "CPU Diode 0",
        "TCXC": "CPU PECI", "TCXc": "CPU PECI", "TCGC": "iGPU PECI", "TCSA": "System Agent", "TCSC": "System Agent Core",
        "TG0P": "GPU Proximity", "TG0D": "GPU Die", "TG0H": "GPU Heatsink", "Tm0P": "Memory Proximity",
        "TN0P": "Northbridge Proximity", "TN0D": "Northbridge Die", "TPCD": "PCH Die", "TA0P": "Ambient",
        "TB0T": "Battery", "Ts0P": "Palm Rest", "TL0P": "LCD", "TW0P": "Wi-Fi", "Th0H": "Heatpipe",
    ]

    /// Decodifica i tipi SMC più comuni: flt, fpXY / spXY (virgola fissa), ui8/ui16/ui32.
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        if type == "flt " && bytes.count >= 4 {
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))
        }
        let chars = Array(type)
        if chars.count == 4, bytes.count >= 2, chars[0] == "f" || chars[0] == "s", chars[1] == "p",
           let frac = Int(String(chars[3]), radix: 16) {
            let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
            let v = chars[0] == "s" ? Int(Int16(truncatingIfNeeded: raw)) : raw
            return Double(v) / Double(1 << frac)
        }
        if type == "ui8 " && bytes.count >= 1 { return Double(bytes[0]) }
        if type == "ui16" && bytes.count >= 2 { return Double((Int(bytes[0]) << 8) | Int(bytes[1])) }
        if type == "ui32" && bytes.count >= 4 {
            return Double((Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3]))
        }
        return nil
    }

    static func enumerate(_ smc: SMCConnection) -> [String] {
        var out: [String] = []
        let n = smc.keyCount()
        for i in 0..<n {
            if let k = smc.key(at: i), let f = k.first, "TFVPI".contains(f) { out.append(k) }
        }
        return out
    }

    static func readAll(_ smc: SMCConnection, _ keys: [String]) -> [SensorReading] {
        var out: [SensorReading] = []
        for k in keys {
            guard let raw = smc.readRaw(k), let v = decode(type: raw.type, bytes: raw.bytes) else { continue }
            let c = Array(k)
            guard c.count == 4 else { continue }
            let isInt = raw.type.hasPrefix("ui")
            switch c[0] {
            case "T":
                guard !isInt, v > 0, v < 150 else { continue }
                var name = tempNames[k] ?? (tr("Temperatura") + " " + k)
                if c[1] == "C", c[3] == "C", let d = Int(String(c[2])), tempNames[k] == nil {
                    name = "CPU Core \(d + 1)"
                }
                out.append(SensorReading(id: k, name: name, value: v, unit: "°C", category: 0))
            case "F":
                guard k.hasSuffix("Ac"), let d = Int(String(c[1])), v >= 0, v < 20000 else { continue }
                out.append(SensorReading(id: k, name: tr("Ventola") + " \(d + 1)", value: v, unit: "RPM", category: 1))
            case "V":
                guard !isInt, v > 0, v < 30 else { continue }
                out.append(SensorReading(id: k, name: tr("Tensione") + " " + k, value: v, unit: "V", category: 2))
            case "P":
                guard !isInt, v > 0, v < 1000 else { continue }
                out.append(SensorReading(id: k, name: tr("Potenza") + " " + k, value: v, unit: "W", category: 3))
            case "I":
                guard !isInt, v > 0, v < 100 else { continue }
                out.append(SensorReading(id: k, name: tr("Corrente") + " " + k, value: v, unit: "A", category: 4))
            default:
                continue
            }
        }
        return coalesce(out)
    }

    /// Chiavi diverse spesso leggono lo stesso sensore (es. TC0D/TC0E/TC0F/TC0P su una sola CPU).
    /// Vengono fuse solo se appartengono alla stessa famiglia e riportano lo stesso valore.
    private static let cpuPackageAliases: Set<String> = [
        "TC0D", "TC0E", "TC0F", "TC0J", "TC0P", "TC0T", "TC0p", "TCXC", "TCXc"
    ]

    private static func familyKey(_ id: String) -> String {
        // Solo gli alias del package CPU vengono fusi. I core/diode (TC1C, TC1c…)
        // restano righe separate come in HWMonitorSMC2, anche se leggono lo stesso valore.
        cpuPackageAliases.contains(id) ? "cpuPackage" : id
    }

    private static func coalesce(_ input: [SensorReading]) -> [SensorReading] {
        var out: [SensorReading] = []
        var indexByKey: [String: Int] = [:]

        for r in input {
            guard r.category == 0 else { out.append(r); continue }
            let bucket = String(format: "%.1f", r.value)
            let key = familyKey(r.id) + "|" + bucket
            if let i = indexByKey[key] {
                if !out[i].aliases.contains(r.id) { out[i].aliases.append(r.id) }
            } else {
                var item = r
                // HWMonitor etichetta il gruppo di alias come "CPU Proximity".
                if familyKey(r.id) == "cpuPackage" { item.name = tr("CPU Proximity") }
                indexByKey[key] = out.count
                out.append(item)
            }
        }
        return out
    }
}

// MARK: - Ventole SuperIO via AMDRyzenCPUPowerManagement

/// Legge le ventole della scheda madre tramite lo UserClient di AMDRyzenCPUPowerManagement.kext.
/// I selettori 90-94 sono in sola lettura; 95-97 (override PWM) non vengono usati.
enum AMDSuperIOFans {
    struct Info {
        var name: String
        var rpm: UInt64
        var throttle: UInt64
        var autoMode: Bool
    }

    /// - Returns: (nome chip, ventole). `nil` se il kext non è presente o il chip non è supportato.
    static func read() -> (chip: String, fans: [Info])? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault,
                                              IOServiceMatching("AMDRyzenCPUPowerManagement"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(conn) }

        // 90: inizializza il driver SuperIO -> [found, chipID]
        var initResult = [UInt64](repeating: 0, count: 2)
        var initSize = MemoryLayout<UInt64>.size * 2
        guard IOConnectCallStructMethod(conn, 90, nil, 0, &initResult, &initSize) == KERN_SUCCESS,
              initResult[0] == 1 else { return nil }

        // 91: numero di ventole
        var count: UInt64 = 0
        var countSize = MemoryLayout<UInt64>.size
        guard IOConnectCallStructMethod(conn, 91, nil, 0, &count, &countSize) == KERN_SUCCESS,
              count > 0, count <= 32 else { return nil }
        let n = Int(count)

        // 92: etichette
        var names: [String] = []
        for i in 0..<n {
            var index = UInt64(i)
            var buf = [UInt8](repeating: 0, count: 128)
            var size = buf.count
            if IOConnectCallMethod(conn, 92, &index, 1, nil, 0, nil, nil, &buf, &size) == KERN_SUCCESS {
                names.append(String(cString: buf))
            } else {
                names.append("\(tr("Ventola")) \(i + 1)")
            }
        }

        // 93: RPM
        var rpms = [UInt64](repeating: 0, count: n)
        var rpmSize = rpms.count * MemoryLayout<UInt64>.size
        guard IOConnectCallStructMethod(conn, 93, nil, 0, &rpms, &rpmSize) == KERN_SUCCESS else { return nil }

        // 94: throttle PWM e modalità automatica
        var states = [UInt64](repeating: 0, count: n)
        var stateSize = states.count * MemoryLayout<UInt64>.size
        let statesOK = IOConnectCallStructMethod(conn, 94, nil, 0, &states, &stateSize) == KERN_SUCCESS

        let chip = "0x" + String(format: "%04x", initResult[1])
        let fans = (0..<n).map { i in
            Info(name: names[i], rpm: rpms[i],
                 throttle: statesOK ? states[i] >> 8 : 0,
                 autoMode: statesOK ? (states[i] & 1) != 0 : true)
        }
        return (chip, fans)
    }
}

// MARK: - Sorgenti aggiuntive (GPU, dischi)

/// Letture non disponibili tramite SMC: GPU da IOAccelerator, dischi da SMART.
enum ExtraSensors {

    /// Categorie: 5 ventole GPU, 6 temperature GPU, 7 temperature dischi.
    static func gpuReadings() -> [SensorReading] {
        let modelNames = IOReg.services(matching: "IOPCIDevice")
            .filter { ($0.properties.u32("class-code") ?? 0) >> 16 == 0x03 }
            .compactMap { $0.properties.str("model") }
            .filter { !$0.isEmpty }

        var out: [SensorReading] = []
        var seen = Set<String>()
        for entry in IOReg.services(matching: "IOAccelerator") {
            guard seen.insert(entry.name).inserted else { continue }   // due client per la stessa GPU
            let stats = (entry.properties["PerformanceStatistics"] as? [String: Any])
                ?? (entry.properties["PerformanceStatisticsAccum"] as? [String: Any])
            let index = seen.count - 1
            let label = index < modelNames.count ? modelNames[index] : entry.name
            let name = label.isEmpty ? tr("GPU") : label

            if let t = stat(stats, containing: "temperature"), t > 0, t < 150 {
                out.append(SensorReading(id: "GPU\(index)", name: tr("GPU") + " · " + name,
                                         value: t, unit: "°C", category: 6))
            }
            if let rpm = stat(stats, containing: "fan speed(rpm)") ?? stat(stats, containing: "fan speed"),
               rpm > 0, rpm < 50_000 {
                out.append(SensorReading(id: "GPUFAN\(index)", name: tr("Ventola GPU") + " · " + name,
                                         value: rpm, unit: "RPM", category: 5))
            }
            if let pct = stat(stats, containing: "fan speed(%)"), pct >= 0, pct <= 100 {
                out.append(SensorReading(id: "GPUFANPCT\(index)", name: tr("Ventola GPU") + " · " + name,
                                         value: pct, unit: "%", category: 5))
            }
            if let power = stat(stats, containing: "total power"), power >= 0, power < 2_000 {
                out.append(SensorReading(id: "GPUPWR\(index)", name: tr("Potenza") + " GPU · " + name,
                                         value: power, unit: "W", category: 6))
            }
            if let clock = stat(stats, containing: "core clock"), clock > 0, clock < 10_000 {
                out.append(SensorReading(id: "GPUCLK\(index)", name: tr("Clock core") + " · " + name,
                                         value: clock, unit: "MHz", category: 6))
            }
            if let clock = stat(stats, containing: "memory clock"), clock > 0, clock < 50_000 {
                out.append(SensorReading(id: "GPUMEMCLK\(index)", name: tr("Clock memoria") + " · " + name,
                                         value: clock, unit: "MHz", category: 6))
            }
            if let activity = stat(stats, containing: "gpu activity"), activity >= 0, activity <= 100 {
                out.append(SensorReading(id: "GPUACT\(index)", name: tr("Attività") + " GPU · " + name,
                                         value: activity, unit: "%", category: 6))
            }
        }
        return out
    }

    /// Legge la temperatura composita SMART dei dischi. Richiede `smartctl`, se installato.
    static func diskReadings() -> [SensorReading] {
        let tool = [
            "/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl", "/usr/local/sbin/smartctl",
            "/opt/local/bin/smartctl", "/opt/local/sbin/smartctl", "/usr/bin/smartctl"
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let tool else { return [] }

        let list = Shell.run("/usr/sbin/diskutil", ["list", "-plist"])
        guard let data = list.data(using: .utf8),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let plist = obj as? [String: Any],
              let entries = plist["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }

        // Escludi i container APFS sintetizzati e i dischi virtuali: puntano allo stesso hardware.
        let disks = entries.compactMap { entry -> String? in
            guard let id = entry["DeviceIdentifier"] as? String,
                  id.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
                  let content = entry["Content"] as? String, !content.isEmpty,
                  content != "Apple_APFS_Container",
                  !(entry["Virtual"] as? Bool ?? false) else { return nil }
            return id
        }

        var out: [SensorReading] = []
        for disk in disks {
            let text = Shell.run(tool, ["-a", "/dev/\(disk)"])
            // NVMe: "Temperature: N Celsius". SATA ATA: attributo SMART "194 Temperature_Celsius … N".
            let raw = firstCapture(text, pattern: #"(?im)^\s*Temperature:\s*([0-9]+(?:\.[0-9]+)?)"#)
                ?? firstCapture(text, pattern: #"(?im)^\s*\d+\s+Temperature_Celsius\s+.*?\s+([0-9]+)\s*$"#)
            guard let raw, let value = Double(raw), value > 0, value < 150 else { continue }
            let model = firstCapture(text,
                                     pattern: #"(?im)^\s*(?:Model Number|Device Model|Product):\s*(.+)$"#)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? disk
            out.append(SensorReading(id: disk, name: tr("Disco") + " · " + model,
                                     value: value, unit: "°C", category: 7))
        }
        return out
    }

    private static func stat(_ dict: [String: Any]?, containing: String) -> Double? {
        guard let dict else { return nil }
        for (key, value) in dict where key.localizedCaseInsensitiveContains(containing) {
            if let n = value as? NSNumber { return n.doubleValue }
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
        }
        return nil
    }

    private static func firstCapture(_ text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let range = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

@MainActor
final class SensorMonitor: ObservableObject {
    @Published var readings: [SensorReading] = []
    @Published var available = true
    @Published var loaded = false
    @Published var superIOChip: String?
    private var keys: [String] = []
    private var gpuReadings: [SensorReading] = []
    private var diskReadings: [SensorReading] = []
    private var fanReadings: [SensorReading] = []
    private var tick = 0
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        Task { await loop() }
    }

    func stop() { running = false }

    private func loop() async {
        while running {
            let known = keys
            // I dischi vengono interpellati ogni 5 cicli (circa 10 s): smartctl è più lento dell'SMC.
            let refreshDisks = tick % 5 == 0
            let result = await Task.detached(priority: .utility) { ()
                -> (Bool, [String], [SensorReading], [SensorReading], [SensorReading], [SensorReading], String?) in
                var smcOK = false
                var ks = known
                var base: [SensorReading] = []
                if let smc = SMCConnection() {
                    smcOK = true
                    if ks.isEmpty { ks = SensorReader.enumerate(smc) }
                    base = SensorReader.readAll(smc, ks)
                }
                let gpu = ExtraSensors.gpuReadings()
                let disks = refreshDisks ? ExtraSensors.diskReadings() : []
                var fans: [SensorReading] = []
                var chip: String?
                if let sio = AMDSuperIOFans.read() {
                    chip = sio.chip
                    fans = sio.fans.enumerated().map { i, f in
                        let mode = f.autoMode ? "Auto" : "PWM \(f.throttle)%"
                        return SensorReading(id: "SIO\(i)", name: "\(f.name) · \(mode)",
                                             value: Double(f.rpm), unit: "RPM", category: 1)
                    }
                }
                return (smcOK, ks, base, gpu, disks, fans, chip)
            }.value

            keys = result.1
            gpuReadings = result.3
            if refreshDisks { diskReadings = result.4 }
            fanReadings = result.5
            superIOChip = result.6
            readings = result.2 + gpuReadings + diskReadings + fanReadings
            available = (result.0 && !result.1.isEmpty) || !gpuReadings.isEmpty
                || !diskReadings.isEmpty || !fanReadings.isEmpty
            loaded = true
            tick += 1
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}

// MARK: - Pagina

struct SensorsView: View {
    @EnvironmentObject var mon: SensorMonitor
    @AppStorage(MenuBarSensorsData.storageKey) private var pinnedIDs = ""

    private let categories: [(Int, String, String, Color)] = [
        (0, tr("Temperature"), "thermometer", .red),
        (6, tr("GPU"), "display", .red),
        (7, tr("Dischi"), "internaldrive", .red),
        (1, tr("Ventole"), "fan", .cyan),
        (5, tr("Ventole GPU"), "fan", .cyan),
        (2, tr("Tensioni"), "bolt", .yellow),
        (3, tr("Potenza"), "powerplug", .orange),
        (4, tr("Corrente"), "bolt.horizontal", .purple),
    ]

    private func isTemperature(_ r: SensorReading) -> Bool { r.unit == "°C" }

    private func tempColor(_ v: Double) -> Color {
        if v >= 90 { return .red }
        if v >= 75 { return .orange }
        return .green
    }

    private func valueText(_ r: SensorReading) -> String {
        switch r.unit {
        case "RPM", "%", "MHz": return String(format: "%.0f", r.value) + " " + r.unit
        case "V", "A":          return String(format: "%.2f", r.value) + " " + r.unit
        default:                return String(format: "%.1f", r.value) + " " + r.unit
        }
    }

    private func emptyText(_ cat: Int) -> String {
        switch cat {
        case 1: return tr("Nessuna ventola di sistema rilevata") + ". "
            + tr("Servono VirtualSMC/SMCSuperIO o AMDRyzenCPUPowerManagement con un chip supportato.")
        case 6: return tr("Nessun dato GPU disponibile")
        case 7: return tr("Nessuna temperatura disco disponibile: installa smartctl per leggere lo SMART.")
        default: return ""
        }
    }

    private func row(_ r: SensorReading) -> some View {
        let pinned = MenuBarSensorsData.isSelected(r.id, in: pinnedIDs)
        return HStack(spacing: 10) {
            if pinned {
                Image(systemName: "menubar.rectangle")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .help(tr("Esposto nella barra dei menu"))
            }
            Text(r.name)
            Text(([r.id] + r.aliases).joined(separator: " · "))
                .font(.caption).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 240, alignment: .leading)
            Spacer()
            if isTemperature(r) {
                ProgressView(value: min(r.value, 110), total: 110)
                    .tint(tempColor(r.value))
                    .frame(width: 100)
            }
            Text(valueText(r))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isTemperature(r) ? tempColor(r.value) : Color.primary)
                .frame(minWidth: 90, alignment: .trailing)
        }
        .contextMenu {
            Button {
                MenuBarSensorsData.toggle(r.id, raw: &pinnedIDs)
            } label: {
                Label(
                    pinned ? tr("Rimuovi dalla barra dei menu") : tr("Aggiungi alla barra dei menu"),
                    systemImage: pinned ? "menubar.rectangle" : "plus"
                )
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if mon.loaded && !mon.available {
                    UnavailableView(title: tr("Nessun sensore SMC trovato"), systemImage: "thermometer",
                                    description: tr("Servono VirtualSMC e i plugin dei sensori (SMCProcessor, SMCSuperIO…)."))
                } else if !mon.loaded {
                    ProgressView().frame(maxWidth: .infinity)
                }
                ForEach(categories, id: \.0) { cat in
                    let items = mon.readings.filter { $0.category == cat.0 }
                    if !items.isEmpty {
                        Card(tr(cat.1), icon: cat.2, tint: cat.3) {
                            ForEach(items) { r in row(r) }
                            if cat.0 == 0 {
                                Text(tr("Chiavi SMC equivalenti con lo stesso valore sono raggruppate."))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            if cat.0 == 1, let chip = mon.superIOChip {
                                Text(tr("Chip SuperIO") + " \(chip) · " + tr("via AMDRyzenCPUPowerManagement"))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    } else if mon.loaded && [1, 6, 7].contains(cat.0) {
                        Card(tr(cat.1), icon: cat.2, tint: cat.3) {
                            Text(emptyText(cat.0)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear { mon.start() }
        // Il monitor resta attivo anche quando si cambia pagina: serve alla barra dei menu.
    }
}
