import SwiftUI
import SwiftData
import WebKit

@main
struct DailyDoseApp: App {
    @State private var cacheManager = CacheManager()
    @State private var saveNotifier = SaveNotifier()
    @AppStorage("hasAcceptedDisclaimer") private var hasAccepted = false
    @AppStorage("displayMode") private var displayMode: Int = 0
    @State private var storeUnavailable: Bool

    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Article.self, Annotation.self)
            _storeUnavailable = State(initialValue: false)
        } catch {
            container = try! ModelContainer(for: Article.self, Annotation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            _storeUnavailable = State(initialValue: true)
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
            .alert("Library Unavailable", isPresented: $storeUnavailable) {
                Button("OK") {}
            } message: {
                Text("Your saved articles couldn't be loaded. Changes made now won't be kept after you close the app.")
            }
        }
        .modelContainer(container)
    }
}
