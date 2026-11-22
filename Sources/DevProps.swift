import Foundation

/// Legge il blob `device-properties` che OpenCore / Clover passano a macOS
/// (visibile in IODeviceTree:/efi). Il formato è quello di Apple:
///   intestazione | per ogni dispositivo: lunghezza, n. proprietà, device path, proprietà…
///   proprietà = lunghezza, nome UTF-16 terminato da 0, lunghezza dato, dato
/// Le lunghezze possono includere o no il proprio campo e l'intestazione può essere di 8 o 12 byte:
/// il parser prova le combinazioni e accetta solo quella che consuma i byte in modo esatto.
enum DevProps {
    private struct Reader {
        let d: [UInt8]
        var o = 0
        init(_ bytes: [UInt8]) { d = bytes }

        mutating func u8() -> Int? {
            guard o < d.count else { return nil }
            let v = Int(d[o])
            o += 1
            return v
        }
        mutating func u16() -> Int? {
            guard o + 2 <= d.count else { return nil }
            let v = Int(d[o]) | (Int(d[o + 1]) << 8)
            o += 2
            return v
        }
        mutating func u32() -> Int? {
            guard o + 4 <= d.count else { return nil }
            let v = Int(d[o]) | (Int(d[o + 1]) << 8) | (Int(d[o + 2]) << 16) | (Int(d[o + 3]) << 24)
            o += 4
            return v
        }
    }

    static func parse(_ data: Data) -> [DevicePropGroup]? {
        let bytes = [UInt8](data)
        for header in [12, 8] {
            for devIncl in [true, false] {
                for entIncl in [true, false] {
                    if let g = attempt(bytes, header: header, devIncl: devIncl, entIncl: entIncl), !g.isEmpty {
                        return g
                    }
                }
            }
        }
        return nil
    }

    private static func le32(_ b: [UInt8], _ at: Int) -> Int {
        Int(b[at]) | (Int(b[at + 1]) << 8) | (Int(b[at + 2]) << 16) | (Int(b[at + 3]) << 24)
    }

    private static func attempt(_ bytes: [UInt8], header: Int, devIncl: Bool, entIncl: Bool) -> [DevicePropGroup]? {
        guard bytes.count > header else { return nil }
        var r = Reader(bytes)
        guard let total = r.u32(), total >= header, total <= bytes.count else { return nil }
        r.o = header

        var groups: [DevicePropGroup] = []
        while r.o < total {
            let devStart = r.o
            guard let dlen = r.u32(), dlen >= 8 else { return nil }
            let devEnd = devIncl ? devStart + dlen : devStart + 4 + dlen
            guard devEnd <= total, devEnd > r.o else { return nil }
            guard r.u32() != nil else { return nil }           // numero di proprietà (non affidabile, ignorato)

            // Device path
            var nodes: [String] = []
            var pci: [(dev: Int, fn: Int)] = []
            var rootUID = -1
            var ended = false
            while r.o + 4 <= devEnd {
                guard let type = r.u8(), let sub = r.u8(), let len = r.u16(), len >= 4 else { return nil }
                let bodyStart = r.o
                let bodyLen = len - 4
                guard bodyStart + bodyLen <= devEnd else { return nil }
                if type == 0x7F && sub == 0xFF {
                    r.o = bodyStart + bodyLen
                    ended = true
                    break
                }
                if type == 2 && sub == 1 && bodyLen >= 8 {
                    let hid = le32(bytes, bodyStart)
                    let uid = le32(bytes, bodyStart + 4)
                    if hid == 0x0A0341D0 || hid == 0x080341D0 {
                        nodes.append("PciRoot(0x\(String(uid, radix: 16)))")
                        rootUID = uid
                    } else {
                        nodes.append("Acpi(0x\(String(hid, radix: 16)),0x\(String(uid, radix: 16)))")
                    }
                } else if type == 1 && sub == 1 && bodyLen >= 2 {
                    let fn = Int(bytes[bodyStart])
                    let dev = Int(bytes[bodyStart + 1])
                    nodes.append("Pci(0x\(String(dev, radix: 16)),0x\(String(fn, radix: 16)))")
                    pci.append((dev: dev, fn: fn))
                } else {
                    nodes.append("Node(\(type),\(sub))")
                }
                r.o = bodyStart + bodyLen
            }
            guard ended else { return nil }

            // Proprietà
            var rows: [PropertyRow] = []
            while r.o < devEnd {
                let eStart = r.o
                guard let elen = r.u32(), elen >= 4 else { return nil }
                let eEnd = entIncl ? eStart + elen : eStart + 4 + elen
                guard eEnd <= devEnd, eEnd > r.o else { return nil }

                var name: [UInt16] = []
                var terminated = false
                while r.o + 2 <= eEnd {
                    guard let c = r.u16() else { return nil }
                    if c == 0 { terminated = true; break }
                    name.append(UInt16(c))
                }
                guard terminated, r.u32() != nil, r.o <= eEnd else { return nil }
                let value = Data(bytes[r.o..<eEnd])
                rows.append(PropertyRow(key: String(decoding: name, as: UTF16.self), value: Fmt.data(value), raw: value))
                r.o = eEnd
            }
            guard r.o == devEnd else { return nil }

            var location = ""
            if pci.count == 1, rootUID == 0 {
                location = Fmt.hex(0, 2) + ":" + Fmt.hex(pci[0].dev, 2) + "." + String(pci[0].fn)
            }
            groups.append(DevicePropGroup(id: "\(groups.count):" + nodes.joined(separator: "/"),
                                          path: nodes.joined(separator: "/"),
                                          location: location,
                                          rows: rows))
        }
        return groups
    }
}
