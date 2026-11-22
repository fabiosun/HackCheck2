import SwiftUI
import AppKit

enum Brand {
    /// Logo macOS86 (PNG con trasparenza, testo bianco: va mostrato su fondo scuro).
    static let logo: NSImage? = {
        guard let p = Bundle.main.path(forResource: "logo_macOS86", ofType: "png") else { return nil }
        return NSImage(contentsOfFile: p)
    }()

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    static var versionLabel: String {
        let v = appVersion, b = appBuild
        if v.isEmpty { return "" }
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    static var buildLabel: String {
        let b = appBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? appVersion : b
    }
}

enum Credits {
    static func join(_ names: [String]) -> String { names.joined(separator: tr(" e ")) }

    static var lines: [(String, String)] {
        [
            (tr("Creatori"), join(["Gengik84", "foskvs"])),
            (tr("Icona originale"), join(["Ciro82", "fabiosun"])),
            (tr("App restaurata da"), join(["fabiosun", "anto65"])),
        ]
    }
}

/// Logo macOS86 trasparente e centrato.
struct LogoBadge: View {
    var height: CGFloat = 64

    @ViewBuilder
    private var logo: some View {
        if let img = Brand.logo {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
        } else {
            Text("macOS86").font(.headline)
        }
    }

    var body: some View {
        logo
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .help("macOS86 · " + tr("la comunità italiana Hackintosh"))
            .onTapGesture {
                if let u = URL(string: "https://www.macos86.it") { NSWorkspace.shared.open(u) }
            }
    }
}

/// Solo la scritta HackCheck, nel colore della pagina selezionata.
struct BrandMark: View {
    var tint: Color = .accentColor

    var body: some View {
        Text("HackCheck")
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            .animation(.easeInOut(duration: 0.25), value: tint)
    }
}

/// Pannello «Informazioni su HackCheck».
enum AboutPanel {
    private static var window: NSWindow?

    private static let profiles: [(String, String?)] = [
        ("Gengik84", "https://github.com/Gengik84"),
        ("foskvs", "https://github.com/foskvs"),
        ("Ciro82", "https://github.com/Ciro82"),
        ("fabiosun", "https://github.com/fabiosun"),
        ("Anto65", "https://github.com/Anto65"),
    ]

    private struct PersonLink: View {
        let name: String
        let url: String?
        var body: some View {
            if let url, let u = URL(string: url) {
                Link(name, destination: u)
            } else {
                Text(name)
            }
        }
    }

    private struct PeopleRow: View {
        let prefix: String
        let names: [String]
        let profiles: [String: String]
        var body: some View {
            HStack(spacing: 0) {
                Text(prefix)
                ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                    if i > 0 { Text(tr(" e ")) }
                    PersonLink(name: n, url: profiles[n])
                }
            }
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct AboutView: View {
        @AppStorage("appearance") private var appearance = 0

        private var profileMap: [String: String] {
            var m: [String: String] = [:]
            for (n, u) in profiles { if let u { m[n] = u } }
            return m
        }
        private var version: String { Brand.versionLabel }

        var body: some View {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HackCheck").font(.system(size: 24, weight: .bold))
                        if !version.isEmpty {
                            Text(tr("Versione") + " " + version)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                VStack(spacing: 8) {
                    PeopleRow(prefix: tr("Ispirata all'app HackCheck originale di") + " ", names: ["Gengik84", "foskvs"], profiles: profileMap)
                    PeopleRow(prefix: tr("Icona originale") + ": ", names: ["Ciro82", "fabiosun"], profiles: profileMap)
                    PeopleRow(prefix: tr("App restaurata da") + " ", names: ["fabiosun", "Anto65"], profiles: profileMap)
                    PeopleRow(prefix: tr("Sviluppo assistito da") + " ", names: ["OpenCode (Big Pickle)"], profiles: [:])
                    HStack(spacing: 0) {
                        Text(tr("Database PCI") + ": PCI ID Repository (")
                        Link("pci-ids.ucw.cz", destination: URL(string: "https://pci-ids.ucw.cz")!)
                        Text(").")
                    }
                    .font(.system(size: 13))
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 4)
                Text("copyright macOS86 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
            .frame(width: 560, height: 340)
            .preferredColorScheme(appearance == 1 ? .light : (appearance == 2 ? .dark : nil))
        }
    }

    @MainActor
    static func show() {
        let desiredAppearance: NSAppearance? = {
            switch UserDefaults.standard.integer(forKey: "appearance") {
            case 1: return NSAppearance(named: .aqua)
            case 2: return NSAppearance(named: .darkAqua)
            default: return nil
            }
        }()
        if let w = window {
            w.appearance = desiredAppearance
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: AboutView())
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = tr("Informazioni su HackCheck")
        w.contentView = hosting
        w.appearance = desiredAppearance
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

/// Icona dell'app al centro, in fondo a «Dettagli di sistema».
struct AppIconFooter: View {
    var body: some View {
        HStack {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
            Spacer()
        }
        .padding(.vertical, 6)
        .background(.bar)
    }
}
