import SwiftUI

/// Slight shrink while pressed, so taps feel physical.
struct OnboardingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A full-width choice, inverted (black background) once picked: gender, goals and level.
/// `revealsDetail`: the detail only shows once picked (goals); otherwise always (level).
struct OnboardingChoiceRow: View {
    let title: String
    var detail: String?
    var revealsDetail = false
    let isSelected: Bool
    let action: () -> Void

    private var showsDetail: Bool { detail != nil && (!revealsDetail || isSelected) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                if showsDetail, let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color(.systemBackground).opacity(0.8) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.primary : Color(.secondarySystemBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(OnboardingPressStyle())
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A sport in the 2-column grid, with its check mark.
struct OnboardingSportTile: View {
    let sport: SportType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: ActivityFormatters.sportSymbol(sport))
                        .accessibilityHidden(true)
                        .font(.title2)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .accessibilityHidden(true)
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color(.systemBackground) : Color(.systemGray3))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(ActivityFormatters.sportLabel(sport))
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.primary : Color(.secondarySystemBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(OnboardingPressStyle())
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ActivityFormatters.sportLabel(sport))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Label above, 54 pt field, darker border while focused.
struct OnboardingTextField: View {
    let label: String
    @Binding var text: String
    let isFocused: Bool
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            TextField("", text: $text)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isFocused ? Color.primary : Color(.systemGray4), lineWidth: isFocused ? 1.5 : 1)
                )
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// The small grey line saying who sees the data.
struct OnboardingNote: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).imageScale(.small)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
