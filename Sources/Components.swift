import SwiftUI

private struct PageTintKey: EnvironmentKey { static let defaultValue: Color = .accentColor }
extension EnvironmentValues {
    var pageTint: Color {
        get { self[PageTintKey.self] }
        set { self[PageTintKey.self] = newValue }
    }
}

struct UnavailableView: View {
    let title: String
    let systemImage: String
    var description: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct Card<Content: View>: View {
    let title: String
    let icon: String
    let tintOverride: Color?
    let content: Content
    @Environment(\.pageTint) private var pageTint
    @Environment(\.colorScheme) private var scheme
    @AppStorage("theme") private var theme = 1

    init(_ title: String, icon: String, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tintOverride = tint
        self.content = content()
    }

    var body: some View {
        let t = tintOverride ?? pageTint
        let aqua = theme == 1
        let r: CGFloat = aqua ? 12 : 16
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if aqua {
                    GelOrb(symbol: icon, color: t, size: 28)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(t.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Text(title).font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            if aqua {
                ZStack {
                    RoundedRectangle(cornerRadius: r, style: .continuous).fill(LinearGradient(
                        colors: scheme == .dark ? [Color(white: 0.27), Color(white: 0.20)] : [.white, Color(white: 0.92)],
                        startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: r, style: .continuous).fill(LinearGradient(
                        colors: [t.opacity(0.22), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)))
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: r, style: .continuous).fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(LinearGradient(colors: [t.opacity(0.18), t.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
        }
        .overlay {
            if aqua {
                ZStack {
                    RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(.black.opacity(0.30), lineWidth: 1)
                    RoundedRectangle(cornerRadius: r, style: .continuous).inset(by: 1).strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.8), lineWidth: 1)
                }
            } else {
                RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(t.opacity(0.35))
            }
        }
        .shadow(color: .black.opacity(aqua ? 0.18 : 0), radius: aqua ? 4 : 0, y: aqua ? 2 : 0)
    }
}

struct KV: View {
    let k: String
    let v: String
    init(_ k: String, _ v: String) { self.k = k; self.v = v }

    var body: some View {
        if !v.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(k).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(v).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
            .font(.callout)
        }
    }
}

struct Chip: View {
    let text: String
    var tint: Color = .accentColor
    init(_ text: String, tint: Color = .accentColor) { self.text = text; self.tint = tint }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

extension CheckStatus {
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .ok: return .green
        case .warn: return .orange
        case .fail: return .red
        case .info: return .blue
        }
    }
}

struct CheckRow: View {
    let check: Check
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.status.symbol).foregroundStyle(check.status.color).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.title).fontWeight(.medium)
                Text(check.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

struct DeviceRow: View {
    let dev: PCIDevice
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dev.deviceName).fontWeight(.medium)
            Text("\(dev.vendorName)  ·  \(dev.idString)  ·  \(dev.location)")
                .font(.caption).foregroundStyle(.secondary)
            if !dev.drivers.isEmpty {
                Text("Driver: " + dev.drivers.joined(separator: ", ")).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pagina con due schede: riepilogo + dati grezzi di system_profiler.
struct SummaryDetailPage<Summary: View>: View {
    let dataType: String
    let summary: Summary
    @State private var tab = 0
    @AppStorage("theme") private var theme = 1

    init(dataType: String, @ViewBuilder summary: () -> Summary) {
        self.dataType = dataType
        self.summary = summary()
    }

    var body: some View {
        VStack(spacing: 0) {
            if theme == 1 {
                AquaTabs(selection: $tab, titles: [tr("Riepilogo"), tr("Dettagli macOS")]).padding(.vertical, 10)
            } else {
                Picker("", selection: $tab) {
                    Text(tr("Riepilogo")).tag(0)
                    Text(tr("Dettagli macOS")).tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280).padding(.vertical, 10)
            }
            Divider()
            if tab == 0 {
                ScrollView { summary.padding(24) }
            } else {
                ProfilerTreeView(dataType: dataType)
            }
        }
    }
}

// MARK: - system_profiler come albero

struct TreeNode: Identifiable {
    let id = UUID()
    var title: String
    var value: String?
    var children: [TreeNode]?
}

enum ProfilerLoader {
    static func load(_ type: String) async -> [TreeNode] {
        await Task.detached(priority: .userInitiated) { () -> [TreeNode] in
            let out = Shell.run("/usr/sbin/system_profiler", ["-json", type])
            guard let data = out.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let top = obj[type] else { return [] }
            return build(top, skipName: false)
        }.value
    }

    static func build(_ any: Any, skipName: Bool) -> [TreeNode] {
        if let arr = any as? [Any] {
            return arr.enumerated().map { (i, v) in
                let t = (v as? [String: Any])?["_name"] as? String
                return node(title: t ?? "#\(i + 1)", v, skipName: t != nil)
            }
        }
        if let d = any as? [String: Any] {
            return d.keys.sorted().filter { !(skipName && $0 == "_name") }.map { node(title: $0, d[$0]!, skipName: false) }
        }
        return []
    }

    static func node(title: String, _ v: Any, skipName: Bool) -> TreeNode {
        let t = title == "_items" ? tr("Elementi") : title
        if v is [Any] || v is [String: Any] {
            let kids = build(v, skipName: skipName)
            return TreeNode(title: t, value: nil, children: kids.isEmpty ? nil : kids)
        }
        return TreeNode(title: t, value: "\(v)", children: nil)
    }
}

struct FlatRow: Identifiable {
    let id: Int
    var title: String
    var value: String?
    var depth: Int
    var isHeader: Bool
}

/// Albero di system_profiler mostrato già tutto aperto (senza sotto-menu da espandere).
struct ProfilerTreeView: View {
    let dataType: String
    @State private var rows: [FlatRow] = []
    @State private var loading = true

    private static func flatten(_ nodes: [TreeNode], depth: Int, into out: inout [FlatRow]) {
        for n in nodes {
            out.append(FlatRow(id: out.count, title: n.title, value: n.value, depth: depth, isHeader: n.children != nil))
            if let kids = n.children { flatten(kids, depth: depth + 1, into: &out) }
        }
    }

    private func row(_ r: FlatRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(r.title)
                .fontWeight(r.isHeader ? .semibold : .regular)
                .foregroundStyle(r.isHeader ? Color.primary : Color.secondary)
            Spacer(minLength: 12)
            if let v = r.value {
                Text(v).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
        }
        .padding(.leading, CGFloat(r.depth) * 18 + 14)
        .padding(.trailing, 14)
        .padding(.vertical, 3)
        .background(r.isHeader ? Color.accentColor.opacity(0.10) : Color.clear)
    }

    var body: some View {
        Group {
            if loading {
                ProgressView(tr("Lettura da system_profiler…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                UnavailableView(title: tr("Nessun dato"), systemImage: "questionmark.folder",
                                 description: tr("system_profiler non ha restituito informazioni per") + " \(dataType).")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { r in row(r) }
                    }
                    .padding(.vertical, 8)
                }
                .modifier(AquaScroll())
            }
        }
        .task(id: dataType) {
            loading = true
            let nodes = await ProfilerLoader.load(dataType)
            var flat: [FlatRow] = []
            Self.flatten(nodes, depth: 0, into: &flat)
            rows = flat
            loading = false
        }
    }
}
