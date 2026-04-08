import SwiftUI
import SwiftData

struct DailyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CacheManager.self) private var cacheManager
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Article.fetchDate, order: .reverse)
    private var allArticles: [Article]

    @State private var noteIconOffset: CGFloat = 0
    @State private var noteIconOpacity: Double = 0
    @State private var noteIconY: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
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

    private var currentArticle: Article? {
        allArticles.first
    }

    var body: some View {
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

            Image(systemName: "note.text")
                .font(.title2)
                .foregroundStyle(.yellow)
                .offset(x: noteIconOffset, y: noteIconY)
                .opacity(noteIconOpacity)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                Task {
                    await cacheManager.checkAndUpdateCache(context: modelContext)
                }
            }
        }
        .task {
            await cacheManager.checkAndUpdateCache(context: modelContext)
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
                                paragraphIndex: pending.paragraphIndex,
                                startIndex: pending.range.location,
                                length: pending.range.length,
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

    // MARK: - Article Reader

    private func articleReader(_ article: Article) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    articleHeader(article)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    contentBlocks(article)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .offset(x: dragOffset)
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

    private func articleHeader(_ article: Article) -> some View {
        ArticleHeaderView(article: article)
    }

    // MARK: - Content Blocks

    private func contentBlocks(_ article: Article) -> some View {
        let matchesByBlock = searchMatches.grouped()
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(article.contentBlocks) { block in
                contentBlockView(block, article: article, matchesByBlock: matchesByBlock)
                    .id(block.index)
            }
        }
    }

    @ViewBuilder
    private func contentBlockView(_ block: ContentBlock, article: Article, matchesByBlock: [Int: [NSRange]]) -> some View {
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
                TableBlockView(html: html)
                    .frame(minHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Swipe to Save

    private func saveSwipeGesture(_ article: Article) -> some Gesture {
        DragGesture(minimumDistance: 50)
            .onChanged { value in
                guard !article.isSavedToLibrary else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                // Axis guard: vertical drags belong to the scroll view's pull-to-refresh.
                guard abs(horizontal) > abs(vertical) else { return }
                if horizontal > 0 {
                    dragOffset = horizontal * 0.3
                }
            }
            .onEnded { value in
                guard !article.isSavedToLibrary else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let isHorizontalDominant = abs(horizontal) > abs(vertical)

                if isHorizontalDominant && horizontal > 100 {
                    article.isSavedToLibrary = true
                    try? modelContext.save()
                    triggerNoteAnimation(from: value.location)
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragOffset = 0
                }
            }
    }

    private func triggerNoteAnimation(from point: CGPoint) {
        noteIconY = point.y - UIScreen.main.bounds.height / 2
        noteIconOffset = point.x - UIScreen.main.bounds.width / 2
        noteIconOpacity = 1

        withAnimation(.easeIn(duration: 0.5)) {
            noteIconOffset = UIScreen.main.bounds.width / 2 + 40
            noteIconOpacity = 0
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
