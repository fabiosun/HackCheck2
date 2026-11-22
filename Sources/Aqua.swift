import SwiftUI

// MARK: - Sfondo "pinstripe" classico di Mac OS X

struct Pinstripe: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let base = scheme == .dark ? Color(white: 0.16) : Color(white: 0.955)
        let stripe = scheme == .dark ? Color(white: 0.20) : Color(white: 0.925)
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 2)), with: .color(stripe))
                y += 4
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Gel: riempimento lucido tipo Aqua

struct GelFill: View {
    let color: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            LinearGradient(colors: [color.opacity(0.70), color, color.opacity(0.92)], startPoint: .top, endPoint: .bottom)
            Capsule()
                .fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.30 : 0.85), .white.opacity(0.03)], startPoint: .top, endPoint: .center))
                .padding(2)
        }
    }
}

/// Sfera di gel con simbolo (stile iTunes / Dock)
struct GelOrb: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .top, endPoint: .bottom))
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                .offset(y: size * 0.07)
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.72, height: size * 0.44)
                .offset(y: -size * 0.24)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.8))
        .shadow(color: color.opacity(0.45), radius: 3, y: 2)
    }
}

// MARK: - Pulsanti Aqua

struct AquaButtonStyle: ButtonStyle {
    @Environment(\.pageTint) private var tint
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 0.5, y: 0.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(GelFill(color: tint).clipShape(Capsule()))
            .overlay(Capsule().strokeBorder(.black.opacity(0.4), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .brightness(configuration.isPressed ? -0.15 : 0)
            .saturation(enabled ? 1 : 0)
            .opacity(enabled ? 1 : 0.55)
    }
}

/// Schede a pillola (sostituisce il selettore segmentato)
struct AquaTabs: View {
    @Binding var selection: Int
    let titles: [String]
    @Environment(\.pageTint) private var tint
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Ogni scheda è una pillola autonoma: nessun contenitore comune.
        HStack(spacing: 6) {
            ForEach(Array(titles.enumerated()), id: \.offset) { item in
                let on = selection == item.offset
                Button {
                    selection = item.offset
                } label: {
                    Text(item.element)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .shadow(color: on ? .black.opacity(0.4) : .clear, radius: 0.5, y: 0.5)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                        .background(
                            GelFill(color: on ? tint : Color(white: scheme == .dark ? 0.26 : 0.85))
                                .clipShape(Capsule())
                        )
                        .overlay(Capsule().strokeBorder(.black.opacity(0.4), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .opacity(on ? 1 : 0.88)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Modificatori di tema

struct ThemeRoot: ViewModifier {
    @AppStorage("theme") private var theme = 1
    func body(content: Content) -> some View {
        if theme == 1 {
            content
                .font(.custom("Lucida Grande", size: 13))
                .buttonStyle(AquaButtonStyle())
        } else {
            content
        }
    }
}

struct AquaSidebarBG: ViewModifier {
    @AppStorage("theme") private var theme = 1
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if theme == 1 {
            content
                .scrollContentBackground(.hidden)
                .background(LinearGradient(
                    colors: scheme == .dark
                        ? [Color(white: 0.18), Color(white: 0.13)]
                        : [Color(red: 0.87, green: 0.90, blue: 0.94), Color(red: 0.78, green: 0.82, blue: 0.89)],
                    startPoint: .top, endPoint: .bottom))
        } else {
            content
        }
    }
}

struct DetailBackground: ViewModifier {
    let color: Color
    @AppStorage("theme") private var theme = 1
    func body(content: Content) -> some View {
        if theme == 1 {
            content.background(Pinstripe())
        } else {
            content.background(
                LinearGradient(colors: [color.opacity(0.14), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4))
                    .ignoresSafeArea())
        }
    }
}

struct AquaScroll: ViewModifier {
    @AppStorage("theme") private var theme = 1
    func body(content: Content) -> some View {
        if theme == 1 { content.scrollContentBackground(.hidden) } else { content }
    }
}
