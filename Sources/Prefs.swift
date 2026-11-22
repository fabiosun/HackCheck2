import SwiftUI

/// Selettore a segmenti che segue lo stile attivo (Aqua oppure moderno).
struct Seg: View {
    @Binding var selection: Int
    let titles: [String]
    @AppStorage("theme") private var theme = 1

    var body: some View {
        if theme == 1 {
            AquaTabs(selection: $selection, titles: titles)
        } else {
            Picker("", selection: $selection) {
                ForEach(Array(titles.enumerated()), id: \.offset) { item in
                    Text(item.element).tag(item.offset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// Pulsanti rapidi della Panoramica: lingua (ITA / EN), stile (Aqua / Moderno) e aspetto (Light / Dark).
/// Usano le impostazioni esistenti: `theme` (0 moderno, 1 Aqua) e `appearance` (0 sistema, 1 chiaro, 2 scuro).
struct PrefsBar: View {
    @AppStorage("lang") private var lang = Lang.defaultCode
    @AppStorage("theme") private var theme = 1
    @AppStorage("appearance") private var appearance = 0

    private var langChoice: Binding<Int> {
        Binding(
            get: { lang == "en" ? 1 : 0 },
            set: { lang = $0 == 1 ? "en" : "it" }
        )
    }

    private var styleChoice: Binding<Int> {
        Binding(
            get: { theme == 1 ? 0 : 1 },
            set: { theme = $0 == 0 ? 1 : 0 }
        )
    }

    private var lightDark: Binding<Int> {
        Binding(
            get: { appearance == 2 ? 1 : 0 },
            set: { appearance = $0 == 1 ? 2 : 1 }
        )
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 10) {
                Seg(selection: langChoice, titles: ["ITA", "EN"])
                    .help(tr("Lingua dell'interfaccia"))
                Seg(selection: styleChoice, titles: ["Aqua", tr("Moderno")])
                    .help(tr("Stile grafico"))
            }
            Seg(selection: lightDark, titles: ["Light", "Dark"])
                .help(tr("Tema grafico"))
        }
    }
}
