import Foundation

/// Parser del file pci.ids (PCI ID Repository). Usa la copia aggiornata in Application Support,
/// altrimenti quella inclusa nell'app.
final class PCIIDDatabase: @unchecked Sendable {
    static let shared = PCIIDDatabase()

    private let lock = NSLock()
    private var vendors: [UInt16: String] = [:]
    private var devices: [UInt32: String] = [:]
    private var classes: [UInt8: String] = [:]
    private var subclasses: [UInt16: String] = [:]
    private(set) var sourcePath = ""

    static var userFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HackCheck/pci.ids")
    }

    init() { load() }

    func load() {
        var path = Self.userFile.path
        if !FileManager.default.fileExists(atPath: path) {
            path = Bundle.main.path(forResource: "pci", ofType: "ids") ?? ""
        }
        guard !path.isEmpty, let data = FileManager.default.contents(atPath: path) else { return }
        parse(String(decoding: data, as: UTF8.self), source: path)
    }

    private static func split(_ s: Substring, _ width: Int) -> (UInt32, String)? {
        guard s.count > width, let id = UInt32(s.prefix(width), radix: 16) else { return nil }
        return (id, s.dropFirst(width).trimmingCharacters(in: .whitespaces))
    }

    private func parse(_ text: String, source: String) {
        var v: [UInt16: String] = [:]
        var d: [UInt32: String] = [:]
        var c: [UInt8: String] = [:]
        var sc: [UInt16: String] = [:]
        var curVendor: UInt32 = 0
        var curClass: UInt32 = 0
        var inClasses = false

        text.enumerateLines { line, _ in
            guard let first = line.first, first != "#" else { return }
            if line.hasPrefix("\t\t") { return }
            if line.hasPrefix("\t") {
                let rest = line.dropFirst()
                if inClasses {
                    if let (id, name) = Self.split(rest, 2) { sc[UInt16(truncatingIfNeeded: curClass << 8 | id)] = name }
                } else if let (id, name) = Self.split(rest, 4) {
                    d[curVendor << 16 | id] = name
                }
                return
            }
            if line.hasPrefix("C ") {
                inClasses = true
                if let (id, name) = Self.split(line.dropFirst(2), 2) {
                    curClass = id
                    c[UInt8(truncatingIfNeeded: id)] = name
                }
                return
            }
            if !inClasses, let (id, name) = Self.split(Substring(line), 4) {
                curVendor = id
                v[UInt16(truncatingIfNeeded: id)] = name
            }
        }

        lock.lock()
        vendors = v; devices = d; classes = c; subclasses = sc; sourcePath = source
        lock.unlock()
    }

    func vendor(_ id: UInt16) -> String? {
        lock.lock(); defer { lock.unlock() }
        return vendors[id]
    }

    func device(_ vendor: UInt16, _ device: UInt16) -> String? {
        lock.lock(); defer { lock.unlock() }
        return devices[UInt32(vendor) << 16 | UInt32(device)]
    }

    func className(_ code: UInt32) -> String {
        lock.lock(); defer { lock.unlock() }
        let cls = UInt8((code >> 16) & 0xFF)
        let key = UInt16((code >> 8) & 0xFFFF)
        return subclasses[key] ?? classes[cls] ?? tr("Classe") + " 0x" + Fmt.hex(code >> 8, 4)
    }

    func baseClassName(_ code: UInt32) -> String {
        lock.lock(); defer { lock.unlock() }
        return classes[UInt8((code >> 16) & 0xFF)] ?? ""
    }

    func subclassName(_ code: UInt32) -> String {
        lock.lock(); defer { lock.unlock() }
        return subclasses[UInt16((code >> 8) & 0xFFFF)] ?? ""
    }

    func update() async throws {
        let url = URL(string: "https://pci-ids.ucw.cz/v2.2/pci.ids")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 100_000 else {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.createDirectory(at: Self.userFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: Self.userFile, options: .atomic)
        load()
    }
}
