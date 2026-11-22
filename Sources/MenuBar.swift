import AppKit
import Combine
import Foundation
import ServiceManagement

// MARK: - Selezione dei sensori da esporre nella barra dei menu

/// La selezione è salvata come elenco di ID dei sensori (chiavi SMC, `SIO0`, GPU, dischi…).
/// Ogni riga della pagina Sensori può essere aggiunta/rimossa col tasto destro.
enum MenuBarSensorsData {
    static let storageKey = "menuBarSensorIDs"

    static func selectedIDs(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    static func isSelected(_ id: String, in raw: String) -> Bool {
        selectedIDs(raw).contains(id)
    }

    static func toggle(_ id: String, raw: inout String) {
        var ids = selectedIDs(raw)
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        raw = ids.sorted().joined(separator: ",")
    }

    static func compact(_ r: SensorReading) -> String {
        switch r.unit {
        case "RPM":   return String(format: "%.0f RPM", r.value)
        case "%":     return String(format: "%.0f%%", r.value)
        case "MHz":   return String(format: "%.0f MHz", r.value)
        case "V":     return String(format: "%.2f V", r.value)
        case "A":     return String(format: "%.2f A", r.value)
        case "W":     return String(format: "%.1f W", r.value)
        case "°C":    return String(format: "%.0f°", r.value)
        default:      return String(format: "%.0f°", r.value)
        }
    }

    static func full(_ r: SensorReading) -> String {
        switch r.unit {
        case "RPM", "%", "MHz": return String(format: "%.0f %@", r.value, r.unit)
        case "V", "A":          return String(format: "%.2f %@", r.value, r.unit)
        default:                return String(format: "%.1f %@", r.value, r.unit)
        }
    }

    /// Stessi simboli usati nelle card della pagina Sensori.
    static func symbol(_ r: SensorReading) -> String {
        switch r.category {
        case 0:   return "thermometer"
        case 6:   return "display"
        case 7:   return "internaldrive"
        case 1, 5: return "fan"
        case 2:   return "bolt"
        case 3:   return "powerplug"
        case 4:   return "bolt.horizontal"
        default:  return "gauge"
        }
    }
}

extension Notification.Name {
    static let hackCheckOpenMainWindow = Notification.Name("hackCheckOpenMainWindow")
}

// MARK: - Barra dei menu AppKit

/// `MenuBarExtra` con stile `.menu` non renderizza più `Image`+`Text` nella label:
/// mostrava solo la prima icona e nessun valore. Un `NSStatusItem` con
/// `attributedTitle` e allegati SF Symbol mostra invece icone e numeri insieme.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private weak var monitor: SensorMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var defaultsObserver: NSObjectProtocol?

    private override init() { super.init() }

    func start(monitor: SensorMonitor) {
        self.monitor = monitor
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        }
        update()

        monitor.$readings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.update() }
            }
            .store(in: &cancellables)

        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.update() }
            }
        }
    }

    private var selectedReadings: [SensorReading] {
        guard let monitor else { return [] }
        let raw = UserDefaults.standard.string(forKey: MenuBarSensorsData.storageKey) ?? ""
        let ids = MenuBarSensorsData.selectedIDs(raw)
        return monitor.readings.filter { ids.contains($0.id) }
    }

    private func update() {
        guard let button = statusItem?.button else { return }

        let all = selectedReadings
        let shown = Array(all.prefix(6))
        let title = NSMutableAttributedString(string: "HackCheck")

        for r in shown {
            title.append(NSAttributedString(string: "  "))
            if let attachment = symbolAttachment(for: r) {
                title.append(NSAttributedString(attachment: attachment))
                title.append(NSAttributedString(string: " "))
            }
            title.append(NSAttributedString(string: MenuBarSensorsData.compact(r)))
        }
        if all.count > shown.count {
            title.append(NSAttributedString(string: "  +\(all.count - shown.count)"))
        }

        let fullRange = NSRange(location: 0, length: title.length)
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        title.addAttribute(.font, value: font, range: fullRange)
        title.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        button.attributedTitle = title
        statusItem?.menu = makeMenu()
    }

    private func symbolAttachment(for r: SensorReading) -> NSTextAttachment? {
        guard let base = NSImage(systemSymbolName: MenuBarSensorsData.symbol(r),
                                 accessibilityDescription: nil) else { return nil }
        let image = base.copy() as! NSImage
        image.size = NSSize(width: 12, height: 12)
        image.isTemplate = true
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
        return attachment
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let readings = selectedReadings

        if readings.isEmpty {
            let item = NSMenuItem(title: tr("Nessun sensore nella barra dei menu"),
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for r in readings {
                let item = NSMenuItem()
                item.title = "\(r.name)  \(MenuBarSensorsData.full(r))"
                item.image = NSImage(systemSymbolName: MenuBarSensorsData.symbol(r),
                                     accessibilityDescription: nil)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(tr("Apri HackCheck"), action: #selector(openMainWindow)))
        menu.addItem(actionItem(tr("Impostazioni…"), action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(actionItem(tr("Esci"), action: #selector(quit)))
        return menu
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let mainWindows = NSApp.windows.filter { window in
            if let id = window.identifier?.rawValue { return id.contains("main") }
            return window.title == "HackCheck"
        }
        if mainWindows.isEmpty {
            NotificationCenter.default.post(name: .hackCheckOpenMainWindow, object: nil)
        } else {
            mainWindows.forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Avvio all'accesso

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
