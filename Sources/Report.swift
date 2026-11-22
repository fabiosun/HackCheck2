import Foundation

enum Report {
    /// Report testuale per forum/GitHub. Non include seriale né UUID. Segue la lingua scelta nell'app.
    static func text(_ s: Snapshot) -> String {
        var o = "# HackCheck report\n\n"
        o += "## " + tr("Sistema") + "\n"
        o += "- " + tr("Modello") + ": \(s.system.model)\n- \(s.system.macOSName) \(s.system.macOS) (\(s.system.build))\n- Kernel: \(s.system.kernel)\n"
        o += "- Bootloader: \(s.boot.loaderName) \(s.boot.loaderVersion)\n- SIP: \(s.boot.sipStatusDisplay.isEmpty ? s.boot.sipStatus : s.boot.sipStatusDisplay) \(s.boot.csrHex)\n- boot-args: \(s.boot.bootArgs)\n\n"
        o += "## CPU / RAM\n- \(s.cpu.brand)\n- " + tr("Core/thread") + ": \(s.cpu.cores)/\(s.cpu.threads)\n- RAM: \(s.cpu.ram)\n\n"
        o += "## GPU\n"
        for g in s.gpus { o += "- \(g.vendor) \(g.name) [\(g.pciID)] \(g.link)\n" }
        o += "- Metal: \(s.metalDevices.joined(separator: ", "))\n"
        for k in s.codecs { o += "- \(k.name): \(k.supported ? "hardware" : "software")\n" }
        o += "\n## " + tr("Rete") + "\n"
        for n in s.network {
            o += "- \(n.bsd) \(n.port) – driver \(n.controller) – built-in: " + (n.builtIn ? tr("sì") : "no") + "\n"
        }
        o += "\n## Audio\n"
        for c in s.audioCodecs { o += "- Codec: \(c)\n" }
        for a in s.audio { o += "- \(a.name) layout-id \(a.layoutID)\n" }
        for d in s.audioDevices { o += "- " + tr("Dispositivo") + ": \(d.name) \(d.manufacturer) \(d.transport)\n" }
        o += "\n## " + tr("Dispositivi PCI") + "\n```\n" + s.pci.map { $0.lspci }.joined(separator: "\n") + "\n```\n\n"
        o += "## " + tr("Kext non Apple") + "\n" + s.kexts.map { "- \($0.id) \($0.version)" }.joined(separator: "\n") + "\n\n"
        o += "## " + tr("Controlli") + "\n" + s.checks.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n") + "\n"
        return o
    }

    /// Sezioni aggiuntive (CPU, RAM, USB, Device Properties, diagnostica bootloader) per il report completo.
    static func extras(_ s: Snapshot) -> String {
        var o = "\n## " + tr("Processore") + "\n- \(s.cpu.brand)\n"
        if !s.cpu.microarch.isEmpty {
            o += "- " + s.cpu.microarch + (s.cpu.generation.isEmpty ? "" : " (\(s.cpu.generation))") + "\n"
        }
        o += "\n## " + tr("Moduli RAM") + "\n"
        for m in s.memory { o += "- \(m.slot): \(m.manufacturer) \(m.size) \(m.speed) \(m.type) \(m.partNumber)\n" }
        o += "\n## USB\n"
        for c in s.usb {
            o += "- \(c.title) [\(c.idString)]\n"
            for p in c.ports {
                var line = "    \(p.name) (\(p.connectorText))"
                if p.used { line += ": \(p.deviceName) [\(p.deviceID)] \(p.speed)" }
                o += line + "\n"
            }
        }
        o += "\n## Device Properties\n"
        for g in s.boot.deviceProps {
            o += "- \(g.path)\n"
            for r in g.rows { o += "    \(r.key) = \(r.value)\n" }
        }
        o += "\n## Bootloader\n" + s.boot.signals.map { "- \($0)" }.joined(separator: "\n") + "\n"
        return o
    }

    static func copyText(for page: Page, snapshot s: Snapshot, acpiScanned: Bool = false, acpiErrors: [String] = []) -> String {
        switch page {
        case .overview:
            return text(s)
        case .cpu:
            var o = "# " + tr("CPU e memoria") + "\n\n"
            o += "## " + tr("Processore") + "\n- \(s.cpu.brand)\n"
            if !s.cpu.vendor.isEmpty { o += "- " + tr("Produttore") + ": \(s.cpu.vendor)\n" }
            if !s.cpu.microarch.isEmpty { o += "- \(s.cpu.microarch)\n" }
            if !s.cpu.generation.isEmpty { o += "- \(s.cpu.generation)\n" }
            o += "- " + tr("Core/thread") + ": \(s.cpu.cores)/\(s.cpu.threads)\n"
            o += "- Family/Model/Stepping: \(s.cpu.family)/\(s.cpu.model)/\(s.cpu.stepping)\n"
            if !s.cpu.l2.isEmpty { o += "- L2: \(s.cpu.l2)\n" }
            if !s.cpu.l3.isEmpty { o += "- L3: \(s.cpu.l3)\n" }
            o += "- RAM: \(s.cpu.ram)\n\n"
            o += "## " + tr("Moduli RAM") + "\n"
            if s.memory.isEmpty {
                o += "- —\n"
            } else {
                for m in s.memory { o += "- \(m.slot): \(m.manufacturer) \(m.size) \(m.speed) \(m.type) \(m.partNumber)\n" }
            }
            if !s.cpu.features.isEmpty {
                o += "\n## " + tr("Istruzioni supportate") + "\n" + s.cpu.features.joined(separator: " ") + "\n"
            }
            return o
        case .sensors:
            var o = "# " + tr("Sensori") + "\n\n"
            var readings: [SensorReading] = []
            if let smc = SMCConnection() {
                let keys = SensorReader.enumerate(smc)
                readings = SensorReader.readAll(smc, keys)
            }
            readings += ExtraSensors.gpuReadings()
            readings += ExtraSensors.diskReadings()
            if let sio = AMDSuperIOFans.read() {
                readings += sio.fans.enumerated().map { i, f in
                    let mode = f.autoMode ? "Auto" : "PWM \(f.throttle)%"
                    return SensorReading(id: "SIO\(i)", name: "\(f.name) · \(mode)", value: Double(f.rpm), unit: "RPM", category: 1)
                }
            }
            if readings.isEmpty {
                o += tr("Nessun sensore SMC trovato") + "\n"
            } else {
                let cats = [(0, tr("Temperature")), (6, tr("GPU")), (7, tr("Dischi")), (1, tr("Ventole")), (5, tr("Ventole GPU")), (2, tr("Tensioni")), (3, tr("Potenza")), (4, tr("Corrente"))]
                for (idx, name) in cats {
                    let items = readings.filter { $0.category == idx }
                    if items.isEmpty { continue }
                    o += "## \(name)\n"
                    for r in items {
                        let val: String
                        switch r.unit {
                        case "RPM", "%", "MHz": val = String(format: "%.0f", r.value)
                        case "V", "A": val = String(format: "%.2f", r.value)
                        default: val = String(format: "%.1f", r.value)
                        }
                        let ids = ([r.id] + r.aliases).joined(separator: " · ")
                        o += "- \(r.name) [\(ids)]: \(val) \(r.unit)\n"
                    }
                    o += "\n"
                }
            }
            return o
        case .graphics:
            var o = "# " + tr("Grafica") + "\n\n"
            for g in s.gpus {
                o += "## \(g.name)\n"
                if !g.vendor.isEmpty { o += "- " + tr("Produttore") + ": \(g.vendor)\n" }
                if !g.pciID.isEmpty { o += "- ID PCI: \(g.pciID)\n" }
                if !g.location.isEmpty { o += "- " + tr("Posizione") + ": \(g.location)\n" }
                if !g.link.isEmpty { o += "- Link PCIe: \(g.link)\n" }
                if !g.accelerator.isEmpty { o += "- " + tr("Acceleratore") + ": \(g.accelerator)\n" }
                if !g.metalPlugin.isEmpty { o += "- " + tr("Plugin Metal") + ": \(g.metalPlugin)\n" }
                if !g.platformID.isEmpty { o += "- ig-platform-id: \(g.platformID)\n" }
                if !g.gvaCodec.isEmpty { o += "- Codec GVA: \(g.gvaCodec)\n" }
                o += "\n"
            }
            o += "## Metal\n- " + (s.metalDevices.isEmpty ? "—" : s.metalDevices.joined(separator: ", ")) + "\n\n"
            o += "## " + tr("Decodifica video hardware") + "\n"
            for k in s.codecs { o += "- \(k.name): \(k.supported ? "Hardware" : "Software")\n" }
            return o
        case .network:
            var o = "# " + tr("Rete e Wi-Fi") + "\n\n"
            for n in s.network {
                o += "- \(n.bsd) \(n.port)\n"
                if !n.mac.isEmpty { o += "  MAC: \(n.mac)\n" }
                if !n.ip.isEmpty { o += "  IP: \(n.ip)\n" }
                if !n.controller.isEmpty { o += "  Driver: \(n.controller)\n" }
                o += "  Built-in: " + (n.builtIn ? tr("sì") : "no") + "\n"
            }
            let nets = s.pci.filter { $0.baseClass == 0x02 }
            if !nets.isEmpty {
                o += "\n## " + tr("Schede di rete PCI") + "\n"
                for d in nets { o += "- \(d.lspci)\n" }
            }
            return o
        case .audio:
            var o = "# Audio\n\n## Codec HDA\n"
            if s.audioCodecs.isEmpty { o += "- —\n" } else { for c in s.audioCodecs { o += "- \(c)\n" } }
            o += "\n## " + tr("Controller audio PCI") + "\n"
            if s.audio.isEmpty { o += "- —\n" }
            for a in s.audio {
                o += "- \(a.name) (\(a.vendor), \(a.location))"
                if !a.layoutID.isEmpty { o += " layout-id \(a.layoutID)" }
                if !a.driver.isEmpty { o += " driver \(a.driver)" }
                o += "\n"
            }
            o += "\n## " + tr("Dispositivi audio") + "\n"
            if s.audioDevices.isEmpty { o += "- —\n" }
            for d in s.audioDevices {
                let meta = [d.manufacturer, d.transport, d.source].filter { !$0.isEmpty }.joined(separator: " · ")
                o += "- \(d.name)" + (meta.isEmpty ? "" : " (\(meta))") + "\n"
            }
            return o
        case .storage:
            var o = "# " + tr("Archiviazione") + "\n\n## " + tr("Controller di archiviazione") + "\n"
            let ctrl = s.pci.filter { $0.baseClass == 0x01 }
            if ctrl.isEmpty { o += "- —\n" }
            for d in ctrl {
                o += "- \(d.lspci)\n"
                if !d.linkStatus.isEmpty { o += "  Link: \(d.linkStatus)\n" }
            }
            return o
        case .usb:
            var o = "# USB\n\n"
            if s.usb.isEmpty {
                let hosts = s.pci.filter { $0.subClass16 == 0x0C03 }
                for h in hosts { o += "- \(h.lspci)\n" }
            }
            for c in s.usb {
                o += "## \(c.title)\n- \(c.vendor)  \(c.idString)  \(c.location)\n"
                for p in c.ports {
                    var line = "- \(p.name) (" + tr("Porta") + " \(p.number), \(p.connectorText))"
                    if p.used { line += ": \(p.deviceName) [\(p.deviceID)] \(p.speed)" }
                    else { line += ": " + tr("Porta libera") }
                    o += line + "\n"
                }
                o += "\n"
            }
            return o
        case .pci:
            var o = "# " + tr("Dispositivi PCI") + "\n\n```\n"
            o += s.pci.map { $0.lspci }.joined(separator: "\n")
            o += "\n```\n"
            return o
        case .kext:
            var o = "# Kext\n\n"
            for k in s.kexts { o += "- \(k.id) \(k.version)\n" }
            return o
        case .boot:
            let b = s.boot
            var o = "# " + tr("Boot e SIP") + "\n\n"
            o += "- Bootloader: \(b.loaderName) \(b.loaderVersion)\n"
            if !b.loaderSource.isEmpty { o += "- " + tr("Rilevato da") + ": \(b.loaderSource)\n" }
            o += "- SIP: \(b.sipStatusDisplay.isEmpty ? b.sipStatus : b.sipStatusDisplay) \(b.csrHex)\n"
            if !b.csrFlags.isEmpty { o += "- CSR flags: \(b.csrFlags.joined(separator: ", "))\n" }
            o += "- boot-args: \(b.bootArgs)\n\n"
            if !b.signals.isEmpty {
                o += "## " + tr("Diagnostica rilevamento") + "\n"
                for sgn in b.signals { o += "- \(sgn)\n" }
            }
            return o
        case .deviceProps:
            let r = DevPropsExport.groups(s)
            var o = "# Device Properties\n\n"
            if r.groups.isEmpty {
                o += s.boot.devicePropsNote + "\n"
            } else {
                for g in r.groups {
                    o += "## \(g.title)\n- \(g.path)\n"
                    for row in g.rows { o += "  \(row.key) = \(row.value)\n" }
                    o += "\n"
                }
            }
            return o
        case .acpi:
            var o = "# ACPI\n\n## " + tr("Dispositivi ACPI esposti a macOS") + "\n"
            for d in s.acpiDevices { o += "- \(d)\n" }
            o += "\n## " + tr("Errori ACPI nel log dell'ultimo avvio") + "\n"
            if acpiScanned {
                if acpiErrors.isEmpty {
                    o += tr("Nessun errore ACPI trovato") + "\n"
                } else {
                    for line in acpiErrors { o += line + "\n" }
                }
            } else {
                o += "-\n"
            }
            return o
        case .profiler:
            // Dati dettagliati per categoria caricati a richiesta nell'interfaccia.
            return "# " + tr("Dettagli di sistema") + "\n\n" + text(s)
        }
    }

    /// Redige seriale macchina e UUID hardware/provisioning nell'output testuale (es. system_profiler).
    static func redactSensitive(_ text: String) -> String {
        let labels = ["Serial Number (system)", "Hardware UUID", "Provisioning UDID", "Serial Number"]
        let keys = ["IOPlatformSerialNumber", "IOPlatformUUID", "platform UUID", "SystemUUID"]
        var out: [String] = []
        out.reserveCapacity(text.count / 40)
        for lineSub in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(lineSub)
            var redacted = false
            for label in labels where line.contains(label) {
                if let colon = line.firstIndex(of: ":") {
                    line = String(line[...colon]) + " [redacted]"
                    redacted = true
                    break
                }
            }
            if !redacted {
                for key in keys where line.contains(key) {
                    if let colon = line.firstIndex(of: ":") {
                        line = String(line[...colon]) + " [redacted]"
                        break
                    }
                }
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
