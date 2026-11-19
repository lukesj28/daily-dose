import SwiftUI

struct ContentView: View {
    @Environment(SaveNotifier.self) private var saveNotifier
    @Environment(CacheManager.self) private var cacheManager

    var body: some View {
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
        .alert("Couldn't Save Changes", isPresented: Binding(
            get: { cacheManager.saveError != nil },
            set: { if !$0 { cacheManager.saveError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(cacheManager.saveError ?? "")
        }
    }
}
