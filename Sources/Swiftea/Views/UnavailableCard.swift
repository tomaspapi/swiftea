import SwiftUI

struct UnavailableCard: View {
    let title: String
    let message: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    UnavailableCard(
        title: "Current temperature",
        message: nil
    )
    .padding()
}
