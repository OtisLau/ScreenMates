import SwiftUI

/// Traffic controller for onboarding → username → group → dashboard.
struct ContentView: View {
    @StateObject private var cloudManager = CloudKitManager.shared

    var body: some View {
        Group {
            if !cloudManager.isSetupDone {
                OnboardingView()
            } else if !cloudManager.usernameSet || cloudManager.myDisplayName.isEmpty {
                UsernameSetupView()
            } else if cloudManager.myGroupID.isEmpty {
                GroupSelectionView()
            } else {
                DashboardView()
            }
        }
    }
}
