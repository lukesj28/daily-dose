import SwiftUI

struct ContentView: View {
    @Environment(SaveNotifier.self) private var saveNotifier
    @State private var noteIconX: CGFloat = 0
    @State private var noteIconY: CGFloat = 0
    @State private var noteIconScale: CGFloat = 1.0
    @State private var noteIconOpacity: Double = 0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TabView {
                    Tab("Daily", systemImage: "book") {
                        DailyView()
                    }

                    Tab {
                        LibraryView()
                    } label: {
                        Label("Library", systemImage: "books.vertical.fill")
                            .symbolEffect(.bounce, value: saveNotifier.didSave)
                    }
                }
                .tint(.primary)

                ZStack {
                    Image(systemName: "text.page.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                    Image(systemName: "text.page")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.primary)
                }
                .frame(width: 56, height: 72)
                .scaleEffect(noteIconScale)
                .position(x: noteIconX, y: noteIconY)
                .opacity(noteIconOpacity)
                .allowsHitTesting(false)
            }
            .onChange(of: saveNotifier.dragLocation) { _, location in
                guard !isAnimating else { return }
                if let location {
                    noteIconX = location.x
                    noteIconY = location.y - 60
                    noteIconOpacity = 1
                } else {
                    noteIconOpacity = 0
                }
            }
            .onChange(of: saveNotifier.animationStart) { _, point in
                guard let point else { return }
                saveNotifier.animationStart = nil
                flyToLibrary(from: point, geo: geo)
            }
        }
        .ignoresSafeArea()
    }

    private func flyToLibrary(from point: CGPoint, geo: GeometryProxy) {
        // Library tab (2nd of 2) centers at 75% width.
        // Tab bar icon sits roughly 25pt above the bottom of the screen.
        let targetX = geo.size.width * 0.75
        let targetY = geo.size.height - geo.safeAreaInsets.bottom - 25

        isAnimating = true
        noteIconX = point.x
        noteIconY = point.y - 60
        noteIconOpacity = 1
        noteIconScale = 1.0

        withAnimation(.easeIn(duration: 0.45), completionCriteria: .logicallyComplete) {
            noteIconX = targetX
            noteIconY = targetY
            noteIconScale = 0.0
        } completion: {
            noteIconOpacity = 0
            noteIconScale = 1.0
            isAnimating = false
            saveNotifier.didSave = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                saveNotifier.didSave = false
            }
        }
    }
}
