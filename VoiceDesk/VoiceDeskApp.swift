import SwiftUI

@main
struct VoiceDeskApp: App {
    @State private var model = AppModel.makeForLaunch()

    var body: some Scene {
        WindowGroup {
            ConversationScreen()
                .environment(model)
                .preferredColorScheme(.light)
        }
    }
}
