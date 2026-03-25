import SwiftUI
import StoreKit
import Siren

@main
struct KotenOCRApp: App {
    @StateObject private var ocrEngine = OCREngine()
    private var transactionListener: Task<Void, Never>?

    init() {
        MetricKitManager.shared.start()

        transactionListener = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
        }
    }

    private func configureSiren() {
        let siren = Siren.shared
        siren.rulesManager = RulesManager(
            majorUpdateRules: .critical,
            minorUpdateRules: .annoying,
            patchUpdateRules: .default
        )
        siren.wail()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ocrEngine)
                .onAppear {
                    ocrEngine.initialize()
                    configureSiren()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    ocrEngine.handleMemoryWarning()
                }
        }
    }
}
