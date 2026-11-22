import SwiftUI

enum UpdateNotice {
    static let currentNotes: [String] = [
        "Aggiunto controllo aggiornamenti da GitHub, con note in italiano e inglese",
        "Nuovo comando «Controlla aggiornamenti…» e opzioni dedicate nelle Impostazioni"
    ]
}

struct UpdateNoticeView: View {
    let version: String
    let notes: [String]
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Novità in HackCheck"))
                        .font(.title3.weight(.semibold))
                    if !version.isEmpty {
                        Text(tr("Versione") + " " + version)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(tr("HackCheck è stato aggiornato. Ecco cosa è cambiato:"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(.top, 1)
                        Text(tr(note))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Spacer()
                Button(tr("Continua")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
