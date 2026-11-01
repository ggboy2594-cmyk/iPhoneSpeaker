import SwiftUI

@main
struct iPhoneSpeakerApp: App {
    @StateObject private var receiver = AudioReceiver()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(receiver)
        }
    }
}
