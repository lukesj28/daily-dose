import SwiftUI

struct SearchMatch: Equatable {
    let blockIndex: Int
    let range: NSRange

    static func compute(query: String, blocks: [ContentBlock]) -> [SearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var matches: [SearchMatch] = []
        for block in blocks {
            guard let text = block.searchableText else { continue }
            let ns = text as NSString
            var searchRange = NSRange(location: 0, length: ns.length)
            while searchRange.location < ns.length {
                let found = ns.range(of: trimmed, options: .caseInsensitive, range: searchRange)
                if found.location == NSNotFound { break }
                matches.append(SearchMatch(blockIndex: block.index, range: found))
                let next = found.location + max(found.length, 1)
                searchRange = NSRange(location: next, length: ns.length - next)
            }
        }
        return matches
    }

    func context(in text: String, radius: Int = 40) -> AttributedString {
        let ns = text as NSString
        guard range.location + range.length <= ns.length else { return AttributedString(text) }
        let start = max(0, range.location - radius)
        let end = min(ns.length, range.location + range.length + radius)
        var result = AttributedString(start > 0 ? "…" : "")
        result += AttributedString(ns.substring(with: NSRange(location: start, length: range.location - start)))
        var hit = AttributedString(ns.substring(with: range))
        hit.foregroundColor = .primary
        hit.inlinePresentationIntent = .stronglyEmphasized
        result += hit
        let afterStart = range.location + range.length
        result += AttributedString(ns.substring(with: NSRange(location: afterStart, length: end - afterStart)))
        if end < ns.length { result += AttributedString("…") }
        return result
    }
}

extension Array where Element == SearchMatch {
    func grouped() -> [Int: [NSRange]] {
        Dictionary(grouping: self, by: \.blockIndex).mapValues { $0.map(\.range) }
    }

    func currentRange(at index: Int, forBlock blockIndex: Int) -> NSRange? {
        guard !isEmpty, indices.contains(index) else { return nil }
        let match = self[index]
        return match.blockIndex == blockIndex ? match.range : nil
    }
}

struct ArticleNavigator: View {
    let article: Article
    let scrollProxy: ScrollViewProxy
    let sectionTracker: SectionTracker
    @Binding var searchQuery: String
    let searchMatches: [SearchMatch]
    @Binding var currentMatchIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode = .sections

    enum Mode: CaseIterable, Identifiable {
        case sections, annotations
        var id: Self { self }
        var title: String {
            switch self {
            case .sections: return "Sections"
            case .annotations: return "Notes"
            }
        }
    }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                searchField
                if !isSearching {
                    Picker("Show", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding([.horizontal, .top], 14)
            .padding(.bottom, 10)

            Divider()

            Group {
                if isSearching {
                    searchResults
                } else {
                    switch mode {
                    case .sections: sectionsList
                    case .annotations: annotationsList
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(idealWidth: 440, idealHeight: 460)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search Article", text: $searchQuery)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchQuery.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") { searchQuery = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.fill.tertiary, in: .capsule)
    }

    // MARK: - Sections

    @ViewBuilder
    private var sectionsList: some View {
        let headings = article.contentBlocks.filter { $0.type == .heading }
        if headings.isEmpty {
            ContentUnavailableView("No Sections", systemImage: "list.bullet")
        } else {
            List(headings) { block in
                let isCurrent = block.index == sectionTracker.currentIndex
                Button {
                    jumpTo(scrollID: block.scrollID)
                } label: {
                    HStack {
                        Text(block.text ?? "")
                            .fontWeight(isCurrent ? .semibold : .regular)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if isCurrent {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .listRowBackground(Color.clear)
            }
            .navigatorListStyle()
        }
    }

    // MARK: - Annotations

    @ViewBuilder
    private var annotationsList: some View {
        let annotations = AnnotationList.sorted(article.annotations)
        if annotations.isEmpty {
            ContentUnavailableView("No Notes", systemImage: "note.text",
                                   description: Text("Select text in the article and choose Annotate."))
        } else {
            List(annotations) { annotation in
                Button {
                    jumpTo(scrollID: annotation.scrollID)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let snippet = AnnotationList.snippet(for: annotation, in: article) {
                            Text(snippet)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        Text(annotation.noteText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .multilineTextAlignment(.leading)
                }
                .listRowBackground(Color.clear)
            }
            .navigatorListStyle()
        }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchResults: some View {
        if searchMatches.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
        } else {
            let blocks = article.contentBlocks
            List(Array(searchMatches.enumerated()), id: \.offset) { offset, match in
                Button {
                    currentMatchIndex = offset
                    jumpTo(scrollID: ContentBlock.scrollID(forIndex: match.blockIndex), anchor: UnitPoint(x: 0.5, y: 0.2))
                } label: {
                    Text(match.context(in: blocks.indices.contains(match.blockIndex) ? blocks[match.blockIndex].searchableText ?? "" : ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .listRowBackground(Color.clear)
            }
            .navigatorListStyle()
        }
    }

    // MARK: - Helpers

    private func jumpTo(scrollID: String, anchor: UnitPoint = .top) {
        dismiss()
        withAnimation(reduceMotion ? nil : .default) {
            scrollProxy.scrollTo(scrollID, anchor: anchor)
        }
    }
}

private extension View {
    func navigatorListStyle() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}

enum AnnotationList {
    private static let sectionOrder = [BlockSection.header: 0, BlockSection.content: 1, BlockSection.footer: 2]

    static func sorted(_ annotations: [Annotation]) -> [Annotation] {
        annotations.sorted { a, b in
            let aOrder = sectionOrder[a.blockSection] ?? 1
            let bOrder = sectionOrder[b.blockSection] ?? 1
            if aOrder != bOrder { return aOrder < bOrder }
            if a.blockIndex != b.blockIndex { return a.blockIndex < b.blockIndex }
            return a.startIndex < b.startIndex
        }
    }

    static func snippet(for annotation: Annotation, in article: Article) -> String? {
        if annotation.isCellAnnotation {
            return "Table cell (\(annotation.cellRow + 1), \(annotation.cellColumn + 1))"
        }

        if annotation.isEquationAnnotation {
            return "Equation"
        }

        let sourceText: String?

        switch annotation.blockSection {
        case BlockSection.header:
            switch annotation.blockIndex {
            case 1: sourceText = article.title
            case 2: sourceText = article.authors.joined(separator: ", ")
            case 3: sourceText = article.formattedPublishDate
            default: sourceText = nil
            }

        case BlockSection.footer:
            switch annotation.blockIndex {
            case 0: sourceText = article.authors.joined(separator: ", ")
            case 1: sourceText = "\(article.journal) · \(article.formattedPublishDate)"
            case 2: sourceText = article.license
            default: sourceText = nil
            }

        default: // BlockSection.content
            if let block = article.contentBlocks.first(where: { $0.index == annotation.blockIndex }) {
                sourceText = block.searchableText ?? block.caption ?? block.text
            } else {
                sourceText = nil
            }
        }

        guard let text = sourceText else { return nil }
        let ns = text as NSString
        let range = annotation.range
        guard range.location >= 0,
              range.location + range.length <= ns.length,
              range.length > 0 else { return nil }
        var snippet = ns.substring(with: range)
        if snippet.count > 80 { snippet = String(snippet.prefix(80)) + "…" }
        return "\u{201C}" + snippet + "\u{201D}"
    }
}
