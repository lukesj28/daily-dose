import SwiftUI
import SwiftData
import UIKit

struct DailyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CacheManager.self) private var cacheManager
    @Environment(SaveNotifier.self) private var saveNotifier
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Article.fetchDate, order: .reverse)
    private var allArticles: [Article]

    @State private var hasAppeared = false
    @State private var showAnnotationSheet = false
    @State private var pendingAnnotation: PendingAnnotation?
    @State private var editingAnnotation: Annotation?

    @AppStorage("highlightColorR") private var highlightR: Double = 1.0
    @AppStorage("highlightColorG") private var highlightG: Double = 0.93
    @AppStorage("highlightColorB") private var highlightB: Double = 0.27

    @State private var searchQuery: String = ""
    @State private var searchMatches: [SearchMatch] = []
    @State private var currentMatchIndex: Int = 0
    @State private var isFABRelocating = false

    private var currentArticle: Article? {
        cacheManager.currentArticle(in: allArticles)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if cacheManager.isLoading && currentArticle == nil {
                    loadingState
                } else if let article = currentArticle, !article.isDeleted {
                    articleReader(article)
                } else if cacheManager.isOffline {
                    messageState(systemImage: "wifi.slash", title: "No Connection",
                                 message: "Read your saved articles in the Library,\nor try again.")
                } else {
                    messageState(systemImage: "newspaper", title: "No article yet",
                                 message: "Try again, or wait\nfor tomorrow's delivery.")
                }
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            Task { await cacheManager.checkAndUpdateCache(context: modelContext) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await cacheManager.checkAndUpdateCache(context: modelContext) }
            }
        }
        .sheet(isPresented: $showAnnotationSheet) {
            AnnotationSheet(
                noteText: editingAnnotation?.noteText ?? "",
                onSave: { text in
                    if let editing = editingAnnotation {
                        editing.noteText = text
                        cacheManager.save(modelContext)
                    } else if let pending = pendingAnnotation {
                        if let article = currentArticle {
                            let annotation = Annotation(pending: pending, noteText: text, article: article)
                            modelContext.insert(annotation)
                            cacheManager.save(modelContext)
                        }
                    }
                    resetAnnotationState()
                },
                onDelete: editingAnnotation.map { editing in {
                    modelContext.delete(editing)
                    cacheManager.save(modelContext)
                    resetAnnotationState()
                }}
            )
            .presentationDetents([.medium])
        }
    }

    private func resetAnnotationState() {
        pendingAnnotation = nil
        editingAnnotation = nil
        showAnnotationSheet = false
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
        cacheManager.save(modelContext)
    }

    // MARK: - Article Reader

    private func articleReader(_ article: Article) -> some View {
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

                    contentBlocks(article)
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
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollDisabled(isFABRelocating)
            .overlay {
                ArticleNavigator(
                    article: article,
                    scrollProxy: proxy,
                    searchQuery: $searchQuery,
                    searchMatches: $searchMatches,
                    currentMatchIndex: $currentMatchIndex,
                    isRelocating: $isFABRelocating
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(article.isSavedToLibrary ? "Saved" : "Save to Library",
                           systemImage: article.isSavedToLibrary ? "bookmark.fill" : "bookmark") {
                        saveToLibrary(article)
                    }
                    .disabled(article.isSavedToLibrary)
                }
            }
            .onChange(of: searchQuery) { _, newValue in
                searchMatches = SearchMatch.compute(query: newValue, blocks: article.contentBlocks)
                currentMatchIndex = 0
            }
            .onChange(of: article.id) { _, _ in
                searchQuery = ""
                searchMatches = []
                currentMatchIndex = 0
            }
        }
        .refreshable {
            await cacheManager.checkAndUpdateCache(context: modelContext, force: true)
        }
    }

    // MARK: - Content Blocks

    private func contentBlocks(_ article: Article) -> some View {
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
                .id("content_\(block.index)")
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
            TextBlockView(
                text: block.text ?? "",
                annotations: textAnnotations,
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

    private func tableBlock(_ block: ContentBlock, textAnnotations: [Annotation], cellAnnotations: [Annotation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption = block.caption, !caption.isEmpty {
                TextBlockView(
                    text: caption,
                    annotations: textAnnotations,
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
                .frame(minHeight: 156)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 8)
    }

    private func saveToLibrary(_ article: Article) {
        article.isSavedToLibrary = true
        cacheManager.save(modelContext)
        saveNotifier.didSave = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            saveNotifier.didSave = false
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Fetching today's science...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func messageState(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task { await cacheManager.checkAndUpdateCache(context: modelContext, force: true) }
                }
                .buttonStyle(.bordered)
                .disabled(cacheManager.isLoading)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .containerRelativeFrame(.vertical)
        }
        .refreshable {
            await cacheManager.checkAndUpdateCache(context: modelContext, force: true)
        }
    }
}
