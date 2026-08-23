import SwiftUI

@main
struct VoiceDeskApp: App {
    @State private var model = AppModel.makeForLaunch()

    var body: some Scene {
        WindowGroup {
            ConversationScreen()
                .environment(model)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    _ = model.handleOpenURL(url)
                }
                .task {
                    await model.restoreGoogleIfNeeded()
                    VoiceCloudDogfoodClient.shared.prepareOnLaunch()
                }
        }
    }
}
