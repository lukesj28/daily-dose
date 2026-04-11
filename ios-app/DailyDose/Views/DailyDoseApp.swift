import SwiftUI
import SwiftData
import WebKit

@main
struct DailyDoseApp: App {
    @State private var cacheManager = CacheManager()
    @State private var saveNotifier = SaveNotifier()
    @AppStorage("hasAcceptedDisclaimer") private var hasAccepted = false
    @AppStorage("displayMode") private var displayMode: Int = 0

    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Article.self, Annotation.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        DispatchQueue.main.async {
            _ = WKWebView(frame: .zero)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasAccepted {
                    ContentView()
                        .environment(cacheManager)
                        .environment(saveNotifier)
                } else {
                    DisclaimerView()
                }
            }
            .preferredColorScheme(DisplayMode(rawValue: displayMode)?.colorScheme)
        }
        .modelContainer(container)
    }
}
