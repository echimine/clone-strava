import SwiftUI

/// Import progress and result, shown at the top of the feed.
struct ImportStatusBanner: View {
    let banner: ImportStore.Banner
    let onPickSport: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                if case .failed(_, true) = banner {
                    Button("Choisir le sport", action: onPickSport)
                        .font(.footnote.weight(.semibold))
                        .padding(.top, 2)
                        .accessibilityIdentifier("import.pickSport")
                }
            }
            Spacer(minLength: 0)
            if isFinished {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
            }
        }
        .padding(14)
        .modifier(BannerBackground())
        .padding(.horizontal, Theme.spacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.banner")
    }

    private var isFinished: Bool {
        switch banner {
        case .uploading, .processing: false
        default: true
        }
    }

    @ViewBuilder private var icon: some View {
        switch banner {
        case .uploading, .processing:
            ProgressView()
        case .imported:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .duplicate:
            Image(systemName: "doc.on.doc.fill").foregroundStyle(.secondary)
        case .stillProcessing:
            Image(systemName: "clock.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch banner {
        case .uploading: "Envoi du fichier…"
        case .processing: "Traitement de l'activité…"
        case .imported: "Activité importée"
        case .duplicate: "Activité déjà importée"
        case .stillProcessing: "Traitement en cours"
        case .failed: "Échec de l'import"
        }
    }

    private var detail: String? {
        switch banner {
        case .uploading(let name), .processing(let name), .imported(let name), .duplicate(let name): name
        case .stillProcessing: "Elle apparaîtra dans votre fil dans quelques instants."
        case .failed(let message, _): message
        }
    }
}

/// Liquid Glass on iOS 26, material before.
private struct BannerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: 20))
        }
    }
}
