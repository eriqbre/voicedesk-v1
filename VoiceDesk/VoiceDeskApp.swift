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
                    // First frame already painted from `makeForLaunch` cache / local state.
                    await Task.yield()
                    await model.prepareAfterFirstPaint()
                    VoiceCloudDogfoodClient.shared.prepareOnLaunch()
                }
        }
    }
}
