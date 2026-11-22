import Foundation
import IOKit
import Metal
import VideoToolbox
import CoreMedia

typealias PCIPair = (dev: PCIDevice, entry: RegistryEntry)

enum Collector {
    static func collect() -> Snapshot {
        var s = Snapshot()
        s.system = system()
        s.cpu = cpu()

        let pcis = pciEntries()
        s.pci = pcis.map { $0.dev }
        s.gpus = pcis.filter { $0.dev.baseClass == 0x03 }.map { gpu($0.dev, $0.entry) }
        s.metalDevices = MTLCopyAllDevices().map { $0.name }
        s.codecs = [
            CodecInfo(id: "h264", name: "H.264 / AVC", supported: VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)),
            CodecInfo(id: "hevc", name: "HEVC / H.265", supported: VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)),
        ]
        s.audio = pcis.filter { $0.dev.baseClass == 0x04 }.map { p in
            AudioInfo(id: p.dev.id, name: p.dev.deviceName, vendor: p.dev.vendorName, location: p.dev.location,
                      layoutID: p.entry.properties.u32("layout-id").map { String($0) } ?? "",
                      driver: p.dev.drivers.first ?? "")
        }
        s.audioCodecs = audioCodecs()
        s.audioDevices = audioDevices()
        s.network = network()
        s.kexts = kexts()
        s.boot = boot()
        s.usb = usbControllers()
        s.memory = memoryModules()
        let acpiEntries = IOReg.services(matching: "IOACPIPlatformDevice")
        s.acpiDevices = Array(Set(acpiEntries.map { $0.name })).sorted()
        for e in acpiEntries {
            let hasLimits = e.properties["kUSBSleepPortCurrentLimit"] != nil || e.properties["kUSBWakePortCurrentLimit"] != nil
            if e.name == "USBX" || hasLimits {
                s.usbPower = e.name
                var parts: [String] = []
                for key in ["kUSBSleepPortCurrentLimit", "kUSBSleepPowerSupply", "kUSBWakePortCurrentLimit", "kUSBWakePowerSupply"] {
                    if let v = e.properties.int(key) { parts.append("\(key.dropFirst(4)) = \(v)") }
                }
                s.usbPowerDetail = parts.joined(separator: "  ·  ")
                break
            }
        }
        return s
    }

    // MARK: Sistema

    static func system() -> SystemInfo {
        let p = IOReg.services(matching: "IOPlatformExpertDevice").first?.properties ?? [:]
        var i = SystemInfo()
        i.model = Sysctl.string("hw.model") ?? p.str("model") ?? ""
        i.macOS = Sysctl.string("kern.osproductversion") ?? ProcessInfo.processInfo.operatingSystemVersionString
        i.build = Sysctl.string("kern.osversion") ?? ""
        i.kernel = (Sysctl.string("kern.ostype") ?? "Darwin") + " " + (Sysctl.string("kern.osrelease") ?? "")
        i.hostname = ProcessInfo.processInfo.hostName
        i.arch = Sysctl.string("hw.machine") ?? ""
        i.boardID = p.str("board-id") ?? ""
        i.serial = p.str("IOPlatformSerialNumber") ?? ""
        i.uuid = p.str("IOPlatformUUID") ?? ""
        i.manufacturer = p.str("manufacturer") ?? ""
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .abbreviated
        i.uptime = f.string(from: ProcessInfo.processInfo.systemUptime) ?? ""
        return i
    }

    static func cpu() -> CPUInfo {
        var c = CPUInfo()
        c.brand = Sysctl.string("machdep.cpu.brand_string") ?? Sysctl.string("hw.model") ?? ""
        c.vendor = Sysctl.string("machdep.cpu.vendor") ?? ""
        c.cores = Sysctl.int("machdep.cpu.core_count") ?? Sysctl.int("hw.physicalcpu") ?? 0
        c.threads = Sysctl.int("machdep.cpu.thread_count") ?? Sysctl.int("hw.logicalcpu") ?? 0
        c.family = Sysctl.int("machdep.cpu.family").map { String($0) } ?? ""
        c.model = Sysctl.int("machdep.cpu.model").map { String($0) } ?? ""
        c.stepping = Sysctl.int("machdep.cpu.stepping").map { String($0) } ?? ""
        let bf = ByteCountFormatter()
        if let l2 = Sysctl.int("hw.l2cachesize") { c.l2 = bf.string(fromByteCount: Int64(l2)) }
        if let l3 = Sysctl.int("hw.l3cachesize") { c.l3 = bf.string(fromByteCount: Int64(l3)) }
        if let m = Sysctl.int("hw.memsize") {
            let mf = ByteCountFormatter(); mf.countStyle = .memory
            c.ram = mf.string(fromByteCount: Int64(m))
        }
        let fam = Sysctl.int("machdep.cpu.family") ?? 0
        let mod = Sysctl.int("machdep.cpu.model") ?? 0
        let step = Sysctl.int("machdep.cpu.stepping") ?? 0
        c.microarch = microarch(vendor: c.vendor, family: fam, model: mod, stepping: step)
        c.generation = generation(c.brand)
        for key in ["machdep.cpu.features", "machdep.cpu.leaf7_features", "machdep.cpu.extfeatures"] {
            c.features += (Sysctl.string(key) ?? "").split(separator: " ").map(String.init)
        }
        return c
    }

    static func microarch(vendor: String, family: Int, model: Int, stepping: Int) -> String {
        if vendor.contains("Intel") && family == 6 {
            switch model {
            case 0x2A: return "Sandy Bridge"
            case 0x2D: return "Sandy Bridge-E"
            case 0x3A: return "Ivy Bridge"
            case 0x3E: return "Ivy Bridge-E"
            case 0x3C, 0x45, 0x46: return "Haswell"
            case 0x3F: return "Haswell-E"
            case 0x3D, 0x47: return "Broadwell"
            case 0x4F, 0x56: return "Broadwell-E"
            case 0x4E, 0x5E: return "Skylake"
            case 0x55: return stepping >= 5 ? "Cascade Lake" : "Skylake-X"
            case 0x8E:
                if stepping == 9 { return "Kaby Lake" }
                if stepping == 10 { return "Coffee Lake" }
                if stepping == 11 { return "Whiskey Lake" }
                return "Comet Lake"
            case 0x9E:
                if stepping == 9 { return "Kaby Lake" }
                if stepping <= 11 { return "Coffee Lake" }
                return "Coffee Lake Refresh"
            case 0xA5, 0xA6: return "Comet Lake"
            case 0x66: return "Cannon Lake"
            case 0x7D, 0x7E: return "Ice Lake"
            case 0x8C, 0x8D: return "Tiger Lake"
            case 0xA7: return "Rocket Lake"
            case 0x97, 0x9A: return "Alder Lake"
            case 0xB7, 0xBA, 0xBF: return "Raptor Lake"
            case 0xAA, 0xAC: return "Meteor Lake"
            case 0xC5, 0xC6: return "Arrow Lake"
            case 0xBD: return "Lunar Lake"
            default: return ""
            }
        }
        if vendor.contains("AMD") {
            switch family {
            case 0x17:
                if model == 0x01 || model == 0x11 { return "Zen" }
                if model == 0x08 || model == 0x18 { return "Zen+" }
                return "Zen 2"
            case 0x19: return model >= 0x60 ? "Zen 4" : "Zen 3"
            case 0x1A: return "Zen 5"
            default: return ""
            }
        }
        return ""
    }

    /// «9th Gen» ricavato dal nome del processore (es. i7-9750H, i9-12900K).
    static func generation(_ brand: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"i[3579]-(\d{4,5})"#),
              let m = re.firstMatch(in: brand, range: NSRange(brand.startIndex..., in: brand)),
              let r = Range(m.range(at: 1), in: brand),
              let n = Int(brand[r]) else { return "" }
        let g = n / 1000
        var suffix = "th"
        if g % 100 < 11 || g % 100 > 13 {
            switch g % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(g)\(suffix) Gen"
    }

    // MARK: Memoria

    static func jedecName(_ s: String) -> String {
        let h = s.lowercased().replacingOccurrences(of: "0x", with: "")
        let map = ["802c": "Micron", "80ad": "SK hynix", "80ce": "Samsung", "859b": "Crucial",
                   "029e": "Corsair", "9801": "Kingston", "0198": "Kingston", "04cd": "G.Skill"]
        return map[h] ?? s
    }

    static func memoryModules() -> [MemoryModule] {
        let out = Shell.run("/usr/sbin/system_profiler", ["SPMemoryDataType", "-json"])
        guard let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let top = obj["SPMemoryDataType"] as? [[String: Any]] else { return [] }
        var mods: [MemoryModule] = []
        for entry in top {
            let items = (entry["_items"] as? [[String: Any]]) ?? []
            for (i, it) in items.enumerated() {
                let size = it["dimm_size"] as? String ?? ""
                if size.isEmpty || size.lowercased().contains("empty") { continue }
                var m = MemoryModule(id: "\(mods.count)-\(i)")
                m.slot = it["_name"] as? String ?? "DIMM"
                m.size = size
                m.type = it["dimm_type"] as? String ?? ""
                m.speed = it["dimm_speed"] as? String ?? ""
                m.manufacturer = jedecName(it["dimm_manufacturer"] as? String ?? "")
                m.partNumber = (it["dimm_part_number"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                mods.append(m)
            }
        }
        return mods
    }

    // MARK: PCI

    static let linkSpeeds = [1: "2.5 GT/s", 2: "5 GT/s", 3: "8 GT/s", 4: "16 GT/s", 5: "32 GT/s", 6: "64 GT/s"]

    static func link(_ p: [String: Any]) -> String {
        guard let raw = p.int("IOPCIExpressLinkStatus") else { return "" }
        let st = raw > 0xFFFF ? raw >> 16 : raw
        var s = "x\((st >> 4) & 0x3F) @ \(linkSpeeds[st & 0xF] ?? "?")"
        if let cap = p.int("IOPCIExpressLinkCapabilities") {
            s += "  (max x\((cap >> 4) & 0x3F) @ \(linkSpeeds[cap & 0xF] ?? "?"))"
        }
        return s
    }

    // Percorsi in stile Hackintool, ricavati dal percorso IORegistry (es. /PCI0@0/RP21@1B,4/PXSX@0).
    static func pathComponents(_ path: String) -> [String] {
        var s = path
        if let r = s.range(of: ":/") { s = String(s[r.upperBound...]) }
        return s.split(separator: "/").map(String.init)
    }

    static func ioregName(_ path: String) -> String {
        "/" + pathComponents(path).dropFirst().joined(separator: "/")
    }

    static func devicePath(_ path: String) -> String {
        let comps = Array(pathComponents(path).dropFirst())
        guard let root = comps.first else { return "" }
        let uid = root.split(separator: "@").last.map(String.init) ?? "0"
        var out: [String] = ["PciRoot(0x\(uid.uppercased()))"]
        for comp in comps.dropFirst() {
            guard let at = comp.firstIndex(of: "@") else { continue }
            let parts = comp[comp.index(after: at)...].split(separator: ",")
            let dev = parts.first.flatMap { Int($0, radix: 16) } ?? 0
            let fn = parts.count > 1 ? (Int(parts[1], radix: 16) ?? 0) : 0
            out.append("Pci(0x\(String(dev, radix: 16).uppercased()),0x\(String(fn, radix: 16).uppercased()))")
        }
        return out.joined(separator: "/")
    }

    static func aspmText(_ p: [String: Any]) -> String {
        // "pci-aspm-default" reflects configured/default ASPM; if absent, treat as disabled
        // (matches common tools like Hackintool for devices without an explicit ASPM setting).
        let v = p.u32("pci-aspm-default") ?? 0
        switch v & 3 {
        case 0: return "Disabled"
        case 1: return "L0s"
        case 2: return "L1"
        default: return "L0s + L1"
        }
    }

    static func location(_ dbg: String?) -> String {
        guard let dbg else { return "" }
        let n = dbg.split(separator: ":").compactMap { Int($0) }
        guard n.count == 3 else { return dbg }
        return "\(Fmt.hex(n[0], 2)):\(Fmt.hex(n[1], 2)).\(n[2])"
    }

    static func pciEntries() -> [PCIPair] {
        let db = PCIIDDatabase.shared
        var result: [PCIPair] = []
        for e in IOReg.services(matching: "IOPCIDevice", childDepth: 4) {
            let p = e.properties
            guard let v = p.u32("vendor-id"), let d = p.u32("device-id") else { continue }
            var dev = PCIDevice(id: e.path, name: e.name)
            dev.vendorID = UInt16(truncatingIfNeeded: v)
            dev.deviceID = UInt16(truncatingIfNeeded: d)
            if let x = p.u32("subsystem-vendor-id") { dev.subVendorID = UInt16(truncatingIfNeeded: x) }
            if let x = p.u32("subsystem-id") { dev.subDeviceID = UInt16(truncatingIfNeeded: x) }
            if let x = p.u32("revision-id") { dev.revision = UInt8(truncatingIfNeeded: x) }
            dev.classCode = p.u32("class-code") ?? 0
            dev.vendorName = db.vendor(dev.vendorID) ?? tr("Sconosciuto") + " (0x\(Fmt.hex(dev.vendorID, 4)))"
            dev.deviceName = db.device(dev.vendorID, dev.deviceID) ?? p.str("model") ?? e.name
            dev.className = db.className(dev.classCode)
            dev.baseClassName = db.baseClassName(dev.classCode)
            dev.subclassName = db.subclassName(dev.classCode)
            dev.ioregName = ioregName(e.path)
            dev.ioName = p.str("IOName") ?? ""
            dev.devicePath = devicePath(e.path)
            dev.aspm = aspmText(p)
            dev.location = location(p.str("pcidebug"))
            dev.linkStatus = link(p)
            dev.acpiPath = p.str("acpi-path") ?? ""
            dev.builtIn = (p.u32("built-in") ?? 0) != 0
            dev.drivers = e.children.filter { $0.depth == 1 }.map { $0.className }
            dev.properties = p.keys.sorted().map { PropertyRow(key: $0, value: Fmt.describe(p[$0]!), raw: p[$0] as? Data) }
            result.append((dev, e))
        }
        return result.sorted { $0.dev.location < $1.dev.location }
    }

    // MARK: USB

    static func speedText(_ n: Int?) -> String {
        switch n {
        case 0: return "Low Speed (1.5 Mbps)"
        case 1: return "Full Speed (12 Mbps)"
        case 2: return "High Speed (480 Mbps)"
        case 3: return "SuperSpeed (5 Gbps)"
        case 4: return "SuperSpeed+ (10 Gbps)"
        case 5: return "SuperSpeed+ (20 Gbps)"
        default: return ""
        }
    }

    /// Controller xHCI/EHCI con le loro porte (nodi con UsbConnector) e il dispositivo collegato a ciascuna.
    static func usbControllers() -> [USBController] {
        let db = PCIIDDatabase.shared
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPCIDevice"), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }

        var out: [USBController] = []
        while case let raw = IOIteratorNext(it), raw != 0 {
            defer { IOObjectRelease(raw) }
            let p = IOReg.properties(raw)
            guard let cc = p.u32("class-code"), (cc >> 8) == 0x0C03,
                  let v = p.u32("vendor-id"), let d = p.u32("device-id") else { continue }
            let e = IOReg.make(raw, childDepth: 8)
            let vid = UInt16(truncatingIfNeeded: v)
            let did = UInt16(truncatingIfNeeded: d)

            var c = USBController(id: e.path)
            c.title = (db.device(vid, did) ?? e.name) + " (" + e.name + ")"
            c.vendor = db.vendor(vid) ?? ""
            c.idString = Fmt.hex(vid, 4) + ":" + Fmt.hex(did, 4)
            c.location = location(p.str("pcidebug"))

            let kids = e.children
            for i in 0..<kids.count {
                let k = kids[i]
                guard let conn = k.properties.int("UsbConnector") else { continue }
                var port = USBPort(id: "\(e.path)#\(i)")
                port.name = k.name
                port.number = Int(k.properties.u32("port") ?? 0)
                port.connector = conn

                // Il dispositivo collegato è il primo discendente con idVendor nel sottoalbero della porta.
                var j = i + 1
                while j < kids.count && kids[j].depth > k.depth {
                    let dp = kids[j].properties
                    if dp["idVendor"] != nil {
                        port.used = true
                        let vendor = dp.str("USB Vendor Name") ?? dp.str("kUSBVendorString") ?? ""
                        let product = dp.str("USB Product Name") ?? dp.str("kUSBProductString") ?? kids[j].name
                        port.deviceName = (vendor.isEmpty || product.hasPrefix(vendor)) ? product : vendor + " " + product
                        port.deviceID = Fmt.hex(dp.int("idVendor") ?? 0, 4) + ":" + Fmt.hex(dp.int("idProduct") ?? 0, 4)
                        port.speed = speedText(dp.int("Device Speed"))
                        break
                    }
                    j += 1
                }
                c.ports.append(port)
            }
            c.ports.sort { $0.name < $1.name }
            out.append(c)
        }
        return out
    }

    // MARK: GPU

    static func gpu(_ d: PCIDevice, _ e: RegistryEntry) -> GPUInfo {
        let all = [e] + e.children
        func prop(_ k: String) -> String {
            for x in all { if let v = x.properties[k] { return Fmt.describe(v) } }
            return ""
        }
        let accel = e.children.first { $0.properties["IOAccelIndex"] != nil || $0.className.hasSuffix("Accelerator") }
        var g = GPUInfo(id: d.id)
        g.name = d.deviceName
        g.vendor = d.vendorName
        g.pciID = d.idString
        if let sv = d.subVendorID, let sd = d.subDeviceID { g.subsystem = Fmt.hex(sv, 4) + ":" + Fmt.hex(sd, 4) }
        g.location = d.location
        g.link = d.linkStatus
        g.accelerator = accel?.className ?? ""
        g.metalPlugin = prop("MetalPluginName")
        g.gvaCodec = prop("IOGVACodec")
        g.hevcDecode = prop("IOGVAHEVCDecode")
        g.hevcEncode = prop("IOGVAHEVCEncode")
        g.platformID = e.properties.u32("AAPL,ig-platform-id").map { "0x" + Fmt.hex($0, 8) } ?? ""
        g.framebuffers = e.children.filter { $0.properties["IOFBDependentIndex"] != nil }.count
        return g
    }

    // MARK: Audio

    static func audioCodecs() -> [String] {
        let db = PCIIDDatabase.shared
        return IOReg.services(matching: "IOHDACodecDevice").compactMap { e in
            guard let v = e.properties.u32("IOHDACodecVendorID") else { return nil }
            let vendor = UInt16(truncatingIfNeeded: v >> 16)
            let dev = v & 0xFFFF
            let raw = "0x" + Fmt.hex(v, 8)
            if vendor == 0x10ec { return "Realtek ALC\(String(dev, radix: 16))  (\(raw))" }
            return "\(db.vendor(vendor) ?? "Codec") \(raw)"
        }
    }

    private static func fourCC(_ n: UInt32) -> String? {
        let b = [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        guard let s = String(bytes: b, encoding: .ascii) else { return nil }
        guard s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7f }) else { return nil }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func audioTransport(_ p: [String: Any], _ keys: [String], _ entry: RegistryEntry) -> String {
        for k in keys {
            if let s = p.str(k), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.caseInsensitiveCompare("usb") == .orderedSame { return "USB" }
                if t.caseInsensitiveCompare("bltn") == .orderedSame || t.caseInsensitiveCompare("builtin") == .orderedSame || t.caseInsensitiveCompare("built-in") == .orderedSame { return "Built-in" }
                if t.caseInsensitiveCompare("pci") == .orderedSame { return "PCI" }
                if t.caseInsensitiveCompare("hdmi") == .orderedSame { return "HDMI" }
                return t
            }
            if let n = p[k] as? NSNumber {
                let u = n.uint32Value
                if u != 0, let s = fourCC(u) {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.caseInsensitiveCompare("usb") == .orderedSame { return "USB" }
                    if t.caseInsensitiveCompare("bltn") == .orderedSame { return "Built-in" }
                    if t.caseInsensitiveCompare("pci") == .orderedSame { return "PCI" }
                    if t.caseInsensitiveCompare("hdmi") == .orderedSame || t.caseInsensitiveCompare("hdpn") == .orderedSame { return "HDMI" }
                    if t.caseInsensitiveCompare("virt") == .orderedSame { return "Virtual" }
                    if !t.isEmpty { return t }
                }
            }
            if let n = p.u32(k), n != 0, let s = fourCC(n) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.caseInsensitiveCompare("usb") == .orderedSame { return "USB" }
                if t.caseInsensitiveCompare("bltn") == .orderedSame { return "Built-in" }
                if !t.isEmpty { return t }
            }
        }
        let path = entry.path.lowercased()
        if path.contains("appleusbaudio") { return "USB" }
        if entry.className.lowercased().contains("usb") { return "USB" }
        return ""
    }

    private static func audioDevicesProfiler(excluding seen: inout Set<String>, seenNames: inout Set<String>) -> [AudioDeviceInfo] {
        let outStr = Shell.run("/usr/sbin/system_profiler", ["SPAudioDataType", "-json"])
        guard let data = outStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = obj["SPAudioDataType"] as? [[String: Any]] else { return [] }
        var result: [AudioDeviceInfo] = []
        func walk(_ items: [[String: Any]]) {
            for it in items {
                let name = (it["_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    let lname = name.lowercased()
                    // Skip generic placeholder names and devices already reported (e.g. from IORegistry)
                    if ["coreaudio_device", "coreaudio_input_device", "coreaudio_output_device"].contains(lname) {
                        if let sub = it["_items"] as? [[String: Any]] { walk(sub) }
                        continue
                    }
                    if seenNames.contains(lname) {
                        if let sub = it["_items"] as? [[String: Any]] { walk(sub) }
                        continue
                    }
                    var manufacturer = (it["coreaudio_device_manufacturer"] as? String ?? it["manufacturer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    var transport = (it["coreaudio_device_transport"] as? String ?? it["transport"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let tl = transport.lowercased()
                    if tl == "usb" { transport = "USB" }
                    else if tl == "builtin" || tl == "built-in" || tl == "bltn" || tl.contains("builtin") || tl.contains("built_in") { transport = "Built-in" }
                    else if tl == "pci" { transport = "PCI" }
                    else if tl == "hdmi" || tl == "hdpn" || tl.contains("hdmi") || tl.contains("displayport") { transport = "HDMI" }
                    if manufacturer == "(null)" { manufacturer = "" }
                    let key = "\(name)|\(manufacturer)|\(transport)".lowercased()
                    let loose = lname
                    let already = seen.contains(key) || seen.contains(where: { $0.hasPrefix(loose + "|") && ($0.hasSuffix("|" + transport.lowercased()) || transport.isEmpty) })
                    if !already && seen.insert(key).inserted {
                        var d = AudioDeviceInfo(id: "sp:\(name)")
                        d.name = name
                        d.manufacturer = manufacturer
                        d.transport = transport
                        d.source = "system_profiler"
                        result.append(d)
                        seenNames.insert(lname)
                    }
                }
                if let sub = it["_items"] as? [[String: Any]] { walk(sub) }
            }
        }
        walk(root)
        return result
    }

    static func audioDevices() -> [AudioDeviceInfo] {
        var out: [AudioDeviceInfo] = []
        var seen = Set<String>()
        var seenNames = Set<String>()
        for cls in ["IOAudioDevice", "IOAudioEngine", "AppleUSBAudioDevice", "AppleUSBAudioEngine"] {
            for e in IOReg.services(matching: cls) {
                let p = e.properties
                let name = (p.str("IOAudioDeviceName")
                    ?? p.str("IOAudioEngineDescription")
                    ?? p.str("USB Product Name")
                    ?? p.str("name")
                    ?? e.name).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { continue }
                let manufacturer = (p.str("IOAudioDeviceManufacturerName")
                    ?? p.str("IOAudioEngineManufacturerName")
                    ?? p.str("USB Vendor Name")
                    ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                var transport = audioTransport(p, ["IOAudioDeviceTransportType", "IOAudioEngineTransportType"], e)
                if transport.isEmpty {
                    let path = e.path.lowercased()
                    if path.contains("appleusbaudio") || path.contains("/usb") || e.className.lowercased().contains("usb") { transport = "USB" }
                }
                let key = "\(name)|\(manufacturer)|\(transport)".lowercased()
                guard seen.insert(key).inserted else { continue }
                var d = AudioDeviceInfo(id: e.path)
                d.name = name
                d.manufacturer = manufacturer
                d.transport = transport
                d.source = "IORegistry"
                out.append(d)
                seenNames.insert(name.lowercased())
            }
        }
        out.append(contentsOf: audioDevicesProfiler(excluding: &seen, seenNames: &seenNames))
        return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: Rete

    static func network() -> [NetIface] {
        var ports: [String: String] = [:]
        var curPort = ""
        for line in Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"]).split(separator: "\n") {
            if line.hasPrefix("Hardware Port:") { curPort = line.dropFirst(14).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("Device:") { ports[line.dropFirst(7).trimmingCharacters(in: .whitespaces)] = curPort }
        }
        var out: [NetIface] = []
        for e in IOReg.services(matching: "IONetworkInterface") {
            guard let bsd = e.properties.str("BSD Name"), bsd.hasPrefix("en") else { continue }
            var n = NetIface(id: bsd)
            n.bsd = bsd
            n.port = ports[bsd] ?? ""
            n.builtIn = e.properties.bool("IOBuiltin") ?? false
            if let d = e.properties["IOMACAddress"] as? Data {
                n.mac = d.map { Fmt.hex($0, 2) }.joined(separator: ":")
            }
            n.controller = e.parentClass
            n.ip = Shell.run("/usr/sbin/ipconfig", ["getifaddr", bsd]).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(n)
        }
        return out.sorted { $0.bsd < $1.bsd }
    }

    // MARK: Kext

    static func kexts() -> [KextInfo] {
        var out = Shell.run("/usr/bin/kmutil", ["showloaded"])
        if out.isEmpty { out = Shell.run("/usr/sbin/kextstat", ["-l"]) }
        guard let re = try? NSRegularExpression(pattern: #"\s([A-Za-z0-9_.\-]+)\s\(([^)\s]+)\)"#) else { return [] }
        var seen = Set<String>()
        var list: [KextInfo] = []
        for line in out.split(separator: "\n") {
            let s = String(line)
            guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s) else { continue }
            let id = String(s[r1])
            guard id.contains("."), !id.hasPrefix("com.apple."), seen.insert(id).inserted else { continue }
            list.append(KextInfo(id: id, version: String(s[r2])))
        }
        return list.sorted { $0.id.lowercased() < $1.id.lowercased() }
    }

    // MARK: Boot

    static var sipFlags: [(UInt32, String)] { [
        (0x1, tr("Kext non firmate")), (0x2, tr("File system senza restrizioni")), (0x4, "task_for_pid"),
        (0x8, tr("Debug kernel")), (0x10, "Apple Internal"), (0x20, "DTrace"), (0x40, tr("NVRAM senza restrizioni")),
        (0x80, tr("Configurazione dispositivi")), (0x100, tr("Qualsiasi Recovery OS")), (0x200, tr("Kext non approvate")),
        (0x400, "Override Executable Policy"), (0x800, tr("Root non autenticato")),
    ] }

    static func asString(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let d = v as? Data { return Fmt.cString(d, minLength: 1) }
        return nil
    }

    static func parseOpenCore(_ s: String) -> String {
        let parts = s.split(separator: "-")
        guard parts.count >= 2, parts[1].count == 3 else { return s }
        let v = Array(parts[1])
        let kind = ["REL": "Release", "DBG": "Debug", "NOO": "NOOPT"][String(parts[0])] ?? String(parts[0])
        let date = parts.count >= 5 ? " (\(parts[2])-\(parts[3])-\(parts[4]))" : ""
        return "\(v[0]).\(v[1]).\(v[2]) \(kind)\(date)"
    }

    /// Cerca una variabile NVRAM nell'output di `nvram -p` (formato: chiave<TAB>valore).
    static func nvramEntry(_ text: String, suffix: String) -> (key: String, value: String)? {
        let wanted = suffix.lowercased()
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let key = String(line[line.startIndex..<tab])
            if key.lowercased().hasSuffix(wanted) {
                let value = String(line[line.index(after: tab)...]).trimmingCharacters(in: .whitespaces)
                return (key, value)
            }
        }
        return nil
    }

    /// Legge una variabile del GUID di OpenCore/Clover direttamente con `nvram`.
    static func directNvram(_ name: String) -> String? {
        let r = Shell.runFull("/usr/sbin/nvram", ["4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:" + name])
        guard r.status == 0, let tab = r.out.firstIndex(of: "\t") else { return nil }
        let v = String(r.out[r.out.index(after: tab)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    static func boot() -> BootInfo {
        var b = BootInfo()
        var signals: [String] = []
        let opt = IOReg.entry(atPath: "IODeviceTree:/options")?.properties ?? [:]
        let efi = IOReg.entry(atPath: "IODeviceTree:/efi")?.properties ?? [:]
        b.nvram = Shell.run("/usr/sbin/nvram", ["-p"])

        // 1) OpenCore: versione esposta nelle variabili EFI (Misc → Security → ExposeSensitiveData)
        if let kv = opt.first(where: { $0.key.lowercased().hasSuffix("opencore-version") }) {
            b.loader = "OpenCore"
            b.loaderVersion = asString(kv.value).map { parseOpenCore($0) } ?? Fmt.describe(kv.value)
            b.loaderSource = tr("Variabili EFI (IORegistry)")
            signals.append(tr("Trovata la variabile opencore-version in IODeviceTree:/options"))
        } else if let hit = nvramEntry(b.nvram, suffix: "opencore-version") {
            b.loader = "OpenCore"
            b.loaderVersion = parseOpenCore(hit.value)
            b.loaderSource = "nvram -p"
            signals.append(tr("Trovata la variabile opencore-version con nvram -p"))
        } else if let v = directNvram("opencore-version") {
            b.loader = "OpenCore"
            b.loaderVersion = parseOpenCore(v)
            b.loaderSource = "nvram"
            signals.append(tr("Trovata la variabile opencore-version con nvram diretto"))
        } else {
            signals.append(tr("Variabile opencore-version assente"))
        }
        let guidLines = b.nvram.split(separator: "\n").filter { $0.uppercased().contains("4D1FDA02") }.count
        signals.append("IODeviceTree:/options: \(opt.count) " + tr("proprietà") + "  ·  nvram -p: \(guidLines) " + tr("variabili OpenCore/Clover (GUID 4D1FDA02)"))

        // 2) Clover: variabili NVRAM «Clover.*» / clovergui-revision
        if b.loader.isEmpty {
            if let kv = opt.first(where: { $0.key.lowercased().contains("clover") }) {
                b.loader = "Clover"
                b.loaderSource = tr("Variabili EFI (IORegistry)")
                signals.append(tr("Trovata una variabile NVRAM di Clover") + ": " + kv.key)
            } else if b.nvram.lowercased().contains("clover") {
                b.loader = "Clover"
                b.loaderSource = "nvram -p"
                signals.append(tr("Trovata una variabile NVRAM di Clover"))
            }
            if b.loader == "Clover", let kv = opt.first(where: { $0.key.lowercased().contains("clovergui-revision") }) {
                let d = [kv.key: kv.value]
                b.loaderVersion = d.u32(kv.key).map { "r\($0)" } ?? Fmt.describe(kv.value)
            }
        }

        // 3) OpenCore: variabili oem-* (bit 0x4 di ExposeSensitiveData, anche senza la versione)
        if b.loader.isEmpty {
            let oem = ["oem-vendor", "oem-product", "oem-board", "boot-path"]
            var found = false
            for k in opt.keys {
                let low = k.lowercased()
                if oem.contains(where: { low.hasSuffix($0) }) { found = true }
            }
            for line in b.nvram.split(separator: "\n") {
                let low = line.lowercased()
                if oem.contains(where: { low.contains("4d1fda02-38c7-4a6a-9cc6-4bcca8b30102:" + $0) }) { found = true }
            }
            if found {
                b.loader = "OpenCore"
                b.loaderSource = tr("Variabili EFI (IORegistry)")
                signals.append(tr("Trovate variabili oem-* di OpenCore"))
            }
        }

        // 4) Firmware vendor dichiarato nel nodo EFI
        if let data = efi["firmware-vendor"] as? Data, let text = String(data: data, encoding: .utf16LittleEndian) {
            let vendor = text.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            if !vendor.isEmpty {
                signals.append("Firmware vendor: " + vendor)
                if b.loader.isEmpty, vendor.lowercased().contains("clover") {
                    b.loader = "Clover"
                    b.loaderSource = "Firmware vendor"
                }
            }
        }

        // 5) Contenuto delle partizioni EFI già montate (OpenCore/Clover presenti sul disco)
        var mountedEFI = 0
        var hintLoader = ""
        var hintPart = ""
        for g in DiskUtil.list() {
            for p in g.parts where p.mounted && !p.isSystemMount {
                if p.isEFI { mountedEFI += 1 }
                if b.configSource.isEmpty, p.expose != nil || p.xhci != nil {
                    b.xhciPortLimit = p.xhci
                    b.configSource = p.id
                }
                if let ex = p.expose {
                    signals.append("config.plist (" + p.id + "): ExposeSensitiveData = \(ex)")
                    if ex & 2 == 0 {
                        signals.append(tr("La versione di OpenCore non è esposta: imposta Misc → Security → ExposeSensitiveData a 6 nel config.plist."))
                    }
                }
                for h in p.hints {
                    signals.append(h + ": " + tr("trovato nella EFI montata") + " (" + p.id + ")")
                    if hintLoader.isEmpty { hintLoader = h; hintPart = p.id }
                }
            }
        }
        if b.loader.isEmpty, !hintLoader.isEmpty {
            b.loader = hintLoader
            b.loaderSource = tr("Contenuto della EFI montata") + " (" + hintPart + ")"
        }
        if hintLoader.isEmpty {
            signals.append(tr("Nessuna cartella EFI/OC o EFI/CLOVER nei volumi montati: monta la EFI da «Archiviazione» (va bene anche una partizione FAT32 normale)"))
        }
        if b.loader.isEmpty { signals.append(tr("Nessun segnale di OpenCore o Clover trovato")) }

        // Log di boot, argomenti, SIP
        if let kv = opt.first(where: { $0.key.hasSuffix(":boot-log") }), let d = kv.value as? Data {
            b.bootLog = String(decoding: d.prefix(400_000), as: UTF8.self)
        }
        b.bootArgs = Sysctl.string("kern.bootargs") ?? asString(opt["boot-args"]) ?? ""
        b.sipStatus = Shell.run("/usr/bin/csrutil", ["status"]).split(separator: "\n").first.map(String.init) ?? ""
        if let csr = opt.u32("csr-active-config") {
            b.csrHex = "0x" + Fmt.hex(csr, 8)
            b.csrFlags = sipFlags.filter { csr & $0.0 != 0 }.map { $0.1 }
        }

        // Device Properties iniettate dal bootloader
        if let blob = efi["device-properties"] as? Data {
            if let groups = DevProps.parse(blob) {
                b.deviceProps = groups
            } else {
                b.devicePropsNote = tr("Device properties presenti ma in un formato non riconosciuto") + " (\(blob.count) " + tr("byte") + ")"
            }
        } else {
            b.devicePropsNote = tr("Nessuna device property trovata in IODeviceTree:/efi.")
        }

        b.signals = signals
        return b
    }

    // MARK: Controlli rapidi

    static func checks(_ s: Snapshot) -> [Check] {
        var c: [Check] = []
        let loaded = s.kexts.map { $0.id.lowercased() }
        func has(_ k: String) -> Bool { loaded.contains { $0.contains(k) } }

        if s.boot.loader.isEmpty {
            c.append(Check(title: "Bootloader", detail: tr("Nessun OpenCore/Clover rilevato: vedi «Boot e SIP» per la diagnostica"), status: .info))
        } else {
            c.append(Check(title: "Bootloader", detail: "\(s.boot.loader) \(s.boot.loaderVersion)", status: .ok))
        }

        let sip = s.boot.sipStatus.lowercased()
        if sip.contains("enabled") && !sip.contains("custom") {
            c.append(Check(title: "SIP", detail: tr("Attivo"), status: .ok))
        } else {
            c.append(Check(title: "SIP", detail: s.boot.sipStatusDisplay.isEmpty ? tr("Stato non leggibile") : s.boot.sipStatusDisplay, status: .warn))
        }

        if s.metalDevices.isEmpty {
            c.append(Check(title: "Metal", detail: tr("Nessun dispositivo Metal: accelerazione grafica non attiva"), status: .fail))
        } else {
            c.append(Check(title: "Metal", detail: s.metalDevices.joined(separator: ", "), status: .ok))
        }

        for k in s.codecs {
            c.append(Check(title: tr("Decodifica hardware") + " \(k.name)", detail: k.supported ? tr("Supportata") : tr("Non supportata"), status: k.supported ? .ok : .warn))
        }

        if let en0 = s.network.first(where: { $0.bsd == "en0" }) {
            c.append(Check(title: "Ethernet en0",
                           detail: en0.builtIn ? tr("Interfaccia built-in") : tr("en0 non è «built-in»: iMessage, FaceTime e iCloud possono dare problemi"),
                           status: en0.builtIn ? .ok : .warn))
        } else {
            c.append(Check(title: "Ethernet en0", detail: tr("Nessuna interfaccia en0 trovata"), status: .warn))
        }

        let acpi = Set(s.acpiDevices)
        c.append(Check(title: "ACPI EC", detail: acpi.contains("EC") || acpi.contains("H_EC") ? tr("Device EC presente") : tr("Device EC non trovato (SSDT-EC)"),
                       status: acpi.contains("EC") || acpi.contains("H_EC") ? .ok : .warn))

        c.append(Check(title: "Lilu / WhateverGreen", detail: "Lilu \(has("lilu") ? "✓" : "✗")  ·  WhateverGreen \(has("whatevergreen") ? "✓" : "✗")",
                       status: has("lilu") ? .ok : .info))
        c.append(Check(title: tr("Kext non Apple caricate"), detail: "\(s.kexts.count)", status: .info))
        return c
    }
}
