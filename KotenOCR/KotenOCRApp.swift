import SwiftUI

@main
struct KotenOCRApp: App {
    @StateObject private var ocrEngine = OCREngine()

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
