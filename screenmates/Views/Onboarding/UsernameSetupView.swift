import SwiftUI

/// Username setup screen after onboarding
struct UsernameSetupView: View {
    @StateObject var cloudManager = CloudKitManager.shared
    
    @State private var username = ""
    @State private var isLoading = false
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon
            Image(systemName: "person.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.purple)
            
            // Title
            Text("Choose Your Name")
                .font(.largeTitle)
                .bold()
            
            // Description
            Text("This is how you'll appear to your friends in the leaderboard.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            // Username input
            VStack(spacing: 16) {
                TextField("Enter your name", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.words)
                    .disableAutocorrection(true)
                    .padding(.horizontal)
                
                Button {
                    saveUsername()
                } label: {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || isLoading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .alert("Invalid Name", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text("Please enter a name between 1 and 20 characters.")
        }
    }
    
    private func saveUsername() {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty && trimmed.count <= 20 else {
            showError = true
            return
        }
        
        isLoading = true
        cloudManager.myDisplayName = trimmed
        cloudManager.usernameSet = true
        // Mirror identity for extension and push initial profile to CloudKit.
        cloudManager.updateMyProfile()
        
        // Small delay for UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoading = false
        }
    }
}
