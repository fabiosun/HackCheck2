import SwiftUI
import AppKit

enum Page: String, CaseIterable, Identifiable {
    case overview, cpu, sensors, graphics, network, audio, storage, usb, pci, deviceProps, kext, boot, acpi, profiler
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return tr("Panoramica")
        case .cpu: return tr("CPU e memoria")
        case .sensors: return tr("Sensori")
        case .graphics: return tr("Grafica")
        case .network: return tr("Rete e Wi-Fi")
        case .audio: return tr("Audio")
        case .storage: return tr("Archiviazione")
        case .usb: return tr("USB")
        case .pci: return tr("Dispositivi PCI")
        case .kext: return tr("Kext")
        case .boot: return tr("Boot e SIP")
        case .deviceProps: return "Device Properties"
        case .acpi: return tr("ACPI")
        case .profiler: return tr("Dettagli di sistema")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .cpu: return "cpu"
        case .sensors: return "thermometer"
        case .graphics: return "display"
        case .network: return "network"
        case .audio: return "speaker.wave.2"
        case .storage: return "internaldrive"
        case .usb: return "cable.connector"
        case .pci: return "rectangle.connected.to.line.below"
        case .kext: return "puzzlepiece.extension"
        case .boot: return "power"
        case .deviceProps: return "slider.horizontal.3"
        case .acpi: return "exclamationmark.triangle"
        case .profiler: return "list.bullet.rectangle"
        }
    }

    var color: Color {
        switch self {
        case .overview: return .blue
        case .cpu: return .orange
        case .sensors: return .mint
        case .graphics: return .purple
        case .network: return .cyan
        case .audio: return .pink
        case .storage: return .green
        case .usb: return .indigo
        case .pci: return .teal
        case .kext: return .brown
        case .boot: return .red
        case .deviceProps: return .blue
        case .acpi: return .yellow
        case .profiler: return .gray
        }
    }

    /// I titoli dei gruppi sono chiavi italiane: si traducono al momento di mostrarli (tr).
    static let groups: [(String, [Page])] = [
        ("Sistema", [.overview, .cpu, .sensors]),
        ("Hardware", [.graphics, .network, .audio, .storage, .usb, .pci]),
        ("Hackintosh", [.deviceProps, .kext, .boot, .acpi]),
        ("Altro", [.profiler]),
    ]
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: UpdateChecker
    @Environment(\.openWindow) private var openWindow
    @State private var page: Page? = .overview
    @AppStorage("theme") private var theme = 1
    @AppStorage("lang") private var lang = Lang.defaultCode
    @AppStorage("lastSeenVersion") private var lastSeenVersion = ""
    @State private var showUpdateNotice = false

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                ForEach(Page.groups, id: \.0) { group in
                    Section(tr(group.0)) {
                        ForEach(group.1) { p in
                            Label {
                                Text(p.title)
                            } icon: {
                                if theme == 1 {
                                    GelOrb(symbol: p.icon, color: p.color, size: 22)
                                } else {
                                    Image(systemName: p.icon)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(p.color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                            .tag(p)
                        }
                    }
                }
            }
            .modifier(AquaSidebarBG())
            .safeAreaInset(edge: .bottom) { LogoBadge(height: 54) }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
        } detail: {
            detail(page ?? .overview)
                .navigationTitle((page ?? .overview).title)
                .environment(\.pageTint, (page ?? .overview).color)
                .tint((page ?? .overview).color)
                .modifier(DetailBackground(color: (page ?? .overview).color))
        }
        // Cambiando lingua l'albero viene ricostruito: tutte le tr() vengono rivalutate.
        .id(lang)
        .modifier(ThemeRoot())
        .toolbar { topToolbar }
        // Alcune stringhe (es. nomi sconosciuti, valori delle proprietà) sono tradotte durante la raccolta dati.
        .onChange(of: lang) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .hackCheckOpenMainWindow)) { _ in
            openWindow(id: "main")
        }
        .onAppear { checkUpdateNotice() }
        .task { await updater.checkIfNeeded() }
        .sheet(isPresented: $showUpdateNotice) {
            UpdateNoticeView(version: Brand.versionLabel, notes: UpdateNotice.currentNotes) {
                lastSeenVersion = Brand.buildLabel
                showUpdateNotice = false
            }
        }
        .sheet(item: $updater.available) { info in
            UpdateAvailableView(updater: updater, info: info)
        }
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        // macOS Tahoe avvolge gli item della toolbar in un fondino "Liquid Glass" a forma di capsule.
        // Lo nascondiamo solo per il titolo, lasciando il testo HackCheck senza sfondo.
        if #available(macOS 26, *) {
            ToolbarItem(placement: .principal) {
                BrandMark(tint: (page ?? .overview).color)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) {
                BrandMark(tint: (page ?? .overview).color)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { copyCurrentPage() } label: {
                Label(tr("Copia"), systemImage: "doc.on.doc")
            }
            .help(tr("Copia le informazioni della scheda aperta"))
            Button { store.refresh() } label: {
                if store.loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
            }
            .help(tr("Aggiorna (⌘R)"))
        }
    }

    private func checkUpdateNotice() {
        let current = Brand.buildLabel
        guard !current.isEmpty else { return }
        if lastSeenVersion.isEmpty {
            let d = UserDefaults.standard
            let knownKeys = ["appearance", "theme", "lang", "maskSerial", "usbOnlyUsed", "kextOnlyInstalled", "efiOnly"]
            let existingUser = knownKeys.contains { d.object(forKey: $0) != nil }
            if existingUser {
                showUpdateNotice = true
            } else {
                lastSeenVersion = current
            }
        } else if lastSeenVersion != current {
            showUpdateNotice = true
        }
    }

    private func copyCurrentPage() {
        let p = page ?? .overview
        Files.copy(Report.copyText(for: p, snapshot: store.snap, acpiScanned: store.acpiScanned, acpiErrors: store.acpiErrors))
    }

    @ViewBuilder
    private func detail(_ p: Page) -> some View {
        switch p {
        case .overview: OverviewView()
        case .cpu: CPUView()
        case .sensors: SensorsView()
        case .graphics: SummaryDetailPage(dataType: "SPDisplaysDataType") { GraphicsSummary() }
        case .network: SummaryDetailPage(dataType: "SPAirPortDataType") { NetworkSummary() }
        case .audio: SummaryDetailPage(dataType: "SPAudioDataType") { AudioSummary() }
        case .storage: SummaryDetailPage(dataType: "SPNVMeDataType") { StorageSummary() }
        case .usb: SummaryDetailPage(dataType: "SPUSBDataType") { USBSummary() }
        case .pci: PCIView()
        case .kext: KextView()
        case .boot: BootView()
        case .deviceProps: DevicePropsPage()
        case .acpi: ACPIView()
        case .profiler: ProfilerPage()
        }
    }
}
