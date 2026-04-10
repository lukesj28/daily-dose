import SwiftUI
import SwiftData

@main
struct DailyDoseApp: App {
    @State private var cacheManager = CacheManager()
    @State private var saveNotifier = SaveNotifier()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(cacheManager)
                .environment(saveNotifier)
        }
        .modelContainer(for: [Article.self, Annotation.self])
    }
}
