import SwiftUI
import SwiftData
import UIKit

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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ArticleHeaderView(
                        article: article,
                        highlightColorR: highlightR,
                        highlightColorG: highlightG,
                        highlightColorB: highlightB,
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
                        highlightColorR: highlightR,
                        highlightColorG: highlightG,
                        highlightColorB: highlightB,
                        onAnnotate: handleAnnotate,
                        onEditAnnotation: handleEdit,
                        onDeleteAnnotation: handleDelete
                    )
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
                            blockIndex: pending.blockIndex,
                            blockSection: pending.blockSection,
                            startIndex: pending.range.location,
                            length: pending.range.length,
                            cellRow: pending.cellRow,
                            cellColumn: pending.cellColumn,
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

    // MARK: - Content Blocks

    private var contentBlocks: some View {
        let matchesByBlock = searchMatches.grouped()
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(article.contentBlocks) { block in
                contentBlockView(block, matchesByBlock: matchesByBlock)
                    .id("content_\(block.index)")
            }
        }
    }

    @ViewBuilder
    private func contentBlockView(_ block: ContentBlock, matchesByBlock: [Int: [NSRange]]) -> some View {
        switch block.type {
        case .heading:
            let annotations = article.annotations.filter {
                $0.blockSection == BlockSection.content && $0.blockIndex == block.index && $0.isTextAnnotation
            }
            TextBlockView(
                text: block.text ?? "",
                annotations: annotations,
                searchRanges: matchesByBlock[block.index] ?? [],
                currentSearchRange: searchMatches.currentRange(at: currentMatchIndex, forBlock: block.index),
                highlightColorR: highlightR,
                highlightColorG: highlightG,
                highlightColorB: highlightB,
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

        case .paragraph:
            let annotations = article.annotations.filter {
                $0.blockSection == BlockSection.content && $0.blockIndex == block.index && $0.isTextAnnotation
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
                    handleAnnotate(.text(section: BlockSection.content, index: block.index, range: range))
                },
                onEditAnnotation: handleEdit,
                onDeleteAnnotation: handleDelete
            )

        case .math:
            if let mathml = block.mathml {
                let equationAnnotation = article.annotations.first {
                    $0.blockSection == BlockSection.content && $0.blockIndex == block.index && $0.isEquationAnnotation
                }
                MathBlockView(
                    mathml: mathml,
                    annotation: equationAnnotation,
                    highlightColorR: highlightR,
                    highlightColorG: highlightG,
                    highlightColorB: highlightB,
                    onAnnotate: {
                        handleAnnotate(.equation(index: block.index))
                    },
                    onEditAnnotation: handleEdit,
                    onDeleteAnnotation: handleDelete
                )
            }

        case .image:
            imageBlock(block)

        case .table:
            tableBlock(block)
        }
    }

    // MARK: - Image Block

    private func imageBlock(_ block: ContentBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ImageBlockView(block: block)

            if let caption = block.caption, !caption.isEmpty {
                let captionAnnotations = article.annotations.filter {
                    $0.blockSection == BlockSection.content && $0.blockIndex == block.index && $0.isTextAnnotation
                }
                TextBlockView(
                    text: caption,
                    annotations: captionAnnotations,
                    highlightColorR: highlightR,
                    highlightColorG: highlightG,
                    highlightColorB: highlightB,
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

    private func tableBlock(_ block: ContentBlock) -> some View {
        let captionAnnotations = article.annotations.filter {
            $0.blockSection == BlockSection.content && $0.blockIndex == block.index && $0.isTextAnnotation
        }
        let cellAnnotations = article.annotations.filter {
            $0.blockSection == BlockSection.content && $0.blockIndex == block.index && $0.isCellAnnotation
        }

        return VStack(alignment: .leading, spacing: 8) {
            if let caption = block.caption, !caption.isEmpty {
                TextBlockView(
                    text: caption,
                    annotations: captionAnnotations,
                    highlightColorR: highlightR,
                    highlightColorG: highlightG,
                    highlightColorB: highlightB,
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
                    isScrolling: .constant(false),
                    annotations: cellAnnotations,
                    highlightColorR: highlightR,
                    highlightColorG: highlightG,
                    highlightColorB: highlightB,
                    onAnnotateCell: { row, col in
                        handleAnnotate(.cell(index: block.index, row: row, col: col))
                    },
                    onEditAnnotation: handleEdit,
                    onDeleteAnnotation: handleDelete
                )
                .frame(minHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Annotation Helpers

    private func handleAnnotate(_ pending: PendingAnnotation) {
        pendingAnnotation = pending
        editingAnnotation = nil
        showAnnotationSheet = true
    }

    private func handleEdit(_ annotation: Annotation) {
        editingAnnotation = annotation
        pendingAnnotation = nil
        showAnnotationSheet = true
    }

    private func handleDelete(_ annotation: Annotation) {
        modelContext.delete(annotation)
        try? modelContext.save()
    }

    private func resetAnnotationState() {
        pendingAnnotation = nil
        editingAnnotation = nil
        showAnnotationSheet = false
    }
}
