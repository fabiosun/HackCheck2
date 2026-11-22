import AppKit
import SwiftUI

// MARK: - PCI

private struct PCICol {
    let title: String
    let width: CGFloat
    let value: (PCIDevice) -> String
    var mono = false
}

struct PCIView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var selection: PCIDevice.ID?
    @State private var expanded = true     // parte grande; selezionando una riga si riduce e compare il dettaglio

    private func hex(_ v: UInt16?) -> String {
        guard let v else { return "" }
        return "0x" + Fmt.hex(v, 4).uppercased()
    }

    private var cols: [PCICol] {
        [
            PCICol(title: "Vendor", width: 70, value: { hex($0.vendorID) }, mono: true),
            PCICol(title: "Device", width: 70, value: { hex($0.deviceID) }, mono: true),
            PCICol(title: "Sub Vendor", width: 84, value: { hex($0.subVendorID) }, mono: true),
            PCICol(title: "Sub Device", width: 84, value: { hex($0.subDeviceID) }, mono: true),
            PCICol(title: "ASPM", width: 76, value: { $0.aspm }),
            PCICol(title: "Vendor Name", width: 170, value: { $0.vendorName }),
            PCICol(title: "Device Name", width: 280, value: { $0.deviceName }),
            PCICol(title: "Class", width: 150, value: { $0.baseClassName }),
            PCICol(title: "Subclass", width: 190, value: { $0.subclassName }),
            PCICol(title: "IOReg Name", width: 240, value: { $0.ioregName }, mono: true),
            PCICol(title: "IOReg IOName", width: 150, value: { $0.ioName }, mono: true),
            PCICol(title: "Device Path", width: 340, value: { $0.devicePath }, mono: true),
        ]
    }

    private var filtered: [PCIDevice] {
        let all = store.snap.pci
        guard !query.isEmpty else { return all }
        return all.filter {
            [$0.location, $0.vendorName, $0.deviceName, $0.className, $0.idString, $0.ioregName, $0.ioName, $0.devicePath,
             $0.drivers.joined(separator: " ")]
                .joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    private func cell(_ text: String, _ c: PCICol, bold: Bool = false, selectable: Bool = false) -> some View {
        let t = Text(text)
            .font(c.mono && !bold ? Font.system(.caption, design: .monospaced) : Font.caption)
            .fontWeight(bold ? .semibold : .regular)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: c.width, alignment: .leading)
            .padding(.horizontal, 6)
            .help(text)
        return Group {
            if selectable {
                t.textSelection(.enabled)
            } else {
                t
            }
        }
    }

    private func headerRow(_ cols: [PCICol]) -> some View {
        HStack(spacing: 0) {
            ForEach(cols.indices, id: \.self) { i in cell(cols[i].title, cols[i], bold: true, selectable: false) }
        }
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func dataRow(_ d: PCIDevice, _ cols: [PCICol], alt: Bool) -> some View {
        let selected = selection == d.id
        return HStack(spacing: 0) {
            ForEach(cols.indices, id: \.self) { i in
                cell(cols[i].value(d), cols[i], selectable: false)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = d.id; expanded = false }
            }
        }
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.28) : (alt ? Color.primary.opacity(0.04) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { selection = d.id; expanded = false }
    }

    private func exportText() {
        let cols = self.cols
        var table: [[String]] = [cols.map { $0.title }]
        for d in store.snap.pci { table.append(cols.map { $0.value(d) }) }
        var widths: [Int] = []
        for i in 0..<cols.count { widths.append(table.map { $0[i].count }.max() ?? 0) }
        var lines: [String] = []
        for row in table {
            var parts: [String] = []
            for (i, cell) in row.enumerated() { parts.append(cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)) }
            lines.append(parts.joined(separator: "  "))
        }
        Files.save(text: lines.joined(separator: "\n") + "\n", name: "PCI-devices.txt")
    }

    private func exportPlist() {
        let cols = self.cols
        var arr: [[String: Any]] = []
        for d in store.snap.pci {
            var item: [String: Any] = [:]
            for c in cols { item[c.title] = c.value(d) }
            item["Location"] = d.location
            item["Drivers"] = d.drivers
            arr.append(item)
        }
        if let data = try? PropertyListSerialization.data(fromPropertyList: arr, format: .xml, options: 0) {
            Files.save(data: data, name: "PCI-devices.plist")
        }
    }

    var body: some View {
        let cols = self.cols
        let rows = filtered
        let tableView = ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { item in
                        dataRow(item.element, cols, alt: item.offset % 2 == 1)
                    }
                } header: {
                    headerRow(cols)
                }
            }
        }
        Group {
            if expanded {
                tableView
            } else {
                VSplitView {
                    tableView.frame(minHeight: 220)
                    Group {
                        if let dev = store.snap.pci.first(where: { $0.id == selection }) {
                            PCIDetail(dev: dev)
                        } else {
                            UnavailableView(title: tr("Seleziona un dispositivo"), systemImage: "rectangle.connected.to.line.below")
                        }
                    }
                    .frame(minHeight: 200, idealHeight: 280)
                }
            }
        }
        .searchable(text: $query, prompt: tr("Cerca nome, ID, classe, driver"))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(rows.count) " + tr("dispositivi")).foregroundStyle(.secondary)
                Button { expanded.toggle() } label: {
                    Label(expanded ? tr("Mostra dettagli") : tr("Espandi tabella"),
                          systemImage: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                Menu {
                    Button(tr("Esporta .txt…")) { exportText() }
                    Button(tr("Esporta .plist…")) { exportPlist() }
                } label: {
                    Label(tr("Esporta elenco"), systemImage: "square.and.arrow.up")
                }
                Spacer()
                Button(tr("Aggiorna pci.ids")) { store.updatePCIIDs() }
                if !store.pciMessage.isEmpty { Text(store.pciMessage).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.bar)
        }
    }
}

struct PCIDetail: View {
    let dev: PCIDevice
    @State private var query = ""

    private var rows: [PropertyRow] {
        query.isEmpty ? dev.properties : dev.properties.filter {
            ($0.key + " " + $0.value).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dev.deviceName).font(.title3.bold()).textSelection(.enabled)
                Text(dev.vendorName).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Chip(dev.idString)
                    Chip(dev.location)
                    if dev.builtIn { Chip("built-in", tint: .green) }
                }
                if !dev.acpiPath.isEmpty { Text(dev.acpiPath).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled) }
                if !dev.drivers.isEmpty { Text("Driver: " + dev.drivers.joined(separator: ", ")).font(.caption).textSelection(.enabled) }
                Button { Files.copy(dev.lspci) } label: { Label(tr("Copia come lspci"), systemImage: "doc.on.doc") }
                    .controlSize(.small)
            }
            .padding([.top, .horizontal], 12)

            TextField(tr("Cerca proprietà"), text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 12)

            List(rows) { r in
                HStack(alignment: .top) {
                    Text(r.key).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                    Text(r.value).textSelection(.enabled)
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
    }
}

// MARK: - Kext

private struct KextCatalogItem {
    let name: String
    let match: String        // frammento (minuscolo) del bundle ID
    let repo: String         // repository GitHub per il controllo versioni (vuoto = nessuno)
    let desc: String         // descrizione in italiano (tradotta con tr)
}

private struct KextRow: Identifiable {
    var id: String
    var name: String
    var bundle: String
    var installed: String
    var isInstalled: Bool
    var repo: String
    var desc: String
}

struct KextView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @AppStorage("kextOnlyInstalled") private var onlyInstalled = true
    @State private var latest: [String: String] = [:]
    @State private var checking = false
    @State private var message = ""

    private static var catalog: [KextCatalogItem] { [
        KextCatalogItem(name: "AirportBrcmFixup", match: "airportbrcmfixup", repo: "acidanthera/AirportBrcmFixup",
                        desc: tr("Kext open source con le patch necessarie per le schede Airport Broadcom non native.")),
        KextCatalogItem(name: "AppleALC", match: "applealc", repo: "acidanthera/AppleALC",
                        desc: tr("Kext open source che abilita l'audio HD nativo per codec non supportati ufficialmente.")),
        KextCatalogItem(name: "BlueToolFixup", match: "bluetoolfixup", repo: "acidanthera/BrcmPatchRAM",
                        desc: tr("Patch del Bluetooth per le schede Broadcom su macOS recenti.")),
        KextCatalogItem(name: "BrcmPatchRAM", match: "brcmpatchram", repo: "acidanthera/BrcmPatchRAM",
                        desc: tr("Driver PatchRAM per le schede wireless Broadcom.")),
        KextCatalogItem(name: "CPUFriend", match: "cpufriend", repo: "acidanthera/CPUFriend",
                        desc: tr("Gestione dinamica della frequenza della CPU con dati personalizzati.")),
        KextCatalogItem(name: "IntelMausi", match: "intelmausi", repo: "acidanthera/IntelMausi",
                        desc: tr("Driver macOS per le schede LAN Intel integrate.")),
        KextCatalogItem(name: "itlwm", match: "itlwm", repo: "OpenIntelWireless/itlwm",
                        desc: tr("Driver Wi-Fi per le schede Intel.")),
        KextCatalogItem(name: "Lilu", match: "lilu", repo: "acidanthera/Lilu",
                        desc: tr("Kext che offre una piattaforma per patchare kext, librerie e programmi.")),
        KextCatalogItem(name: "NVMeFix", match: "nvmefix", repo: "acidanthera/NVMeFix",
                        desc: tr("Patch per il driver NVMe di Apple, utili per risparmio energetico e compatibilità.")),
        KextCatalogItem(name: "RealtekRTL8111", match: "realtekrtl8111", repo: "Mieze/RTL8111_driver_for_OS_X",
                        desc: tr("Driver per le schede Ethernet Realtek RTL8111.")),
        KextCatalogItem(name: "RestrictEvents", match: "restrictevents", repo: "acidanthera/RestrictEvents",
                        desc: tr("Estensione Lilu che blocca processi indesiderati che causano problemi di compatibilità.")),
        KextCatalogItem(name: "SimpleBCM", match: "simplebcm", repo: "",
                        desc: tr("Ripristina il Wi-Fi Broadcom sulle versioni recenti di macOS tramite OpenCore.")),
        KextCatalogItem(name: "SimpleHDA", match: "simplehda", repo: "",
                        desc: tr("Ripristina l'AppleHDA originale sulle versioni recenti di macOS tramite OpenCore e Lilu.")),
        KextCatalogItem(name: "SMCAMDProcessor", match: "smcamdprocessor", repo: "trulyspinach/SMCAMDProcessor",
                        desc: tr("Gestione energetica e sensori per le CPU AMD Ryzen.")),
        KextCatalogItem(name: "USBToolBox", match: "usbtoolbox", repo: "USBToolBox/kext",
                        desc: tr("Mappatura delle porte USB tramite USBToolBox.")),
        KextCatalogItem(name: "VirtualSMC", match: "virtualsmc", repo: "acidanthera/VirtualSMC",
                        desc: tr("Emulatore SMC avanzato nel kernel; richiede Lilu per tutte le funzioni.")),
        KextCatalogItem(name: "WhateverGreen", match: "whatevergreen", repo: "acidanthera/WhateverGreen",
                        desc: tr("Plugin Lilu con patch per selezionare le GPU su macOS; richiede Lilu 1.2.5 o successivo.")),
    ] }

    private var rows: [KextRow] {
        var out: [KextRow] = []
        var used = Set<String>()
        for item in Self.catalog {
            let hit = store.snap.kexts.first { $0.id.lowercased().contains(item.match) }
            if let h = hit { used.insert(h.id) }
            out.append(KextRow(id: item.name, name: item.name, bundle: hit?.id ?? "", installed: hit?.version ?? "",
                               isInstalled: hit != nil, repo: item.repo, desc: tr(item.desc)))
        }
        for k in store.snap.kexts where !used.contains(k.id) {
            let short = k.id.split(separator: ".").last.map(String.init) ?? k.id
            out.append(KextRow(id: k.id, name: short, bundle: k.id, installed: k.version, isInstalled: true, repo: "", desc: ""))
        }
        var r = onlyInstalled ? out.filter { $0.isInstalled } : out
        if !query.isEmpty {
            r = r.filter { ($0.name + " " + $0.bundle + " " + $0.desc).localizedCaseInsensitiveContains(query) }
        }
        return r.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private static func norm(_ v: String) -> String {
        let s = v.lowercased()
        return s.hasPrefix("v") ? String(s.dropFirst()) : s
    }

    @ViewBuilder
    private func status(_ r: KextRow) -> some View {
        if !r.isInstalled {
            Chip(tr("Non installata"), tint: .secondary)
        } else if let cur = latest[r.id], !cur.isEmpty, Self.norm(cur) != Self.norm(r.installed) {
            Chip(tr("Aggiornamento"), tint: .orange)
        } else {
            Chip(tr("Installata"), tint: .blue)
        }
    }

    private static func fetchLatest(_ repo: String) async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private func checkVersions() {
        checking = true
        message = ""
        let repos = Self.catalog.filter { !$0.repo.isEmpty }.map { ($0.name, $0.repo) }
        Task { @MainActor in
            var found: [String: String] = [:]
            for (name, repo) in repos {
                if let v = await Self.fetchLatest(repo) { found[name] = v }
            }
            latest = found
            checking = false
            if found.isEmpty { message = tr("Impossibile controllare le versioni (rete o limite GitHub)") }
        }
    }

    var body: some View {
        let list = rows
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Toggle(tr("Mostra solo installate"), isOn: $onlyInstalled).toggleStyle(.checkbox)
                Spacer()
                if checking { ProgressView().controlSize(.small) }
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                Button { checkVersions() } label: {
                    Label(tr("Controlla versioni"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(checking)
            }
            Table(list) {
                TableColumn(tr("Nome")) { r in
                    HStack(spacing: 6) {
                        Image(systemName: "puzzlepiece.extension").foregroundStyle(.secondary)
                        Text(r.name)
                    }
                    .help(r.bundle)
                }
                .width(min: 130, ideal: 170)
                TableColumn(tr("Stato")) { r in status(r) }
                    .width(min: 110, ideal: 130)
                TableColumn(tr("Installata")) { r in
                    Text(r.installed).font(.system(.body, design: .monospaced))
                }
                .width(min: 70, ideal: 90)
                TableColumn(tr("Attuale")) { r in
                    Text(latest[r.id] ?? "").font(.system(.body, design: .monospaced))
                }
                .width(min: 70, ideal: 90)
                TableColumn("Download") { r in
                    if !r.repo.isEmpty {
                        Button {
                            if let u = URL(string: "https://github.com/\(r.repo)/releases/latest") { NSWorkspace.shared.open(u) }
                        } label: { Image(systemName: "arrow.down.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn(tr("Descrizione")) { r in
                    Text(r.desc).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(16)
        .searchable(text: $query, prompt: tr("Cerca kext"))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(list.count) kext").foregroundStyle(.secondary)
                Spacer()
                Button(tr("Esporta CSV…")) {
                    let csv = "bundle_id,version\n" + store.snap.kexts.map { "\($0.id),\($0.version)" }.joined(separator: "\n")
                    Files.save(text: csv, name: "kext-non-apple.csv")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.bar)
        }
    }
}

// MARK: - Boot

struct BootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let b = store.snap.boot
        Form {
            Section("Bootloader") {
                LabeledContent("Bootloader", value: b.loaderName)
                if !b.loaderVersion.isEmpty { LabeledContent(tr("Versione"), value: b.loaderVersion) }
                if !b.loaderSource.isEmpty { LabeledContent(tr("Rilevato da"), value: b.loaderSource) }
            }
            Section(tr("Diagnostica rilevamento")) {
                ForEach(Array(b.signals.enumerated()), id: \.offset) { item in
                    Text(item.element).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if b.loader.isEmpty {
                    Text(tr("Se usi OpenCore, imposta Misc → Security → ExposeSensitiveData a 6 (include la versione) oppure monta la EFI dalla pagina «Archiviazione»."))
                        .font(.caption)
                }
            }
            Section("System Integrity Protection") {
                LabeledContent(tr("Stato"), value: b.sipStatusDisplay.isEmpty ? "—" : b.sipStatusDisplay)
                if !b.csrHex.isEmpty { LabeledContent("csr-active-config", value: b.csrHex) }
                if !b.csrFlags.isEmpty {
                    FlowLayout { ForEach(b.csrFlags, id: \.self) { Chip($0, tint: .orange) } }
                }
            }
            Section(tr("Argomenti di boot")) {
                Text(b.bootArgs.isEmpty ? "—" : b.bootArgs).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            Section("Boot log") {
                if b.bootLog.isEmpty {
                    Text(b.loader == "OpenCore"
                         ? tr("Non disponibile: serve la versione Debug di OpenCore con il log salvato in NVRAM.")
                         : tr("Boot log non disponibile."))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView { Text(b.bootLog).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 220)
                    Button(tr("Salva boot log…")) { Files.save(text: b.bootLog, name: "Boot.log") }
                }
            }
            Section("NVRAM") {
                DisclosureGroup(tr("Mostra nvram -p")) {
                    ScrollView { Text(b.nvram).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 260)
                }
            }
        }
        .formStyle(.grouped)
        .modifier(AquaScroll())
    }
}

// MARK: - ACPI

struct ACPIView: View {
    @EnvironmentObject var store: Store
    @State private var scanning = false

    private let notable: Set<String> = ["EC", "H_EC", "PNLF", "ALS0", "MCHC", "SBUS", "DMAC", "PMCR", "XHC", "XHCI", "XHC0"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(tr("Dispositivi ACPI esposti a macOS"), icon: "memorychip") {
                    FlowLayout {
                        ForEach(store.snap.acpiDevices, id: \.self) { Chip($0, tint: notable.contains($0) ? .accentColor : .secondary) }
                    }
                }
                Card(tr("Errori ACPI nel log dell'ultimo avvio"), icon: "exclamationmark.triangle") {
                    HStack(spacing: 10) {
                        Button(scanning ? tr("Scansione…") : tr("Scansiona")) { scan() }.disabled(scanning)
                        if scanning { ProgressView().controlSize(.small) }
                        if store.acpiScanned && !store.acpiErrors.isEmpty {
                            Spacer()
                            Button { Files.copy(store.acpiErrors.joined(separator: "\n")) } label: {
                                Label(tr("Copia"), systemImage: "doc.on.doc")
                            }
                            .controlSize(.small)
                        }
                    }
                    if store.acpiScanned {
                        if store.acpiErrors.isEmpty {
                            Label(tr("Nessun errore ACPI trovato"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Text(store.acpiErrors.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func scan() {
        scanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> [String] in
                let out = Shell.run("/usr/bin/log", ["show", "--last", "boot", "--style", "compact", "--predicate",
                                                     "process == \"kernel\" AND senderImagePath CONTAINS[c] \"AppleACPIPlatform\""])
                if out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return [tr("Impossibile leggere il log (serve un account amministratore).")]
                }
                let keys = ["error", "AE_", "fail", "garbage", "not found", "undefined"]
                return out.split(separator: "\n").map(String.init).filter { l in keys.contains { l.localizedCaseInsensitiveContains($0) } }
            }.value
            await MainActor.run {
                store.acpiErrors = result
                store.acpiScanned = true
                scanning = false
            }
        }
    }
}

// MARK: - Dettagli di sistema

struct ProfilerPage: View {
    @EnvironmentObject var store: Store
    private let types: [(String, String)] = [
        ("Hardware", "SPHardwareDataType"), (tr("Memoria"), "SPMemoryDataType"), (tr("Grafica e monitor"), "SPDisplaysDataType"),
        ("Wi-Fi", "SPAirPortDataType"), (tr("Rete"), "SPNetworkDataType"), ("Bluetooth", "SPBluetoothDataType"),
        ("Audio", "SPAudioDataType"), ("NVMe", "SPNVMeDataType"), ("SATA", "SPSerialATADataType"),
        (tr("Archiviazione"), "SPStorageDataType"), ("USB", "SPUSBDataType"), ("Thunderbolt", "SPThunderboltDataType"),
        ("PCI", "SPPCIDataType"), (tr("Alimentazione"), "SPPowerDataType"),
    ]
    @State private var selected = "SPHardwareDataType"
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker(tr("Categoria"), selection: $selected) {
                    ForEach(types, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(maxWidth: 340)
                Spacer()
                if exporting { ProgressView().controlSize(.small) }
                Button { exportFull() } label: {
                    Label(tr("Esporta report completo…"), systemImage: "square.and.arrow.up")
                }
                .disabled(exporting)
            }
            .padding(12)
            Divider()
            ProfilerTreeView(dataType: selected)
            Divider()
            AppIconFooter()
        }
    }

    /// Report completo: riepilogo HackCheck + tutte le categorie di system_profiler, in un unico file di testo.
    private func exportFull() {
        exporting = true
        let head = "HackCheck – " + tr("Report completo") + " – " + Date().formatted(date: .abbreviated, time: .shortened) + "\n\n"
        let summary = head + Report.text(store.snap) + Report.extras(store.snap)
        let list = types
        Task { @MainActor in
            let text = await Task.detached(priority: .userInitiated) { () -> String in
                var out = summary
                for (title, type) in list {
                    out += "\n\n==================== \(title) ====================\n"
                    out += Report.redactSensitive(Shell.run("/usr/sbin/system_profiler", [type, "-detailLevel", "full"]))
                }
                return out
            }.value
            exporting = false
            Files.save(text: text, name: "HackCheck-Report.txt")
        }
    }
}
