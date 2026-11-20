import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showMailUnavailable = false

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    NavigationLink("About Daily Dose") {
                        AboutView()
                    }
                    Link("Privacy Policy", destination: URL(string: ArticleService.baseURL + "/privacy.html")!)
                    Button("Contact Support") {
                        openURL(URL(string: "mailto:help@sanjuan.dev")!) { accepted in
                            guard !accepted else { return }
                            UIPasteboard.general.string = "help@sanjuan.dev"
                            showMailUnavailable = true
                        }
                    }
                }
            }
            .alert("Mail Isn't Set Up", isPresented: $showMailUnavailable) {
                Button("OK") {}
            } message: {
                Text("We copied help@sanjuan.dev to your clipboard. Send us a message from any email app.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
