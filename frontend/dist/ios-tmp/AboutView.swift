import SwiftUI

struct RootforgeProduct: Identifiable {
    let id = UUID()
    let name: String
    let priceLabel: String
    let url: URL
    let blurb: String
}

enum RootforgeLinks {
    static let email = "iamroot88@gmail.com"
    static let mailto = URL(string: "mailto:iamroot88@gmail.com?subject=Rootforge%20Speed%20Test")!
    static let privacy = URL(string: "https://soul-hub.onrender.com/privacy/")!
    static let products: [RootforgeProduct] = [
        .init(name: "Wi-Fi Speed Fix Checklist", priceLabel: "$9", url: URL(string: "https://rootmaster008.gumroad.com/l/hoizp")!, blurb: "A short, practical pass for slow home Wi-Fi."),
        .init(name: "UniFi Home Lab Ops Pack", priceLabel: "$19", url: URL(string: "https://rootmaster008.gumroad.com/l/uhgvyv")!, blurb: "Ops notes for a small UniFi home lab."),
        .init(name: "Custom Script Deposit", priceLabel: "$50", url: URL(string: "https://rootmaster008.gumroad.com/l/ujkbcr")!, blurb: "Kick off a one-off automation or network script."),
        .init(name: "Network Site Survey Deposit", priceLabel: "$75", url: URL(string: "https://rootmaster008.gumroad.com/l/aakouc")!, blurb: "Reserve a survey when the DIY pass is not enough."),
    ]
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("App") {
                    Text("Rootforge Speed Test measures real download, upload, ping, and jitter against Cloudflare’s public speed-test endpoints. Free. No account. No ads. No tracking.")
                }
                Section("Privacy") {
                    Link("Privacy policy", destination: RootforgeLinks.privacy)
                    Text("Data Not Collected — network measurements stay on device; we do not sell or store your results.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Optional Rootforge products") {
                    ForEach(RootforgeLinks.products) { p in
                        Link(destination: p.url) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(p.name).fontWeight(.semibold)
                                    Spacer()
                                    Text(p.priceLabel).foregroundStyle(.secondary)
                                }
                                Text(p.blurb).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Contact") {
                    Link(RootforgeLinks.email, destination: RootforgeLinks.mailto)
                }
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
