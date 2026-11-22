import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: Store
    @AppStorage("maskSerial") private var mask = true

    private func m(_ s: String) -> String {
        guard mask, s.count > 4 else { return s }
        return String(s.prefix(3)) + String(repeating: "•", count: 6)
    }

    var body: some View {
        let s = store.snap
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Image(systemName: "desktopcomputer").font(.system(size: 46, weight: .light)).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.system.model.isEmpty ? tr("Questo Mac") : s.system.model).font(.largeTitle.bold())
                        Text("\(s.system.macOSName) \(s.system.macOS) (\(s.system.build))").foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        PrefsBar()
                        Toggle(isOn: $mask) {
                            Label(tr("Nascondi seriale e UUID"), systemImage: mask ? "eye.slash" : "eye")
                        }
                        .toggleStyle(.button)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 16, alignment: .top)], spacing: 16) {
                    Card(tr("Sistema"), icon: "macwindow", tint: .blue) {
                        KV(tr("Modello"), s.system.model)
                        KV("Board ID", s.system.boardID)
                        KV(tr("Seriale"), m(s.system.serial))
                        KV("UUID", m(s.system.uuid))
                        KV("Kernel", s.system.kernel)
                        KV(tr("Attivo da"), s.system.uptime)
                    }
                    Card(tr("Processore e memoria"), icon: "cpu", tint: .orange) {
                        KV("CPU", s.cpu.brand)
                        KV(tr("Core / thread"), "\(s.cpu.cores) / \(s.cpu.threads)")
                        KV("RAM", s.cpu.ram)
                    }
                    Card(tr("Grafica"), icon: "display", tint: .purple) {
                        if s.gpus.isEmpty { Text(tr("Nessuna GPU PCI rilevata")).foregroundStyle(.secondary) }
                        ForEach(s.gpus) { g in KV(g.vendor, g.name) }
                        KV("Metal", s.metalDevices.joined(separator: ", "))
                    }
                    Card(tr("Rete"), icon: "network", tint: .cyan) {
                        if s.network.isEmpty { Text(tr("Nessuna interfaccia")).foregroundStyle(.secondary) }
                        ForEach(s.network) { n in
                            KV("\(n.bsd) · \(n.port)", n.ip.isEmpty ? n.mac : n.ip)
                        }
                    }
                    Card("Audio", icon: "speaker.wave.2", tint: .pink) {
                        ForEach(s.audioCodecs, id: \.self) { KV("Codec", $0) }
                        ForEach(s.audio) { a in KV(a.name, a.layoutID.isEmpty ? "" : "layout-id \(a.layoutID)") }
                        ForEach(s.audioDevices.filter(\.isUSB)) { d in
                            KV(tr("Audio USB"), d.name)
                        }
                    }
                    Card(tr("Bootloader e SIP"), icon: "power", tint: .red) {
                        KV("Bootloader", s.boot.loaderName)
                        KV(tr("Versione"), s.boot.loaderVersion)
                        KV("SIP", s.boot.sipStatusDisplay)
                        KV(tr("Kext non Apple"), "\(s.kexts.count)")
                    }
                }

                Card(tr("Controlli rapidi"), icon: "checkmark.shield", tint: .green) {
                    ForEach(s.checks) { CheckRow(check: $0) }
                }
            }
            .padding(24)
        }
    }
}

struct CPUView: View {
    @EnvironmentObject var store: Store

    private func vendorColor(_ v: String) -> Color {
        if v.contains("Intel") { return .blue }
        if v.contains("AMD") { return .red }
        return .gray
    }

    private func memColor(_ m: String) -> Color {
        let s = m.lowercased()
        if s.contains("samsung") { return .blue }
        if s.contains("micron") || s.contains("crucial") { return .teal }
        if s.contains("hynix") { return .orange }
        if s.contains("kingston") { return .red }
        if s.contains("corsair") { return .yellow }
        if s.contains("g.skill") || s.contains("gskill") { return .pink }
        if s.contains("team") { return .purple }
        if s.contains("adata") || s.contains("xpg") { return .indigo }
        return .gray
    }

    var body: some View {
        let c = store.snap.cpu
        let mods = store.snap.memory
        let tint = vendorColor(c.vendor)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(tr("Processore"), icon: "cpu", tint: tint) {
                    Text(c.brand).font(.title3.bold())
                    FlowLayout {
                        if !c.vendor.isEmpty { Chip(c.vendor, tint: tint) }
                        if !c.microarch.isEmpty { Chip(c.microarch, tint: .orange) }
                        if !c.generation.isEmpty { Chip(c.generation, tint: .purple) }
                        Chip("\(c.cores) " + tr("core") + " / \(c.threads) thread", tint: .green)
                        Chip(store.snap.system.arch, tint: .gray)
                    }
                    KV("Family / Model / Stepping", "\(c.family) / \(c.model) / \(c.stepping)")
                    KV(tr("Core fisici"), "\(c.cores)")
                    KV("Thread", "\(c.threads)")
                }

                Card(tr("Cache e memoria"), icon: "memorychip", tint: .green) {
                    FlowLayout {
                        Chip(tr("RAM installata") + ": " + c.ram, tint: .green)
                        if !c.l2.isEmpty { Chip("L2 " + c.l2, tint: .teal) }
                        if !c.l3.isEmpty { Chip("L3 " + c.l3, tint: .cyan) }
                    }
                }

                Card(tr("Moduli RAM"), icon: "memorychip", tint: .pink) {
                    if mods.isEmpty {
                        Text(tr("Nessun dato sui moduli RAM (SMBIOS incompleto o macchina virtuale)")).foregroundStyle(.secondary)
                    }
                    ForEach(mods) { m in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(memColor(m.manufacturer)).frame(width: 10, height: 10).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(m.slot).fontWeight(.semibold)
                                    Chip(m.manufacturer.isEmpty ? "?" : m.manufacturer, tint: memColor(m.manufacturer))
                                    if !m.type.isEmpty { Chip(m.type, tint: .indigo) }
                                }
                                Text([m.size, m.speed, m.partNumber].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                if !c.features.isEmpty {
                    Card(tr("Istruzioni supportate") + " (\(c.features.count))", icon: "list.bullet", tint: .brown) {
                        FlowLayout { ForEach(c.features, id: \.self) { Chip($0, tint: tint) } }
                    }
                }
            }
            .padding(24)
        }
    }
}
