import SwiftUI
import SwiftData

struct ArticleReaderView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("highlightColorR") private var highlightR: Double = 1.0
    @AppStorage("highlightColorG") private var highlightG: Double = 0.93
    @AppStorage("highlightColorB") private var highlightB: Double = 0.27

    let article: Article

    @State private var showAnnotationSheet = false
    @State private var pendingAnnotation: PendingAnnotation?
    @State private var editingAnnotation: Annotation?

    @State private var searchQuery: String = ""
    @State private var searchMatches: [SearchMatch] = []
    @State private var currentMatchIndex: Int = 0

    struct PendingAnnotation {
        let paragraphIndex: Int
        let range: NSRange
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    articleHeader
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    contentBlocks
                        .padding(.horizontal, 20)

                    ArticleFooterView(article: article)
                        .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
            }
            .overlay(alignment: .bottomTrailing) {
                ArticleNavigator(
                    article: article,
                    scrollProxy: proxy,
                    searchQuery: $searchQuery,
                    searchMatches: $searchMatches,
                    currentMatchIndex: $currentMatchIndex
                )
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            searchMatches = SearchMatch.compute(query: newValue, blocks: article.contentBlocks)
            currentMatchIndex = 0
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAnnotationSheet) {
            AnnotationSheet(
                noteText: editingAnnotation?.noteText ?? "",
                onSave: { text in
                    if let editing = editingAnnotation {
                        editing.noteText = text
                        try? modelContext.save()
                    } else if let pending = pendingAnnotation {
                        let annotation = Annotation(
                            paragraphIndex: pending.paragraphIndex,
                            startIndex: pending.range.location,
                            length: pending.range.length,
                            noteText: text,
                            article: article
                        )
                        modelContext.insert(annotation)
                        try? modelContext.save()
                    }
                    resetAnnotationState()
                },
                onDelete: editingAnnotation.map { editing in {
                    modelContext.delete(editing)
                    try? modelContext.save()
                    resetAnnotationState()
                }}
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Header

    private var articleHeader: some View {
        ArticleHeaderView(article: article)
    }

    // MARK: - Content Blocks

    private var contentBlocks: some View {
        let matchesByBlock = searchMatches.grouped()
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(article.contentBlocks) { block in
                contentBlockView(block, matchesByBlock: matchesByBlock)
                    .id(block.index)
            }
        }
    }

    @ViewBuilder
    private func contentBlockView(_ block: ContentBlock, matchesByBlock: [Int: [NSRange]]) -> some View {
        switch block.type {
        case .heading:
            Text(block.text ?? "")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 12)

        case .paragraph:
            let annotations = article.annotations.filter {
                $0.paragraphIndex == block.index
            }
            TextBlockView(
                text: block.text ?? "",
                annotations: annotations,
                searchRanges: matchesByBlock[block.index] ?? [],
                currentSearchRange: searchMatches.currentRange(at: currentMatchIndex, forBlock: block.index),
                highlightColorR: highlightR,
                highlightColorG: highlightG,
                highlightColorB: highlightB,
                onAnnotate: { range in
                    pendingAnnotation = PendingAnnotation(
                        paragraphIndex: block.index,
                        range: range
                    )
                    editingAnnotation = nil
                    showAnnotationSheet = true
                },
                onEditAnnotation: { annotation in
                    editingAnnotation = annotation
                    pendingAnnotation = nil
                    showAnnotationSheet = true
                },
                onDeleteAnnotation: { annotation in
                    modelContext.delete(annotation)
                    try? modelContext.save()
                }
            )

        case .math:
            if let mathml = block.mathml {
                MathBlockView(mathml: mathml)
            }

        case .image:
            ImageBlockView(block: block)

        case .table:
            tableBlock(block)
        }
    }

    // MARK: - Table Block

    private func tableBlock(_ block: ContentBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption = block.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            if let html = block.html {
                TableBlockView(html: html, isScrolling: .constant(false))
                    .frame(minHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 8)
    }

    private func resetAnnotationState() {
        pendingAnnotation = nil
        editingAnnotation = nil
        showAnnotationSheet = false
    }
}
