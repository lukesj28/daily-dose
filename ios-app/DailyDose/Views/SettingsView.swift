import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showMailUnavailable = false
    @AppStorage("highlightColorR") private var highlightR: Double = 1.0
    @AppStorage("highlightColorG") private var highlightG: Double = 0.93
    @AppStorage("highlightColorB") private var highlightB: Double = 0.27

    private var highlightColor: Binding<Color> {
        Binding(
            get: { Color(red: highlightR, green: highlightG, blue: highlightB) },
            set: { newColor in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                if UIColor(newColor).getRed(&r, green: &g, blue: &b, alpha: nil) {
                    highlightR = Double(r)
                    highlightG = Double(g)
                    highlightB = Double(b)
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Annotations") {
                    ColorPicker("Highlight Color", selection: highlightColor, supportsOpacity: false)
                }

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
