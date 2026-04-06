import SwiftUI

struct ImageBlockView: View {
    let block: ContentBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let urlString = block.url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        HStack {
                            Image(systemName: "photo.badge.exclamationmark")
                            Text("Image unavailable")
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 100)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            if let caption = block.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 8)
    }
}
