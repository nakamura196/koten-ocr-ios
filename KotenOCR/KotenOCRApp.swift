import SwiftUI
import StoreKit

@main
struct KotenOCRApp: App {
    @StateObject private var ocrEngine = OCREngine()
    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ocrEngine)
                .onAppear {
                    ocrEngine.initialize()
                }
        }
    }
}
