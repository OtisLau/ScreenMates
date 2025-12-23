import SwiftUI

/// Share sheet for sharing group code with friends
struct GroupShareSheet: View {
    let groupID: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.green)
                
                // Title
                Text("Group Created!")
                    .font(.title)
                    .bold()
                
                // Group code display
                VStack(spacing: 8) {
                    Text("Your Group Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(groupID)
                        .font(.system(size: 36, weight: .bold))
                        .kerning(3)
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(12)
                }
                
                // Instructions
                Text("Share this code with friends so they can join your group!")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Spacer()
                
                // Share button
                ShareLink(
                    item: shareMessage,
                    subject: Text("Join my ScreenMates group"),
                    message: Text(shareMessage)
                ) {
                    Label("Share Group Code", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                
                // Done button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Success")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var shareMessage: String {
        "Join my ScreenMates group!\n\nGroup Code: \(groupID)\n\nDownload ScreenMates to join and track screen time together!"
    }
}
