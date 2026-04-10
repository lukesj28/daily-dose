import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Medical Disclaimer") {
                    Text("This application is for informational and educational purposes only. It does not constitute professional medical advice, diagnosis, or treatment. Always seek the advice of a physician or other qualified health provider with any questions you may have regarding a medical condition.")
                }

                section("Data Source") {
                    Text("This application utilizes data from the National Library of Medicine (NLM) PubMed Central® (PMC) database.")
                }

                section("Non-Affiliation") {
                    Text("This application is not endorsed by, sponsored by, or affiliated with the NLM, NCBI, or the United States Government.")
                }

                section("Content Licensing") {
                    Text("Articles displayed in this app are sourced from the PubMed Central Open Access Subset. Each article remains the copyright of its respective authors and is distributed under its original open-access license (such as Creative Commons). See the footer of each article for specific licensing details.")
                }
            }
            .padding(20)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
