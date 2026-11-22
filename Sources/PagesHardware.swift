import SwiftUI

struct GraphicsSummary: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let s = store.snap
        VStack(alignment: .leading, spacing: 16) {
            if s.gpus.isEmpty {
                UnavailableView(title: tr("Nessuna GPU PCI"), systemImage: "display",
                                description: tr("Su Apple Silicon la GPU non è un dispositivo PCI."))
            }
            ForEach(s.gpus) { g in
                Card(g.name, icon: "display") {
                    KV(tr("Produttore"), g.vendor)
                    KV("ID PCI", g.pciID)
                    KV(tr("Sottosistema"), g.subsystem)
                    KV(tr("Posizione"), g.location)
                    KV("Link PCIe", g.link)
                    KV(tr("Acceleratore"), g.accelerator)
                    KV(tr("Plugin Metal"), g.metalPlugin)
                    KV("ig-platform-id", g.platformID)
                    KV("Codec GVA", g.gvaCodec)
                    KV("Decoder HEVC", g.hevcDecode)
                    KV("Encoder HEVC", g.hevcEncode)
                    KV("Framebuffer", g.framebuffers > 0 ? "\(g.framebuffers)" : "")
                }
            }
            Card("Metal", icon: "cube") {
                if s.metalDevices.isEmpty { Text(tr("Nessun dispositivo Metal")).foregroundStyle(.red) }
                ForEach(s.metalDevices, id: \.self) { Text($0) }
            }
            Card(tr("Decodifica video hardware"), icon: "play.rectangle") {
                ForEach(s.codecs) { k in
                    HStack {
                        Image(systemName: k.supported ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(k.supported ? .green : .orange)
                        Text(k.name)
                        Spacer()
                        Text(k.supported ? "Hardware" : "Software").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct NetworkSummary: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let s = store.snap
        VStack(alignment: .leading, spacing: 16) {
            ForEach(s.network) { n in
                Card("\(n.bsd)  \(n.port)", icon: n.port.lowercased().contains("wi-fi") ? "wifi" : "cable.connector.horizontal") {
                    KV(tr("Indirizzo MAC"), n.mac)
                    KV(tr("Indirizzo IP"), n.ip)
                    KV("Driver", n.controller)
                    HStack {
                        Image(systemName: n.builtIn ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(n.builtIn ? .green : .orange)
                        Text(n.builtIn ? "Built-in" : tr("Non built-in"))
                        Spacer()
                    }
                    if n.bsd == "en0" && !n.builtIn {
                        Text(tr("Per iMessage / FaceTime / iCloud en0 dovrebbe essere built-in."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Card(tr("Schede di rete PCI"), icon: "rectangle.connected.to.line.below") {
                let nets = s.pci.filter { $0.baseClass == 0x02 }
                if nets.isEmpty { Text(tr("Nessuna scheda di rete PCI")).foregroundStyle(.secondary) }
                ForEach(nets) { DeviceRow(dev: $0) }
            }
        }
    }
}

struct AudioSummary: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let s = store.snap
        VStack(alignment: .leading, spacing: 16) {
            Card("Codec HDA", icon: "waveform") {
                if s.audioCodecs.isEmpty { Text(tr("Nessun codec IOHDACodecDevice trovato")).foregroundStyle(.secondary) }
                ForEach(s.audioCodecs, id: \.self) { Text($0).textSelection(.enabled) }
                Link(destination: URL(string: "https://github.com/acidanthera/applealc/wiki/supported-codecs")!) {
                    Label(tr("Layout supportati (AppleALC)"), systemImage: "arrow.up.right.square")
                }
            }
            Card(tr("Controller audio PCI"), icon: "speaker.wave.2") {
                if s.audio.isEmpty { Text(tr("Nessun controller audio PCI rilevato")).foregroundStyle(.secondary) }
                ForEach(s.audio) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name).fontWeight(.medium)
                        Text("\(a.vendor)  ·  \(a.location)").font(.caption).foregroundStyle(.secondary)
                        if !a.layoutID.isEmpty { Text("layout-id: \(a.layoutID)").font(.caption) }
                        if !a.driver.isEmpty { Text("Driver: \(a.driver)").font(.caption).foregroundStyle(.tertiary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Card(tr("Audio USB"), icon: "cable.connector", tint: .mint) {
                let usb = s.audioDevices.filter(\.isUSB)
                if usb.isEmpty {
                    Text(tr("Nessun dispositivo audio USB rilevato")).foregroundStyle(.secondary)
                }
                ForEach(usb) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).fontWeight(.medium)
                        let meta = [d.manufacturer, d.transport].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(tr("Gli audio USB sono gestiti dai driver integrati di macOS: non serve AppleALC né layout-id."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Card(tr("Dispositivi audio"), icon: "speaker.wave.3") {
                if s.audioDevices.isEmpty {
                    Text(tr("Nessun dispositivo audio rilevato")).foregroundStyle(.secondary)
                }
                ForEach(s.audioDevices) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).fontWeight(.medium)
                        let meta = [d.manufacturer, d.transport, d.source].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct StorageSummary: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let ctrl = store.snap.pci.filter { $0.baseClass == 0x01 }
        VStack(alignment: .leading, spacing: 16) {
            Card(tr("Controller di archiviazione"), icon: "internaldrive") {
                if ctrl.isEmpty { Text(tr("Nessun controller PCI di archiviazione")).foregroundStyle(.secondary) }
                ForEach(ctrl) { d in
                    DeviceRow(dev: d)
                    if !d.linkStatus.isEmpty { Text("Link: \(d.linkStatus)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            DisksPanel()
        }
    }
}

struct USBSummary: View {
    @EnvironmentObject var store: Store
    @AppStorage("usbOnlyUsed") private var onlyUsed = false

    var body: some View {
        let s = store.snap
        let hosts = s.pci.filter { $0.subClass16 == 0x0C03 }
        VStack(alignment: .leading, spacing: 16) {
            portLimitCard(s)

            Toggle(tr("Mostra solo porte USB attualmente utilizzate"), isOn: $onlyUsed)

            if s.usb.isEmpty {
                Card(tr("Controller USB"), icon: "cable.connector") {
                    if hosts.isEmpty { Text(tr("Nessun controller xHCI/EHCI rilevato")).foregroundStyle(.secondary) }
                    ForEach(hosts) { DeviceRow(dev: $0) }
                }
            }
            ForEach(s.usb) { c in controllerCard(c) }
        }
    }

    private func limitMessage(_ ports: Int, _ xhci: Bool?) -> String {
        guard let x = xhci else {
            return tr("config.plist non trovato: monta la EFI da Archiviazione (o una partizione con EFI/OC) per leggere XhciPortLimit.")
        }
        if ports > 15 {
            return x ? tr("Il controller espone più di 15 porte e XhciPortLimit è abilitato: macOS le vede tutte. Meglio una mappa USB di al massimo 15 porte, poi disattiva la patch.")
                     : tr("Il controller espone più di 15 porte e XhciPortLimit è disabilitato: macOS ne vedrà solo 15. Abilita XhciPortLimit o crea una mappa USB.")
        }
        return x ? tr("XhciPortLimit è abilitato ma le porte sono 15 o meno: la patch non serve più e si può disattivare.")
                 : tr("Porte entro il limite di 15.")
    }

    @ViewBuilder
    private func portLimitCard(_ s: Snapshot) -> some View {
        let maxPorts = s.usb.map { $0.ports.count }.max() ?? 0
        if maxPorts > 0 {
            let xhci = s.boot.xhciPortLimit
            let state = xhci == nil ? "?" : (xhci == true ? "ON" : "OFF")
            Card(tr("Limite porte USB"), icon: "gauge") {
                HStack {
                    Text(tr("Porte per controller") + ": \(maxPorts)  (" + tr("limite macOS") + ": 15)")
                    Spacer()
                    Chip("XhciPortLimit: " + state, tint: xhci == true ? .green : .secondary)
                    Chip(maxPorts > 15 ? ">15" : "≤15", tint: maxPorts > 15 ? .orange : .green)
                }
                Text(limitMessage(maxPorts, xhci)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func controllerCard(_ c: USBController) -> some View {
        let active = c.ports.filter { $0.used }.count
        let shown = onlyUsed ? c.ports.filter { $0.used } : c.ports
        let summary = "\(c.ports.count) " + tr("porte totali") + " / \(active) " + tr("attive")
        return Card(c.title, icon: "cable.connector") {
            HStack {
                Text("\(c.vendor)  ·  \(c.idString)  ·  \(c.location)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Chip(summary, tint: .orange)
            }
            if c.ports.isEmpty {
                Text(tr("Nessuna porta USB trovata nel registro")).foregroundStyle(.secondary)
            }
            ForEach(shown) { p in
                Divider()
                portRow(p)
            }
        }
    }

    private func portRow(_ p: USBPort) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(p.used ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(p.name).font(.system(.callout, design: .monospaced)).fontWeight(.bold)
                    Chip(tr("Porta") + " \(p.number)")
                    Text(p.connectorText).font(.caption).foregroundStyle(.secondary)
                }
                if p.used {
                    HStack(spacing: 6) {
                        Text(p.deviceName).fontWeight(.medium)
                        Chip(p.deviceID)
                        if !p.speed.isEmpty { Text("· " + p.speed).font(.caption).foregroundStyle(.secondary) }
                    }
                } else {
                    Text(tr("Porta libera")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
