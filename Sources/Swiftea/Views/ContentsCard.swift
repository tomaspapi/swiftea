import SwiftUI

struct ContentsCard: View {
    let model: AppModel

    var body: some View {
        GroupBox {
            HStack(spacing: 16) {
                Image(systemName: model.contentsSymbolName)
                    .font(.system(size: 28, weight: .medium))
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Contents")
                        .font(.headline)

                    Text(model.contentsStatusLabel)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(model.contentsDetailLine)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }
}

#Preview {
    ContentsCard(model: AppModel.previewConnected())
        .padding()
}
