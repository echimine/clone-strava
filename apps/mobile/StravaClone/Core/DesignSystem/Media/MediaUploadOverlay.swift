import SwiftUI

/// French texts of the Media being sent and of the "Photos et vidéos" section (ADR-037 §5, §10).
enum MediaUploadMessages {
    static let sectionTitle = "Photos et vidéos"
    static let add = "Ajouter photos/vidéo"
    static let limitReached = "Limite de 8 atteinte"
    static let map = "Carte"
    static let failed = "Échec"
    static let retry = "Réessayer"
    static let remove = "Retirer"
    static let sending = "Envoi en cours"
    static let preparing = "Préparation"
    static let addMedia = "Ajouter des photos ou vidéos"
    static let mediaTitle = "Média"
    static let putFirst = "Mettre en premier"
    static let putMapFirst = "Remettre la carte en premier"
    static let delete = "Supprimer"
    static let reorder = "Modifier l'ordre"
    static let orderTitle = "Ordre des médias"
    static let done = "OK"
    static let photo = "Photo"
    static let video = "Vidéo"
    static let tapHint = "Touchez un média pour le mettre en premier ou le supprimer."

    /// "5/8".
    static func counter(_ count: Int, limit: Int) -> String { "\(count)/\(limit)" }

    static func failure(_ reason: MediaUploadFailure) -> String {
        switch reason {
        case .network: "Échec de l'envoi : réseau indisponible"
        case .limitReached: "Échec : cette activité a déjà 8 médias"
        case .invalid: "Échec : fichier refusé"
        case .exportFailed: "Échec : média illisible"
        case .unavailableOffline: unavailableOffline
        }
    }
}

/// Over a Media not confirmed yet (ADR-037 §5): a spinner while it is exported, a progress ring
/// while it is sent, "Échec" with "Réessayer" and "Retirer" once failed. `compact` on the edit
/// strip's tiles: the failed state only shows its mark, the tile's tap opens the actions.
struct MediaUploadOverlay: View {
    let mediaID: UUID
    let status: MediaUploadStatus
    var compact = false

    @Environment(\.mediaUploads) private var uploads

    var body: some View {
        switch status {
        case .exporting:
            ZStack {
                Color.black.opacity(0.25)
                ProgressView().tint(.white)
            }
            .accessibilityElement()
            .accessibilityLabel(MediaUploadMessages.preparing)
            .allowsHitTesting(false)
        case .sending(let progress):
            ZStack {
                Color.black.opacity(0.25)
                ring(progress)
            }
            .accessibilityElement()
            .accessibilityLabel(MediaUploadMessages.sending)
            .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
            .accessibilityIdentifier("mediaUpload.progress")
            .allowsHitTesting(false)
        case .failed(let reason, let canRetry):
            ZStack {
                Color.black.opacity(0.55)
                if compact {
                    Label(MediaUploadMessages.failed, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                } else {
                    VStack(spacing: 10) {
                        Label(MediaUploadMessages.failure(reason), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        HStack(spacing: 10) {
                            if canRetry {
                                Button(MediaUploadMessages.retry) { uploads?.retry(mediaID) }
                                    .accessibilityIdentifier("mediaUpload.retry")
                            }
                            Button(MediaUploadMessages.remove, role: .destructive) { uploads?.remove(mediaID) }
                                .accessibilityIdentifier("mediaUpload.remove")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(12)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mediaUpload.failed")
        }
    }

    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(width: compact ? 26 : 40, height: compact ? 26 : 40)
    }
}
