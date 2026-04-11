import SwiftUI

/// Routes the user through onboarding → phone auth → display name → contacts → dashboard.
/// The group gate (myGroupID) is no longer used for routing.
struct ContentView: View {
    @ObservedObject private var cloudManager = CloudKitManager.shared
    @ObservedObject private var phoneAuth = PhoneAuthManager.shared

    var body: some View {
        Group {
            if !cloudManager.isSetupDone {
                OnboardingView()
            } else if !phoneAuth.isPhoneVerified {
                PhoneEntryView()
            } else if cloudManager.myDisplayName.isEmpty {
                UsernameSetupView()
            } else if !phoneAuth.contactsHandled {
                ContactsPermissionView()
            } else {
                DashboardView()
            }
        }
    }
}
