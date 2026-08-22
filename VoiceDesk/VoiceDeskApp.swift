import SwiftUI

@main
struct VoiceDeskApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ConversationScreen()
                .environment(model)
                .preferredColorScheme(.light)
        }
    }
}
