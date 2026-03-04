import SwiftUI
import StoreKit

struct TipJarView: View {
    @StateObject private var manager = TipJarManager()

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("tipjar_title", tableName: nil, bundle: .main, comment: "")
                        .font(.title2)
                        .bold()
                    Text("tipjar_description", tableName: nil, bundle: .main, comment: "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                if manager.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if manager.products.isEmpty {
                    Text(String(localized: "tipjar_unavailable", defaultValue: "現在、商品を取得できません。"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(manager.products, id: \.id) { product in
                        tipRow(product: product)
                    }
                }
            }

            if case .success = manager.purchaseState {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.pink)
                            Text("tipjar_thanks", tableName: nil, bundle: .main, comment: "")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding()
                    .listRowBackground(Color.clear)
                }
            }

            if case .error(let message) = manager.purchaseState {
                Section {
                    Text(message)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(String(localized: "tipjar_nav_title", defaultValue: "応援する"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await manager.loadProducts()
        }
    }

    private func tipRow(product: Product) -> some View {
        let emoji = emojiForProduct(product)
        return Button {
            Task {
                await manager.purchase(product)
            }
        } label: {
            HStack {
                Text(emoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.body)
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.headline)
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 4)
        }
        .disabled(manager.purchaseState == .purchasing)
        .accessibilityLabel(Text("\(product.displayName) \(product.displayPrice)"))
    }

    private func emojiForProduct(_ product: Product) -> String {
        let ids = TipJarManager.productIDs
        if product.id == ids[0] { return "☕️" }
        if product.id == ids[1] { return "🍵" }
        return "🎉"
    }
}
