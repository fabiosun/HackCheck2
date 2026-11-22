import SwiftUI
import AppKit

// MARK: - Modello

struct DiskPart: Identifiable, Hashable {
    var id: String                 // es. disk0s1
    var name = ""
    var content = ""               // es. EFI, Apple_APFS, Microsoft Basic Data
    var size: Int64 = 0
    var mountPoint = ""
    var hints: [String] = []       // bootloader trovati (solo EFI montate)
    var expose: Int? = nil         // ExposeSensitiveData letto dal config.plist di OpenCore
    var xhci: Bool? = nil          // Kernel → Quirks → XhciPortLimit

    var isEFI: Bool {
        if content == "EFI" { return true }
        let n = name.lowercased()
        let c = content.lowercased()
        if n.contains("efi") || c.contains("efi") { return true }
        return !hints.isEmpty
    }
    var mounted: Bool { !mountPoint.isEmpty }
    var isSystemMount: Bool { mountPoint == "/" || mountPoint.hasPrefix("/System/Volumes") }
    var canMount: Bool {
        !["Apple_APFS", "Apple_APFS_ISC", "Apple_APFS_Recovery", "Apple_Boot", "Apple_Free",
          "Apple_partition_map", "Apple_partition_scheme"].contains(content)
    }
}

struct DiskGroup: Identifiable {
    var id: String                 // es. disk0
    var size: Int64 = 0
    var scheme = ""
    var isInternal = false
    var parts: [DiskPart] = []
}

struct OpResult {
    var ok: Bool
    var message: String
}

// MARK: - diskutil

enum DiskUtil {
    /// Accetta solo identificatori del tipo disk0, disk0s1, disk3s2s1 (evita injection nello script admin).
    static func isValidID(_ s: String) -> Bool {
        s.range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil
    }

    /// Determina se il disco è interno (alcuni sistemi riportano OSInternal=false in `diskutil list`).
    static func isInternalDisk(_ id: String) -> Bool {
        let xml = Shell.run("/usr/sbin/diskutil", ["info", "-plist", id])
        guard let data = xml.data(using: .utf8),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = obj as? [String: Any] else { return false }
        if let v = root["Internal"] as? Bool { return v }
        if let rem = root["RemovableMediaOrExternalDevice"] as? Bool { return !rem }
        return false
    }

    static func list() -> [DiskGroup] {
        let xml = Shell.run("/usr/sbin/diskutil", ["list", "-plist"])
        guard let data = xml.data(using: .utf8),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = obj as? [String: Any],
              let disks = root["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }

        var out: [DiskGroup] = []
        for d in disks {
            guard let id = d["DeviceIdentifier"] as? String else { continue }
            var g = DiskGroup(id: id)
            g.size = (d["Size"] as? NSNumber)?.int64Value ?? 0
            g.scheme = d["Content"] as? String ?? ""
            let osInternal = d["OSInternal"] as? Bool ?? false
            g.isInternal = osInternal || isInternalDisk(id)

            for key in ["Partitions", "APFSVolumes"] {
                let items = (d[key] as? [[String: Any]]) ?? []
                for p in items {
                    guard let pid = p["DeviceIdentifier"] as? String else { continue }
                    var part = DiskPart(id: pid)
                    part.name = p["VolumeName"] as? String ?? ""
                    part.content = p["Content"] as? String ?? (key == "APFSVolumes" ? "APFS Volume" : "")
                    let size = (p["Size"] as? NSNumber) ?? (p["CapacityInUse"] as? NSNumber)
                    part.size = size?.int64Value ?? 0
                    part.mountPoint = p["MountPoint"] as? String ?? ""
                    if part.mounted && !part.isSystemMount {
                        part.hints = bootloaderHints(mountPoint: part.mountPoint)
                        if !part.hints.isEmpty {
                            let cfg = readOCConfig(mountPoint: part.mountPoint)
                            part.expose = cfg.expose
                            part.xhci = cfg.xhci
                        }
                    }
                    g.parts.append(part)
                }
            }
            out.append(g)
        }
        return out
    }

    /// Cerca OpenCore / Clover dentro una EFI montata.
    static func bootloaderHints(mountPoint: String) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        let efiPath = mountPoint + "/EFI"
        if fm.fileExists(atPath: efiPath + "/OC") { out.append("OpenCore") }
        if let items = try? fm.contentsOfDirectory(atPath: efiPath) {
            if items.contains(where: { $0.caseInsensitiveCompare("CLOVER") == .orderedSame }) {
                out.append("Clover")
            }
        } else if fm.fileExists(atPath: efiPath + "/CLOVER") {
            out.append("Clover")
        }
        return Array(Set(out)).sorted()
    }

    /// Legge dal config.plist di OpenCore: Misc → Security → ExposeSensitiveData e Kernel → Quirks → XhciPortLimit.
    static func readOCConfig(mountPoint: String) -> (expose: Int?, xhci: Bool?) {
        guard let d = NSDictionary(contentsOfFile: mountPoint + "/EFI/OC/config.plist") else { return (nil, nil) }
        var expose: Int? = nil
        var xhci: Bool? = nil
        if let misc = d["Misc"] as? [String: Any], let sec = misc["Security"] as? [String: Any],
           let n = sec["ExposeSensitiveData"] as? NSNumber { expose = n.intValue }
        if let kernel = d["Kernel"] as? [String: Any], let q = kernel["Quirks"] as? [String: Any],
           let n = q["XhciPortLimit"] as? NSNumber { xhci = n.boolValue }
        return (expose, xhci)
    }

    private static func firstNonEmpty(_ items: [String]) -> String {
        for s in items {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return ""
    }

    private static func operation(_ verb: String, _ id: String) -> OpResult {
        guard isValidID(id), verb == "mount" || verb == "unmount" else {
            return OpResult(ok: false, message: "ID non valido")
        }
        let r = Shell.runFull("/usr/sbin/diskutil", [verb, "/dev/" + id])
        if r.status == 0 { return OpResult(ok: true, message: firstNonEmpty([r.out])) }

        // Secondo tentativo con privilegi di amministratore (tipico per le partizioni EFI).
        let script = "do shell script \"/usr/sbin/diskutil \(verb) /dev/\(id)\" with administrator privileges"
        let a = Shell.runFull("/usr/bin/osascript", ["-e", script])
        if a.status == 0 { return OpResult(ok: true, message: firstNonEmpty([a.out])) }
        return OpResult(ok: false, message: firstNonEmpty([a.err, r.err, r.out]))
    }

    static func mount(_ id: String) -> OpResult { operation("mount", id) }
    static func unmount(_ id: String) -> OpResult { operation("unmount", id) }

    /// Monta più partizioni chiedendo la password di amministratore una sola volta.
    static func mountAll(_ ids: [String]) -> OpResult {
        let valid = ids.filter { isValidID($0) }
        var failedIDs: [String] = []
        for id in valid {
            if Shell.runFull("/usr/sbin/diskutil", ["mount", "/dev/" + id]).status != 0 { failedIDs.append(id) }
        }
        if failedIDs.isEmpty { return OpResult(ok: true, message: "") }

        let cmd = failedIDs.map { "/usr/sbin/diskutil mount /dev/\($0)" }.joined(separator: "; ")
        let a = Shell.runFull("/usr/bin/osascript", ["-e", "do shell script \"\(cmd)\" with administrator privileges"])

        // Verifica reale: rileggo lo stato dei dischi.
        let after = list().flatMap { $0.parts }
        var still: [String] = []
        for id in failedIDs {
            let mounted = after.first(where: { $0.id == id })?.mounted ?? false
            if !mounted { still.append(id) }
        }
        if still.isEmpty { return OpResult(ok: true, message: "") }
        return OpResult(ok: false, message: firstNonEmpty([a.err, a.out]))
    }
}

// MARK: - Pagina

struct DisksPanel: View {
    @State private var groups: [DiskGroup] = []
    @State private var loading = true
    @State private var busy: String?
    @State private var message = ""
    @State private var failed = false
    @AppStorage("efiOnly") private var efiOnly = false
    @EnvironmentObject var store: Store

    /// Con «solo EFI» restano le sole partizioni EFI (e i dischi che le contengono).
    private var visibleGroups: [DiskGroup] {
        guard efiOnly else { return groups }
        var out: [DiskGroup] = []
        for g in groups {
            var copy = g
            copy.parts = g.parts.filter { $0.isEFI }
            if !copy.parts.isEmpty { out.append(copy) }
        }
        return out
    }

    private var efiToMount: [DiskPart] {
        groups.flatMap { $0.parts }.filter { $0.isEFI && !$0.mounted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("Monta, smonta e sfoglia le partizioni, comprese le EFI con OpenCore o Clover. Se serve, macOS chiede la password di amministratore."))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button { mountAllEFI() } label: {
                        Label(tr("Monta tutte le EFI"), systemImage: "memorychip")
                    }
                    .disabled(efiToMount.isEmpty || busy != nil)
                    Button { reload() } label: {
                        Label(tr("Aggiorna elenco"), systemImage: "arrow.clockwise")
                    }
                    .disabled(busy != nil)
                    Toggle(tr("Mostra solo partizioni EFI"), isOn: $efiOnly).toggleStyle(.checkbox)
                    if loading || busy != nil { ProgressView().controlSize(.small) }
                    Spacer()
                }

                if !message.isEmpty {
                    Label(message, systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(failed ? Color.orange : Color.green)
                        .textSelection(.enabled)
                }

                if visibleGroups.isEmpty && !loading {
                    UnavailableView(title: efiOnly ? tr("Nessuna partizione EFI trovata") : tr("Nessun disco trovato"), systemImage: "externaldrive",
                                    description: tr("diskutil non ha restituito informazioni."))
                }

                ForEach(visibleGroups) { g in
                    Card(groupTitle(g), icon: g.isInternal ? "internaldrive" : "externaldrive") {
                        ForEach(g.parts) { p in
                            row(p)
                            if p.id != g.parts.last?.id { Divider() }
                        }
                    }
                }
            }
        }
        .task { reload() }
    }

    private func groupTitle(_ g: DiskGroup) -> String {
        let size = ByteCountFormatter.string(fromByteCount: g.size, countStyle: .file)
        let kind = g.isInternal ? tr("Interno") : tr("Esterno")
        return "\(g.id)  ·  \(size)  ·  \(kind)"
    }

    @ViewBuilder
    private func row(_ p: DiskPart) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.name.isEmpty ? p.content : p.name).fontWeight(.medium)
                    if p.isEFI { Chip("EFI", tint: .orange) }
                    ForEach(p.hints, id: \.self) { Chip($0, tint: .green) }
                }
                let size = ByteCountFormatter.string(fromByteCount: p.size, countStyle: .file)
                Text("\(p.id)  ·  \(p.content)  ·  \(size)")
                    .font(.caption).foregroundStyle(.secondary)
                if p.mounted {
                    Text(p.mountPoint).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
                    if p.isEFI && p.hints.isEmpty {
                        Text(tr("Nessun OpenCore/Clover trovato in questa EFI")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 12)
            if busy == p.id || busy == "all" {
                ProgressView().controlSize(.small)
            } else if p.mounted {
                Button(tr("Apri nel Finder")) { NSWorkspace.shared.open(URL(fileURLWithPath: p.mountPoint)) }
                if !p.isSystemMount {
                    Button(tr("Smonta")) { run(p, mount: false) }.disabled(busy != nil)
                }
            } else if p.canMount {
                Button(tr("Monta")) { run(p, mount: true) }.disabled(busy != nil)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Azioni

    /// Rilegge i dischi; per gli ID indicati (appena montati) apre la cartella nel Finder.
    private func reload(openAfter ids: [String] = []) {
        loading = true
        Task { @MainActor in
            let g = await Task.detached(priority: .userInitiated) { DiskUtil.list() }.value
            groups = g
            loading = false
            let parts = g.flatMap { $0.parts }
            for id in ids {
                if let mp = parts.first(where: { $0.id == id })?.mountPoint, !mp.isEmpty {
                    NSWorkspace.shared.open(URL(fileURLWithPath: mp))
                }
            }
        }
    }

    private func run(_ p: DiskPart, mount: Bool) {
        busy = p.id
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) { () -> OpResult in
                mount ? DiskUtil.mount(p.id) : DiskUtil.unmount(p.id)
            }.value
            failed = !r.ok
            if r.ok {
                message = "\(p.id): " + tr(mount ? "montata" : "smontata")
            } else {
                var text = "\(p.id): " + tr(mount ? "montaggio non riuscito" : "smontaggio non riuscito")
                if !r.message.isEmpty { text += " — " + r.message }
                message = text
            }
            busy = nil
            reload(openAfter: (r.ok && mount) ? [p.id] : [])
            if r.ok { store.refresh() }      // rilegge anche il bootloader (ora la EFI è leggibile)
        }
    }

    private func mountAllEFI() {
        let ids = efiToMount.map { $0.id }
        guard !ids.isEmpty else { return }
        busy = "all"
        Task { @MainActor in
            let r = await Task.detached(priority: .userInitiated) { DiskUtil.mountAll(ids) }.value
            failed = !r.ok
            if r.ok {
                message = tr("EFI montate") + ": \(ids.count)"
            } else {
                var text = tr("Montaggio EFI non riuscito")
                if !r.message.isEmpty { text += " — " + r.message }
                message = text
            }
            busy = nil
            reload(openAfter: ids)
            store.refresh()
        }
    }
}
