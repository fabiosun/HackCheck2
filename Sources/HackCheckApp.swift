import SwiftUI
import AppKit

/// Fa sì che il pulsante rosso di chiusura termini realmente l'app,
/// invece di lasciarla attiva solo nella barra dei menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var snap = Snapshot()
    @Published var loading = false
    @Published var pciMessage = ""
    @Published var acpiErrors: [String] = []
    @Published var acpiScanned = false

    func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            let s = await Task.detached(priority: .userInitiated) { Collector.collect() }.value
            self.snap = s
            self.loading = false
        }
    }

    func updatePCIIDs() {
        pciMessage = tr("Download in corso…")
        Task {
            do {
                try await PCIIDDatabase.shared.update()
                pciMessage = tr("pci.ids aggiornato")
                refresh()
            } catch {
                pciMessage = tr("Aggiornamento non riuscito") + ": " + error.localizedDescription
            }
        }
    }
}

@main
struct HackCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()
    /// Unico monitor condiviso tra pagina Sensori e barra dei menu: così le letture
    /// aggiunte col tasto destro sono sempre le stesse mostrate nella barra.
    @StateObject private var sensors = SensorMonitor()
    @StateObject private var updater = UpdateChecker.shared
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("lang") private var lang = Lang.defaultCode
    @AppStorage("theme") private var theme = 1

    var body: some Scene {
        WindowGroup("HackCheck", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(sensors)
                .environmentObject(updater)
                .environment(\.locale, Locale(identifier: lang))
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(appearance == 1 ? .light : (appearance == 2 ? .dark : nil))
                .task {
                    store.refresh()
                    sensors.start()
                    MenuBarController.shared.start(monitor: sensors)
                }
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button(tr("Informazioni su HackCheck")) { AboutPanel.show() }
            }
            prefsCommands
            CommandGroup(after: .toolbar) {
                Button(tr("Aggiorna")) { store.refresh() }.keyboardShortcut("r")
            }
        }
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(updater)
                .environment(\.locale, Locale(identifier: lang))
        }
        .commands { prefsCommands }
    }

    /// Comandi globali per lingua, aspetto e stile: aggiunti a ogni scena così funzionano
    /// sia nella finestra principale (qualunque pagina) sia nella finestra Impostazioni.
    @CommandsBuilder
    private var prefsCommands: some Commands {
        CommandMenu(tr("Aspetto")) {
            Button(tr("Lingua ITA / EN")) {
                lang = (lang == "en") ? "it" : "en"
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button(tr("Aspetto Light / Dark")) {
                appearance = (appearance == 2) ? 1 : 2
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button(tr("Aspetto sistema")) {
                appearance = 0
            }
            .keyboardShortcut("a", modifiers: [.command, .option])

            Button(tr("Stile Aqua / Moderno")) {
                theme = (theme == 1) ? 0 : 1
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }

        CommandGroup(after: .appInfo) {
            Button(tr("Controlla aggiornamenti…")) {
                NotificationCenter.default.post(name: .hackCheckOpenMainWindow, object: nil)
                Task { await updater.check(force: true) }
            }
        }
    }
}

// MARK: - Utility file / appunti

enum Files {
    static func save(text: String, name: String) {
        let p = NSSavePanel()
        p.nameFieldStringValue = name
        if p.runModal() == .OK, let u = p.url { try? text.write(to: u, atomically: true, encoding: .utf8) }
    }
    static func save(data: Data, name: String) {
        let p = NSSavePanel()
        p.nameFieldStringValue = name
        if p.runModal() == .OK, let u = p.url { try? data.write(to: u) }
    }
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: UpdateChecker
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("maskSerial") private var mask = true
    @AppStorage("theme") private var theme = 1
    @AppStorage("lang") private var lang = Lang.defaultCode
    @AppStorage(MenuBarSensorsData.storageKey) private var pinnedIDs = ""
    @AppStorage(UpdateChecker.repoKey) private var updateRepo = UpdateChecker.defaultRepo
    @AppStorage(UpdateChecker.autoKey) private var autoCheckUpdates = true
    @State private var loginStatus = LoginItem.status
    @State private var loginError = ""

    var body: some View {
        Form {
            Picker(tr("Lingua"), selection: $lang) {
                Text("Italiano").tag("it")
                Text("English").tag("en")
            }
            Picker(tr("Stile"), selection: $theme) {
                Text(tr("Moderno")).tag(0)
                Text("Aqua").tag(1)
            }
            Picker(tr("Aspetto"), selection: $appearance) {
                Text(tr("Sistema")).tag(0)
                Text(tr("Chiaro")).tag(1)
                Text(tr("Scuro")).tag(2)
            }
            Toggle(tr("Nascondi seriale e UUID nella panoramica"), isOn: $mask)
            LabeledContent(tr("Database PCI")) {
                VStack(alignment: .trailing) {
                    Button(tr("Aggiorna pci.ids da internet")) { store.updatePCIIDs() }
                    if !store.pciMessage.isEmpty { Text(store.pciMessage).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Text(PCIIDDatabase.shared.sourcePath).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)

            Section(tr("Aggiornamenti")) {
                Toggle(tr("Controlla automaticamente all'avvio"), isOn: $autoCheckUpdates)
                LabeledContent(tr("Ultimo controllo")) { Text(lastCheckText).foregroundStyle(.secondary) }
                HStack {
                    Button(tr("Controlla ora")) {
                        Task { await updater.check(force: true) }
                    }
                    .disabled(updater.isChecking)
                    if updater.isChecking { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(tr("Apri pagina Release")) { updater.openReleasesPage() }
                }
                if !updater.message.isEmpty {
                    Text(updater.message).font(.caption).foregroundStyle(.secondary)
                }
                TextField(tr("Repository GitHub (utente/repo)"), text: $updateRepo)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .autocorrectionDisabled()
                Text(tr("Deve puntare al file update.json pubblicato sul branch main di GitHub."))
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Section(tr("Avvio")) {
                Toggle(tr("Avvia all'accesso"), isOn: Binding(
                    get: { loginStatus == .enabled },
                    set: { newValue in
                        do {
                            try LoginItem.set(newValue)
                            loginStatus = LoginItem.status
                            loginError = ""
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                ))
                if loginStatus == .requiresApproval {
                    Text(tr("Approva l'app in Impostazioni di Sistema › Generale › Elementi di accesso."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !loginError.isEmpty {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section(tr("Sensori nella barra dei menu")) {
                Text(tr("Clicca con il tasto destro su una voce nella pagina Sensori per aggiungerla o rimuoverla dalla barra dei menu."))
                    .font(.caption).foregroundStyle(.secondary)
                if !MenuBarSensorsData.selectedIDs(pinnedIDs).isEmpty {
                    Button(tr("Rimuovi tutti i sensori dalla barra")) { pinnedIDs = "" }
                }
            }

            Section(tr("Scorciatoie da tastiera")) {
                LabeledContent(tr("Lingua ITA / EN")) { Text("⌘⇧L").foregroundStyle(.secondary) }
                LabeledContent(tr("Aspetto Light / Dark")) { Text("⌘⇧A").foregroundStyle(.secondary) }
                LabeledContent(tr("Aspetto sistema")) { Text("⌘⌥A").foregroundStyle(.secondary) }
                LabeledContent(tr("Stile Aqua / Moderno")) { Text("⌘⇧M").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear { loginStatus = LoginItem.status }
        .modifier(ThemeRoot())
        .id(lang)
    }

    private var lastCheckText: String {
        guard let d = UserDefaults.standard.object(forKey: UpdateChecker.lastCheckKey) as? Date else {
            return tr("Mai")
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: Lang.code)
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}
