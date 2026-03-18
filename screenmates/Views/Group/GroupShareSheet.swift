import SwiftUI

// Shown after successfully creating a group.
// Big code display + share button so you can immediately send it to friends.
struct GroupShareSheet: View {
    let groupID: String
    @Environment(\.dismiss) var dismiss

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .padding()
            }

            Spacer()

            VStack(spacing: 28) {
                // Title
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color(UIColor.systemGreen))

                    Text("Group Created!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Share this code with friends")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Big code display
                VStack(spacing: 10) {
                    Text("Your Group Code")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .kerning(1)

                    Button {
                        UIPasteboard.general.string = groupID
                        withAnimation(.spring(response: 0.3)) { copied = true }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(groupID)
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .kerning(5)

                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 18))
                                .foregroundStyle(copied ? Color(UIColor.systemGreen) : Color.secondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .glassCard(cornerRadius: AppTheme.cornerRadiusLarge)
                    }
                    .buttonStyle(.plain)

                    if copied {
                        Text("Copied!")
                            .font(.caption)
                            .foregroundStyle(Color(UIColor.systemGreen))
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            }

            Spacer()

            // Action buttons
            VStack(spacing: 10) {
                ShareLink(
                    item: shareMessage,
                    subject: Text("Join my ScreenMates group"),
                    message: Text(shareMessage)
                ) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Invite Friends")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .glassProminentButtonStyle()

                Button {
                    dismiss()
                } label: {
                    Text("Do it later")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private var shareMessage: String {
        "Join my ScreenMates group!\n\nGroup Code: \(groupID)\n\nLet's compare screen time — less is more!"
    }
}
