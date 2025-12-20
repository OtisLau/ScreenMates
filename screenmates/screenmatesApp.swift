import SwiftUI
import BackgroundTasks

@main
struct ScreenMatesApp: App {
    @StateObject var cloudMate = CloudMate.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // This listens for the system wake-up call
        .backgroundTask(.appRefresh("com.otishlau.screenmates.refresh")) {
            let success = await cloudMate.performBackgroundCheck()
        }
    }
}
