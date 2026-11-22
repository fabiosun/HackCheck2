import Foundation
import IOKit

// MARK: - Shell

enum Shell {
    static func run(_ path: String, _ args: [String] = []) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Come `run`, ma restituisce anche stato di uscita e stderr (serve per diskutil / osascript).
    static func runFull(_ path: String, _ args: [String] = []) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let o = Pipe()
        let e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { return (-1, "", error.localizedDescription) }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: od, as: UTF8.self), String(decoding: ed, as: UTF8.self))
    }
}

// MARK: - sysctl

enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func int(_ name: String) -> Int? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        if size == 4 {
            var v: Int32 = 0
            guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
            return Int(v)
        }
        if size == 8 {
            var v: Int64 = 0
            guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
            return Int(v)
        }
        return nil
    }
}

// MARK: - Formattazione

enum Fmt {
    static func hex<T: BinaryInteger>(_ v: T, _ width: Int) -> String {
        let s = String(v, radix: 16)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    /// Stringa C se il Data contiene solo ASCII stampabile.
    static func cString(_ d: Data, minLength: Int = 3) -> String? {
        var bytes = Array(d)
        while bytes.last == 0 { bytes.removeLast() }
        guard bytes.count >= minLength, bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func data(_ d: Data) -> String {
        if let s = cString(d) { return s }
        let shown = d.prefix(64).map { hex($0, 2) }.joined(separator: " ")
        if d.isEmpty { return tr("(vuoto)") }
        if d.count <= 4 {
            var v: UInt64 = 0
            for (i, b) in d.enumerated() { v |= UInt64(b) << UInt64(8 * i) }
            return "\(shown)  (\(v))"
        }
        return d.count > 64 ? "\(shown) … (\(d.count) " + tr("byte") + ")" : shown
    }

    static func describe(_ v: Any) -> String {
        switch v {
        case let d as Data: return data(d)
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? tr("Sì") : "No" }
            return n.stringValue
        case let a as [Any]: return "[" + a.map { describe($0) }.joined(separator: ", ") + "]"
        case let d as [String: Any]:
            return "{" + d.keys.sorted().map { "\($0) = \(describe(d[$0]!))" }.joined(separator: ", ") + "}"
        default: return "\(v)"
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func u32(_ k: String) -> UInt32? {
        if let d = self[k] as? Data, !d.isEmpty {
            var v: UInt32 = 0
            for (i, b) in d.prefix(4).enumerated() { v |= UInt32(b) << UInt32(8 * i) }
            return v
        }
        if let n = self[k] as? NSNumber { return n.uint32Value }
        return nil
    }
    func int(_ k: String) -> Int? { (self[k] as? NSNumber)?.intValue }
    func bool(_ k: String) -> Bool? { (self[k] as? NSNumber)?.boolValue }
    func str(_ k: String) -> String? {
        if let s = self[k] as? String { return s }
        if let d = self[k] as? Data { return Fmt.cString(d, minLength: 1) }
        return nil
    }
}

// MARK: - IORegistry

struct RegistryEntry {
    var name = ""
    var className = ""
    var path = ""
    var parentName = ""
    var parentClass = ""
    var properties: [String: Any] = [:]
    var children: [RegistryEntry] = []
    var depth = 0
}

enum IOReg {
    private static func cstr(_ cap: Int, _ fill: (UnsafeMutablePointer<CChar>) -> Void) -> String {
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: cap)
        buf.initialize(repeating: 0, count: cap)
        defer { buf.deallocate() }
        fill(buf)
        return String(cString: buf)
    }

    static func properties(_ e: io_registry_entry_t) -> [String: Any] {
        var ref: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(e, &ref, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let cf = ref?.takeRetainedValue() else { return [:] }
        return unsafeBitCast(cf, to: NSDictionary.self) as? [String: Any] ?? [:]
    }

    static func make(_ e: io_registry_entry_t, childDepth: Int = 0) -> RegistryEntry {
        var r = RegistryEntry()
        r.name = cstr(128) { _ = IORegistryEntryGetName(e, $0) }
        r.className = cstr(128) { _ = IOObjectGetClass(e, $0) }
        r.path = cstr(512) { _ = IORegistryEntryGetPath(e, kIOServicePlane, $0) }
        r.properties = properties(e)
        var parent: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(e, kIOServicePlane, &parent) == KERN_SUCCESS {
            r.parentName = cstr(128) { _ = IORegistryEntryGetName(parent, $0) }
            r.parentClass = cstr(128) { _ = IOObjectGetClass(parent, $0) }
            IOObjectRelease(parent)
        }
        if childDepth > 0 { r.children = descendants(of: e, depth: 1, max: childDepth) }
        return r
    }

    static func descendants(of e: io_registry_entry_t, depth: Int, max: Int) -> [RegistryEntry] {
        guard depth <= max else { return [] }
        var it: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(e, kIOServicePlane, &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var out: [RegistryEntry] = []
        while case let c = IOIteratorNext(it), c != 0 {
            var r = make(c)
            r.depth = depth
            out.append(r)
            out += descendants(of: c, depth: depth + 1, max: max)
            IOObjectRelease(c)
        }
        return out
    }

    static func services(matching cls: String, childDepth: Int = 0) -> [RegistryEntry] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var out: [RegistryEntry] = []
        while case let e = IOIteratorNext(it), e != 0 {
            out.append(make(e, childDepth: childDepth))
            IOObjectRelease(e)
        }
        return out
    }

    static func entry(atPath path: String) -> RegistryEntry? {
        let e = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard e != 0 else { return nil }
        defer { IOObjectRelease(e) }
        return make(e)
    }
}
