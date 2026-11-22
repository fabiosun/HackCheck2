import SwiftUI
import AppKit

// MARK: - Modello del feed update.json

/// Struttura del file `update.json` pubblicato nel repository GitHub.
/// I campi opzionali permettono di pubblicare un feed minimo senza rompere l'app.
struct UpdateInfo: Decodable, Identifiable {
    let version: String
    let build: String?
    let minOS: String?
    let published: String?
    let notes: [String: [String]]?
    let pageURL: String?
    let downloadURL: String?
    let sha256: String?

    var id: String { version }

    /// Note localizzate: lingua scelta → inglese → italiano → prima disponibile.
    var localizedNotes: [String] {
        guard let notes else { return [] }
        return notes[Lang.code] ?? notes["en"] ?? notes["it"] ?? notes.values.first ?? []
    }
}

// MARK: - Checker

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let repoKey = "updateRepo"
    static let autoKey = "autoCheckUpdates"
    static let skipKey = "skippedUpdateVersion"
    static let lastCheckKey = "lastUpdateCheck"

    /// Repository GitHub dell'app. Cambiabile da Impostazioni → Aggiornamenti.
    static let defaultRepo = "fabiosun/HackCheck2"
    static let feedPath = "update.json"

    @Published var available: UpdateInfo?
    @Published var isChecking = false
    @Published var message = ""

    /// Accetta `utente/repo`, ma anche l'URL completo copiato da GitHub.
    static var repo: String {
        let raw = UserDefaults.standard.string(forKey: repoKey) ?? defaultRepo
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "github.com/"] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return s.isEmpty ? defaultRepo : s
    }

    var feedURL: URL? {
        URL(string: "https://raw.githubusercontent.com/\(Self.repo)/main/\(Self.feedPath)")
    }

    /// Controllo automatico: solo se attivo e non già fatto nelle ultime 24 ore.
    func checkIfNeeded() async {
        if !UserDefaults.standard.bool(forKey: Self.autoKey) { return }
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        await check(force: false)
    }

    func check(force: Bool = true) async {
        guard !isChecking else { return }
        isChecking = true
        message = ""
        defer { isChecking = false }

        guard let url = feedURL else {
            message = tr("URL feed aggiornamenti non valido")
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
            guard !info.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw URLError(.badServerResponse)
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

            let current = Brand.buildLabel
            let skipped = UserDefaults.standard.string(forKey: Self.skipKey) ?? ""
            if Self.isNewer(info.version, than: current), info.version != skipped {
                available = info
            } else {
                available = nil
                message = tr("HackCheck è aggiornato") + " · " + current
            }
        } catch {
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            available = nil
            message = tr("Impossibile controllare gli aggiornamenti") + ": " + error.localizedDescription
        }
    }

    func skipThisVersion() {
        guard let v = available?.version else { return }
        UserDefaults.standard.set(v, forKey: Self.skipKey)
        available = nil
    }

    func openRelease() {
        guard let s = available?.pageURL, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }

    func download() {
        guard let s = available?.downloadURL, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }

    func openReleasesPage() {
        guard let url = URL(string: "https://github.com/\(Self.repo)/releases") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Confronta versioni numeriche (`2.8.0` > `2.7.9`), tollerando suffissi non numerici.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let parts: (String) -> [Int] = { s in
            s.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        let n = max(x.count, y.count)
        guard n > 0 else { return false }
        for i in 0..<n {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

// MARK: - Finestra "Aggiornamento disponibile"

struct UpdateAvailableView: View {
    @ObservedObject var updater: UpdateChecker
    let info: UpdateInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Aggiornamento disponibile"))
                        .font(.title3.weight(.semibold))
                    Text(tr("Versione installata") + " \(Brand.buildLabel)  →  \(info.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !info.localizedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(info.localizedNotes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .padding(.top, 1)
                            Text(note).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text(tr("La build è firmata ad-hoc: se macOS blocca l'app, tieni premuto Control e scegli Apri."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(tr("Ignora questa versione")) { updater.skipThisVersion() }
                Button(tr("Non ora")) { updater.available = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(tr("Apri release")) { updater.openRelease() }
                Button(tr("Scarica DMG")) { updater.download() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
        .modifier(ThemeRoot())
    }
}
