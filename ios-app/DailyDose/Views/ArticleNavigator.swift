import SwiftUI

struct SearchMatch: Equatable {
    let blockIndex: Int
    let range: NSRange

    static func compute(query: String, blocks: [ContentBlock]) -> [SearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var matches: [SearchMatch] = []
        for block in blocks where block.type == .paragraph || block.type == .heading {
            guard let text = block.text else { continue }
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
    @Binding var searchQuery: String
    @Binding var searchMatches: [SearchMatch]
    @Binding var currentMatchIndex: Int

    @State private var isExpanded = false
    @State private var mode: Mode = .sections
    @FocusState private var searchFocused: Bool

    enum Mode: String, CaseIterable, Identifiable {
        case sections, annotations, search
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sections: return "Sections"
            case .annotations: return "Notes"
            case .search: return "Search"
            }
        }
        var icon: String {
            switch self {
            case .sections: return "list.bullet.indent"
            case .annotations: return "note.text"
            case .search: return "magnifyingglass"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                Color.black.opacity(0.0001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { collapse() }
            }

            VStack(alignment: .trailing, spacing: 12) {
                if isExpanded {
                    panel
                        .frame(width: 320)
                        .frame(maxHeight: 440)
                        .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
                }
                fab
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isExpanded)
    }

    // MARK: - FAB

    private var fab: some View {
        Button {
            if isExpanded {
                collapse()
            } else {
                withAnimation { isExpanded = true }
            }
        } label: {
            Image(systemName: isExpanded ? "xmark" : "list.bullet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Panel

    private var panel: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                picker
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider().opacity(0.3)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var picker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(Mode.allCases) { m in
                Label(m.title, systemImage: m.icon).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .sections: sectionsList
        case .annotations: annotationsList
        case .search: searchPane
        }
    }

    // MARK: - Sections

    private var sectionsList: some View {
        let headings = article.contentBlocks.filter { $0.type == .heading }
        return Group {
            if headings.isEmpty {
                emptyState("No sections")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(headings) { block in
                            Button {
                                jumpTo(scrollID: "content_\(block.index)")
                            } label: {
                                HStack {
                                    Text(block.text ?? "")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            Divider().opacity(0.2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Annotations

    private static let annotationSectionOrder = [BlockSection.header: 0, BlockSection.content: 1, BlockSection.footer: 2]

    private var annotationsList: some View {
        let annotations = article.annotations.sorted { a, b in
            let aOrder = Self.annotationSectionOrder[a.blockSection] ?? 1
            let bOrder = Self.annotationSectionOrder[b.blockSection] ?? 1
            if aOrder != bOrder { return aOrder < bOrder }
            if a.blockIndex != b.blockIndex { return a.blockIndex < b.blockIndex }
            return a.startIndex < b.startIndex
        }
        let blocks = article.contentBlocks
        return Group {
            if annotations.isEmpty {
                emptyState("No annotations yet")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(annotations) { annotation in
                            Button {
                                jumpTo(scrollID: annotation.scrollID)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let snippet = snippet(for: annotation, in: blocks) {
                                        Text(snippet)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Text(annotation.noteText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            Divider().opacity(0.2)
                        }
                    }
                }
            }
        }
    }

    private func snippet(for annotation: Annotation, in blocks: [ContentBlock]) -> String? {
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
            case 0: sourceText = article.journal
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
            if let block = blocks.first(where: { $0.index == annotation.blockIndex }) {
                sourceText = block.caption ?? block.text
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

    // MARK: - Search

    private var searchPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search article", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.5))
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if !searchQuery.isEmpty {
                HStack {
                    Text(searchMatches.isEmpty
                         ? "No matches"
                         : "\(currentMatchIndex + 1) / \(searchMatches.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        stepMatch(-1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(searchMatches.isEmpty)
                    Button {
                        stepMatch(1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(searchMatches.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
        .onAppear { searchFocused = true }
    }

    private func stepMatch(_ delta: Int) {
        guard !searchMatches.isEmpty else { return }
        let count = searchMatches.count
        currentMatchIndex = (currentMatchIndex + delta + count) % count
        let match = searchMatches[currentMatchIndex]
        withAnimation {
            scrollProxy.scrollTo("content_\(match.blockIndex)", anchor: .center)
        }
    }

    // MARK: - Helpers

    private func jumpTo(scrollID: String) {
        withAnimation {
            scrollProxy.scrollTo(scrollID, anchor: .top)
        }
        collapse()
    }

    private func collapse() {
        withAnimation { isExpanded = false }
        searchFocused = false
    }

    private func emptyState(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
