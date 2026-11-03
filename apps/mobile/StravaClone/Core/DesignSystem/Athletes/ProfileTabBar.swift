import SwiftUI

/// The tabs under a profile's header (ADR-036 §3), as Strava draws them: an icon over each
/// label, the chosen one in the primary colour and underlined in `Theme.accent`, a hairline
/// under the bar. Pinned over the tab's content while it scrolls.
struct ProfileTabBar<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    let systemImage: (Tab) -> String

    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                button(tab)
            }
        }
        .padding(.horizontal, Theme.spacing)
        .background(alignment: .bottom) { Divider() }
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
    }

    private func button(_ tab: Tab) -> some View {
        let isSelected = tab == selection
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selection = tab }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage(tab))
                    .font(.title2)
                    .frame(height: 28)
                Text(title(tab))
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: 3)
                        .matchedGeometryEffect(id: "underline", in: underline)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title(tab)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var selection = "Plus"
    ProfileTabBar(
        tabs: ["Progrès", "Activités", "Plus"],
        selection: $selection,
        title: { $0 },
        systemImage: { ["Progrès": "chart.bar.doc.horizontal", "Activités": "waveform.path.ecg"][$0] ?? "line.3.horizontal" }
    )
}
