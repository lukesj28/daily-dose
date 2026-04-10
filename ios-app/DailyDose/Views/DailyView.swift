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
    @State private var wasAboveThreshold = false
    @State private var iconIsVisible = false
    @State private var isTableScrolling = false
    @State private var dragCancelledByTable = false
    @State private var showAnnotationSheet = false
    @State private var pendingAnnotation: PendingAnnotation?
    @State private var editingAnnotation: Annotation?

    @AppStorage("highlightColorR") private var highlightR: Double = 1.0
    @AppStorage("highlightColorG") private var highlightG: Double = 0.93
    @AppStorage("highlightColorB") private var highlightB: Double = 0.27

    @State private var searchQuery: String = ""
    @State private var searchMatches: [SearchMatch] = []
    @State private var currentMatchIndex: Int = 0

    private var currentArticle: Article? {
        if let id = cacheManager.currentDailyId {
            return allArticles.first(where: { $0.id == id })
        }
        return allArticles.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if cacheManager.isLoading && currentArticle == nil {
                    loadingState
                } else if cacheManager.isOffline && currentArticle == nil {
                    offlineState
                } else if let article = currentArticle {
                    articleReader(article)
                } else {
                    emptyState
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
                        try? modelContext.save()
                    } else if let pending = pendingAnnotation {
                        if let article = currentArticle {
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
        try? modelContext.save()
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
            .scrollDisabled(iconIsVisible)
            .simultaneousGesture(saveSwipeGesture(article))
            .overlay(alignment: .bottomTrailing) {
                ArticleNavigator(
                    article: article,
                    scrollProxy: proxy,
                    searchQuery: $searchQuery,
                    searchMatches: $searchMatches,
                    currentMatchIndex: $currentMatchIndex
                )
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
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(article.contentBlocks) { block in
                contentBlockView(block, article: article, matchesByBlock: matchesByBlock)
                    .id("content_\(block.index)")
            }
        }
    }

    @ViewBuilder
    private func contentBlockView(_ block: ContentBlock, article: Article, matchesByBlock: [Int: [NSRange]]) -> some View {
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
            imageBlock(block, article: article)

        case .table:
            tableBlock(block, article: article)
        }
    }

    // MARK: - Image Block

    private func imageBlock(_ block: ContentBlock, article: Article) -> some View {
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

    private func tableBlock(_ block: ContentBlock, article: Article) -> some View {
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
                    isScrolling: $isTableScrolling,
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

    // MARK: - Swipe to Save

    private func saveSwipeGesture(_ article: Article) -> some Gesture {
        DragGesture(minimumDistance: 50, coordinateSpace: .global)
            .onChanged { value in
                guard !article.isSavedToLibrary else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height

                if iconIsVisible {
                    SaveIconAnimator.shared.move(to: value.location)
                    let isAbove = horizontal > 100
                    if isAbove != wasAboveThreshold {
                        wasAboveThreshold = isAbove
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    return
                }

                guard abs(horizontal) > abs(vertical) else { return }

                if isTableScrolling {
                    dragCancelledByTable = true
                    return
                }

                if horizontal > 50 {
                    SaveIconAnimator.shared.show(at: value.location)
                    iconIsVisible = true
                }

                let isAbove = horizontal > 100
                if isAbove != wasAboveThreshold {
                    wasAboveThreshold = isAbove
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .onEnded { value in
                defer {
                    wasAboveThreshold = false
                    dragCancelledByTable = false
                    iconIsVisible = false
                }

                guard iconIsVisible, !article.isSavedToLibrary else { return }
                let horizontal = value.translation.width

                guard !dragCancelledByTable && !isTableScrolling else {
                    SaveIconAnimator.shared.hide()
                    return
                }

                if horizontal > 100 {
                    article.isSavedToLibrary = true
                    try? modelContext.save()
                    SaveIconAnimator.shared.flyToLibrary {
                        saveNotifier.didSave = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            saveNotifier.didSave = false
                        }
                    }
                } else {
                    SaveIconAnimator.shared.hide()
                }
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

    private var offlineState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Connection")
                .font(.title2)
                .fontWeight(.bold)
            Text("Check your connection or read\nsaved articles in your Library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "newspaper")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No article yet")
                .font(.title2)
                .fontWeight(.bold)
            Text("Pull down to refresh, or wait\nfor tomorrow's delivery.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
