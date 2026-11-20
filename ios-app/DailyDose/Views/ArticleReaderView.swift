import SwiftUI
import SwiftData
import UIKit

struct ArticleReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CacheManager.self) private var cacheManager
    @Environment(SaveNotifier.self) private var saveNotifier: SaveNotifier?

    let article: Article
    var showsSaveButton = false

    @State private var noteDraft: NoteDraft?
    @AppStorage("lastHighlightColor") private var lastColor: HighlightColor = .yellow

    @State private var searchQuery: String = ""
    @State private var searchMatches: [SearchMatch] = []
    @State private var currentMatchIndex: Int = 0
    @State private var showNavigator = false
    @State private var sectionTracker = SectionTracker()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ArticleHeaderView(
                        article: article,
                        onAnnotate: handleAnnotate,
                        onEditAnnotation: handleEdit,
                        onDeleteAnnotation: handleDelete
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    contentBlocks
                        .padding(.horizontal, 20)

                    ArticleFooterView(
                        article: article,
                        onAnnotate: handleAnnotate,
                        onEditAnnotation: handleEdit,
                        onDeleteAnnotation: handleDelete
                    )
                    .padding(.horizontal, 20)
                }
                .coordinateSpace(.named("articleContent"))
                .padding(.top, 16)
                .padding(.bottom, 40)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .onScrollGeometryChange(for: Int?.self) { geometry in
                sectionTracker.section(atOffset: geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, index in
                sectionTracker.currentIndex = index
            }
            .toolbar {
                if showsSaveButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(article.isSavedToLibrary ? "Remove from Library" : "Save to Library",
                               systemImage: article.isSavedToLibrary ? "bookmark.fill" : "bookmark",
                               action: toggleSaved)
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Contents", systemImage: "list.bullet") { showNavigator = true }
                        .popover(isPresented: $showNavigator) {
                            ArticleNavigator(
                                article: article,
                                scrollProxy: proxy,
                                sectionTracker: sectionTracker,
                                searchQuery: $searchQuery,
                                searchMatches: searchMatches,
                                currentMatchIndex: $currentMatchIndex
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                }
            }
        }
        .task(id: searchQuery) {
            if !searchQuery.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            searchMatches = SearchMatch.compute(query: searchQuery, blocks: article.contentBlocks)
            currentMatchIndex = 0
        }
        .sheet(item: $noteDraft) { draft in
            AnnotationSheet(
                quote: AnnotationList.snippet(for: draft.anchor, in: article),
                noteText: draft.editing?.noteText ?? "",
                color: draft.editing?.highlightColor ?? lastColor,
                onSave: { text, color in
                    if let note = draft.editing ?? article.annotation(at: draft.anchor) {
                        note.noteText = text
                        note.highlightColor = color
                    } else {
                        modelContext.insert(Annotation(pending: draft.anchor, noteText: text, color: color, article: article))
                    }
                    cacheManager.save(modelContext)
                    lastColor = color
                },
                onDelete: draft.editing.map { editing in { handleDelete(editing) } }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Content Blocks

    private var contentBlocks: some View {
        let matchesByBlock = searchMatches.grouped()
        let contentAnnotations = article.annotations.filter { $0.blockSection == BlockSection.content }
        let textByIndex = Dictionary(grouping: contentAnnotations.filter(\.isTextAnnotation), by: \.blockIndex)
        let cellByIndex = Dictionary(grouping: contentAnnotations.filter(\.isCellAnnotation), by: \.blockIndex)
        let eqByIndex = Dictionary(grouping: contentAnnotations.filter(\.isEquationAnnotation), by: \.blockIndex)
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(article.contentBlocks) { block in
                contentBlockView(
                    block,
                    matchesByBlock: matchesByBlock,
                    textAnnotations: textByIndex[block.index, default: []],
                    cellAnnotations: cellByIndex[block.index, default: []],
                    equationAnnotation: eqByIndex[block.index]?.first
                )
                .id(block.scrollID)
            }
        }
    }

    @ViewBuilder
    private func contentBlockView(
        _ block: ContentBlock,
        matchesByBlock: [Int: [NSRange]],
        textAnnotations: [Annotation],
        cellAnnotations: [Annotation],
        equationAnnotation: Annotation?
    ) -> some View {
        switch block.type {
        case .heading:
            TextBlockView(
                text: block.text ?? "",
                annotations: textAnnotations,
                searchRanges: matchesByBlock[block.index] ?? [],
                currentSearchRange: searchMatches.currentRange(at: currentMatchIndex, forBlock: block.index),
                baseFont: UIFont.preferredFont(forTextStyle: .title2),
                baseFontWeight: .bold,
                enableMarkdown: false,
                onAnnotate: { range in
                    handleAnnotate(.text(section: BlockSection.content, index: block.index, range: range))
                },
                onEditAnnotation: handleEdit,
                onDeleteAnnotation: handleDelete
            )
            .padding(.top, 12)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named("articleContent")).minY
            } action: { minY in
                sectionTracker.headingTops[block.index] = minY
            }

        case .paragraph:
            TextBlockView(
                text: block.text ?? "",
                annotations: textAnnotations,
                searchRanges: matchesByBlock[block.index] ?? [],
                currentSearchRange: searchMatches.currentRange(at: currentMatchIndex, forBlock: block.index),
                onAnnotate: { range in
                    handleAnnotate(.text(section: BlockSection.content, index: block.index, range: range))
                },
                onEditAnnotation: handleEdit,
                onDeleteAnnotation: handleDelete
            )

        case .math:
            if let mathml = block.mathml {
                MathBlockView(
                    mathml: mathml,
                    annotation: equationAnnotation,
                    onAnnotate: {
                        handleAnnotate(.equation(index: block.index))
                    },
                    onEditAnnotation: handleEdit,
                    onDeleteAnnotation: handleDelete
                )
            }

        case .image:
            imageBlock(block, textAnnotations: textAnnotations)

        case .table:
            tableBlock(block, textAnnotations: textAnnotations, cellAnnotations: cellAnnotations)
        }
    }

    // MARK: - Image Block

    private func imageBlock(_ block: ContentBlock, textAnnotations: [Annotation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ImageBlockView(block: block)

            if let caption = block.caption, !caption.isEmpty {
                TextBlockView(
                    text: caption,
                    annotations: textAnnotations,
                    baseFont: UIFont.preferredFont(forTextStyle: .caption1),
                    textColor: .secondaryLabel,
                    enableMarkdown: false,
                    onAnnotate: { range in
                        handleAnnotate(.text(section: BlockSection.content, index: block.index, range: range))
                    },
                    onEditAnnotation: handleEdit,
                    onDeleteAnnotation: handleDelete
                )
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Table Block

    private func tableBlock(_ block: ContentBlock, textAnnotations: [Annotation], cellAnnotations: [Annotation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption = block.caption, !caption.isEmpty {
                TextBlockView(
                    text: caption,
                    annotations: textAnnotations,
                    baseFont: UIFont.preferredFont(forTextStyle: .caption1),
                    baseFontWeight: .semibold,
                    textColor: .secondaryLabel,
                    enableMarkdown: false,
                    onAnnotate: { range in
                        handleAnnotate(.text(section: BlockSection.content, index: block.index, range: range))
                    },
                    onEditAnnotation: handleEdit,
                    onDeleteAnnotation: handleDelete
                )
            }

            if let html = block.html {
                TableBlockView(
                    html: html,
                    annotations: cellAnnotations,
                    onAnnotateCell: { row, col in
                        handleAnnotate(.cell(index: block.index, row: row, col: col))
                    },
                    onEditAnnotation: handleEdit,
                    onDeleteAnnotation: handleDelete
                )
                .frame(minHeight: 156)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Annotation Helpers

    private func handleAnnotate(_ pending: PendingAnnotation) {
        if let existing = article.annotation(at: pending) {
            handleEdit(existing)
        } else {
            noteDraft = NoteDraft(target: .new(pending))
        }
    }

    private func handleEdit(_ annotation: Annotation) {
        noteDraft = NoteDraft(target: .edit(annotation))
    }

    private func handleDelete(_ annotation: Annotation) {
        modelContext.delete(annotation)
        cacheManager.save(modelContext)
    }

    private func toggleSaved() {
        article.isSavedToLibrary.toggle()
        cacheManager.save(modelContext)
        guard article.isSavedToLibrary, let saveNotifier else { return }
        saveNotifier.didSave = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            saveNotifier.didSave = false
        }
    }
}

private struct NoteDraft: Identifiable {
    enum Target {
        case new(PendingAnnotation)
        case edit(Annotation)
    }

    let id = UUID()
    let target: Target

    var editing: Annotation? {
        if case .edit(let annotation) = target { annotation } else { nil }
    }

    var anchor: PendingAnnotation {
        switch target {
        case .new(let pending): pending
        case .edit(let annotation): annotation.anchor
        }
    }
}

@Observable
final class SectionTracker {
    var currentIndex: Int?
    @ObservationIgnored var headingTops: [Int: CGFloat] = [:]

    private let activationOffset: CGFloat = 80

    func section(atOffset visibleTop: CGFloat) -> Int? {
        let line = visibleTop + activationOffset
        var best: (index: Int, top: CGFloat)?
        for (index, top) in headingTops where top <= line && top > (best?.top ?? -.infinity) {
            best = (index, top)
        }
        return best?.index
    }
}
