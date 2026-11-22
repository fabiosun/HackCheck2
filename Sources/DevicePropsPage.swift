import SwiftUI

struct ExportGroup: Identifiable {
    var id: String
    var title: String
    var path: String
    var rows: [PropertyRow]
}

enum DevPropsExport {
    static func isCustomKey(_ k: String) -> Bool {
        k == "built-in" || k == "layout-id" || k == "alc-layout-id" || k.hasPrefix("AAPL,") || k.hasPrefix("framebuffer-")
    }

    /// Gruppi da mostrare/esportare. Se il blob `device-properties` è leggibile si usa quello,
    /// altrimenti si ricostruisce una stima dalle proprietà tipiche viste sui dispositivi PCI (solo bus 0).
    static func groups(_ snap: Snapshot) -> (groups: [ExportGroup], fromBlob: Bool) {
        var out: [ExportGroup] = []
        for g in snap.boot.deviceProps {
            var title = g.path
            if !g.location.isEmpty, let d = snap.pci.first(where: { $0.location == g.location }) { title = d.deviceName }
            out.append(ExportGroup(id: g.id, title: title, path: g.path, rows: g.rows))
        }
        if !out.isEmpty { return (out, true) }

        for d in snap.pci {
            let parts = d.location.split(whereSeparator: { $0 == ":" || $0 == "." }).map(String.init)
            guard parts.count == 3, parts[0] == "00",
                  let dev = Int(parts[1], radix: 16), let fn = Int(parts[2]) else { continue }
            let rows = d.properties.filter { isCustomKey($0.key) }
            if rows.isEmpty { continue }
            let path = "PciRoot(0x0)/Pci(0x\(String(dev, radix: 16)),0x\(fn))"
            out.append(ExportGroup(id: d.id, title: d.deviceName, path: path, rows: rows))
        }
        return (out, false)
    }

    /// Plist nel formato di OpenCore: DeviceProperties → Add → { percorso: { chiave: valore } }.
    static func plist(_ groups: [ExportGroup]) -> Data? {
        var add: [String: Any] = [:]
        for g in groups {
            var dict = (add[g.path] as? [String: Any]) ?? [:]
            for r in g.rows {
                if let raw = r.raw { dict[r.key] = raw } else { dict[r.key] = r.value }
            }
            add[g.path] = dict
        }
        let root: [String: Any] = ["DeviceProperties": ["Add": add]]
        return try? PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }
}

struct DevicePropsPage: View {
    @EnvironmentObject var store: Store
    @State private var exportFailed = false

    var body: some View {
        let r = DevPropsExport.groups(store.snap)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("Elenco delle Device Properties iniettate dal bootloader. L'esportazione usa il formato di config.plist (DeviceProperties → Add)."))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button { export(r.groups) } label: {
                        Label(tr("Esporta .plist…"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(r.groups.isEmpty)
                    Text("\(r.groups.count) " + tr("dispositivi")).foregroundStyle(.secondary)
                    Spacer()
                }

                if exportFailed {
                    Label(tr("Esportazione non riuscita"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                }
                if !r.fromBlob && !r.groups.isEmpty {
                    Text(tr("Il blob device-properties non è disponibile: elenco ricavato dalle proprietà viste sui dispositivi PCI (solo bus 0)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if r.groups.isEmpty {
                    UnavailableView(title: tr("Nessuna device property da esportare"), systemImage: "slider.horizontal.3",
                                    description: store.snap.boot.devicePropsNote)
                }

                ForEach(r.groups) { g in
                    Card(g.title, icon: "slider.horizontal.3") {
                        Text(g.path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        ForEach(g.rows) { row in
                            HStack(alignment: .top) {
                                Text(row.key).foregroundStyle(.secondary).frame(width: 180, alignment: .leading)
                                Text(row.value).textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func export(_ groups: [ExportGroup]) {
        if let data = DevPropsExport.plist(groups) {
            exportFailed = false
            Files.save(data: data, name: "DeviceProperties.plist")
        } else {
            exportFailed = true
        }
    }
}
