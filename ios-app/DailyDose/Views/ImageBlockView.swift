import SwiftUI

struct ImageBlockView: View {
    let block: ContentBlock

    var body: some View {
        if let urlString = block.url,
           let url = URL(string: urlString),
           url.scheme == "https",
           url.host?.hasSuffix("ncbi.nlm.nih.gov") == true {
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
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.fill.tertiary)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .shimmering()
                        .accessibilityLabel("Loading image")
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}
