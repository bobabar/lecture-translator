import SwiftUI

struct TranscriptPane: View {
    let title: String
    let text: String
    let placeholder: String
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.headline)
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(text.isEmpty ? Color.secondary.opacity(0.4) : Color.teal)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .font(isPrimary ? .system(size: 42, weight: .bold, design: .default) : .title2.weight(.semibold))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
