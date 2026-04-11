import SwiftUI
import CloudKit

/// Quick diagnostic view to see what's wrong
struct DiagnosticView: View {
    @ObservedObject var cloudManager = CloudKitManager.shared
    @State private var diagnosticResult = "Running diagnostics..."
    @State private var isPingingCloudKit = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status
                    Text(diagnosticResult)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    
                    // Quick fixes
                    VStack(spacing: 12) {
                        Button {
                            fixDisplayName()
                        } label: {
                            Text("Fix: Set Display Name to Test User")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button {
                            forceSync()
                        } label: {
                            Text("Force Sync & Fetch")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            checkCloudKit()
                        } label: {
                            Text("Check CloudKit Status")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            reuploadPhoneHash()
                        } label: {
                            Text("Re-upload Phone Hash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            cloudKitPing()
                        } label: {
                            if isPingingCloudKit {
                                HStack {
                                    ProgressView()
                                    Text("CloudKit Ping (running...)")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("CloudKit Ping (read + write test)")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPingingCloudKit)
                    }
                    .padding()
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                runDiagnostics()
            }
        }
    }
    
    private func runDiagnostics() {
        var result = "=== DIAGNOSTICS ===\n\n"
        
        // Check basic setup
        result += " Setup Done: \(cloudManager.isSetupDone)\n"
        result += " Username Set: \(cloudManager.usernameSet)\n\n"
        
        // Check user data
        result += "USER DATA:\n"
        result += "  ID: \(cloudManager.myID)\n"
        result += "  Name: '\(cloudManager.myDisplayName)'\n"
        if cloudManager.myDisplayName.isEmpty {
            result += "   DISPLAY NAME IS EMPTY!\n"
            result += "     This is why you're not in leaderboard!\n"
        } else {
            result += "   Display name is set\n"
        }
        result += "\n"
        
        // Check group
        result += "GROUP DATA:\n"
        result += "  Group ID: '\(cloudManager.myGroupID)'\n"
        if cloudManager.myGroupID.isEmpty {
            result += "   No group joined\n"
        } else {
            result += "   In group \(cloudManager.myGroupID)\n"
        }
        result += "  Members: \(cloudManager.groupMembers.count)\n"
        if cloudManager.groupMembers.isEmpty {
            result += "   No members loaded\n"
        } else {
            result += "   Members loaded:\n"
            for member in cloudManager.groupMembers {
                result += "     - \(member.displayName) (\(member.blocks) blocks)\n"
            }
        }
        result += "\n"
        
        // Phone auth / contacts discovery
        result += "PHONE AUTH:\n"
        let phoneNum = PhoneAuthManager.shared.phoneNumberE164
        let phoneHash = PhoneAuthManager.shared.phoneHash
        result += "  E164: '\(phoneNum.isEmpty ? "NOT SET" : phoneNum)'\n"
        result += "  Hash: '\(phoneHash.isEmpty ? "NOT SET — contacts won't match" : String(phoneHash.prefix(12)) + "...")'\n"
        if phoneHash.isEmpty {
            result += "  ⚠️ No phone hash — tap 'Re-upload Phone Hash' to fix\n"
        }
        result += "\n"

        // Check sync status
        if let lastSync = cloudManager.lastSyncTime {
            result += "SYNC STATUS:\n"
            result += "  Last Sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))\n"
            result += "  (\(DateHelpers.relativeTime(from: lastSync)))\n"
        } else {
            result += "SYNC STATUS:\n"
            result += "   Never synced\n"
        }

        diagnosticResult = result
    }
    
    private func reuploadPhoneHash() {
        let hash = PhoneAuthManager.shared.phoneHash
        let e164 = PhoneAuthManager.shared.phoneNumberE164
        if hash.isEmpty {
            diagnosticResult += "\n\n⚠️ No phone hash stored locally — go through phone number setup first\n"
            return
        }
        diagnosticResult += "\n\n Uploading phone hash to CloudKit...\n"
        diagnosticResult += "  E164: \(e164)\n"
        diagnosticResult += "  Hash prefix: \(String(hash.prefix(12)))...\n"
        cloudManager.updateMyProfile {
            Task { @MainActor in
                diagnosticResult += " Done — hash uploaded.\n"
                runDiagnostics()
            }
        }
    }

    private func fixDisplayName() {
        cloudManager.myDisplayName = "TestUser"
        cloudManager.usernameSet = true
        diagnosticResult += "\n\n Set display name to 'TestUser'\n"
        diagnosticResult += "Now forcing sync...\n"

        cloudManager.updateMyProfile {
            Task { @MainActor in
                CloudKitManager.shared.fetchGroupData(useCache: false)
                try? await Task.sleep(for: .seconds(2))
                runDiagnostics()
            }
        }
    }

    private func forceSync() {
        diagnosticResult += "\n\n Forcing sync...\n"

        print("=== FORCE SYNC START ===")
        print("User ID: \(cloudManager.myID)")
        print("Display Name: \(cloudManager.myDisplayName)")
        print("Group ID: \(cloudManager.myGroupID)")

        cloudManager.updateMyProfile {
            Task { @MainActor in
                print(" updateMyProfile completed")
                CloudKitManager.shared.fetchGroupData(useCache: false)
                try? await Task.sleep(for: .seconds(3))
                diagnosticResult += "Sync completed, refreshing...\n"
                runDiagnostics()
            }
        }
    }

    private func checkCloudKit() {
        diagnosticResult += "\n\n Checking CloudKit...\n"

        Task { @MainActor in
            do {
                let status = try await cloudManager.container.accountStatus()
                switch status {
                case .available:
                    diagnosticResult += " iCloud account is available\n"
                case .noAccount:
                    diagnosticResult += " NO iCloud ACCOUNT!\n"
                    diagnosticResult += "   Fix: Settings → Sign in to iCloud\n"
                case .restricted:
                    diagnosticResult += " iCloud is RESTRICTED\n"
                case .couldNotDetermine:
                    diagnosticResult += " Could not determine iCloud status\n"
                case .temporarilyUnavailable:
                    diagnosticResult += " iCloud temporarily unavailable\n"
                @unknown default:
                    diagnosticResult += " Unknown iCloud status\n"
                }
            } catch {
                diagnosticResult += " Account check failed: \(error.localizedDescription)\n"
                return
            }

            if !cloudManager.myGroupID.isEmpty {
                diagnosticResult += "\nFetching group data...\n"
                cloudManager.fetchGroupData(useCache: false)
                try? await Task.sleep(for: .seconds(3))
                runDiagnostics()
            } else {
                diagnosticResult += " No group ID to check\n"
            }
        }
    }

    private func cloudKitPing() {
        guard !isPingingCloudKit else { return }
        isPingingCloudKit = true

        diagnosticResult += "\n\n=== CLOUDKIT PING ===\n"
        diagnosticResult += "Container: \(AppConstants.cloudKitContainerID)\n"

        Task {
            var lines: [String] = []

            // 1) iCloud account status
            do {
                let status = try await cloudManager.container.accountStatus()
                switch status {
                case .available:
                    lines.append("Account:  available")
                case .noAccount:
                    lines.append("Account:  no iCloud account signed in")
                case .restricted:
                    lines.append("Account:  restricted")
                case .couldNotDetermine:
                    lines.append("Account:  could not determine")
                case .temporarilyUnavailable:
                    lines.append("Account:  temporarily unavailable")
                @unknown default:
                    lines.append("Account:  unknown status")
                }
            } catch {
                lines.append("Account:  status check failed: \(error.localizedDescription)")
                await MainActor.run {
                    diagnosticResult += lines.joined(separator: "\n") + "\n"
                    isPingingCloudKit = false
                }
                return
            }

            // 2) CloudKit read test (query by user_id)
            var readSucceeded = false
            do {
                let predicate = NSPredicate(format: "user_id == %@", cloudManager.myID)
                let query = CKQuery(recordType: "UserProfile", predicate: predicate)
                let (matchResults, _) = try await cloudManager.database.records(matching: query)
                lines.append("Read:  ok (\(matchResults.count) matching UserProfile record(s))")
                readSucceeded = true
            } catch {
                if let ckError = error as? CKError {
                    lines.append("Read:  CKError(\(ckError.code.rawValue)): \(ckError.localizedDescription)")
                    if ckError.code == .unknownItem,
                       ckError.localizedDescription.localizedCaseInsensitiveContains("Did not find record type") {
                        lines.append("  Hint: CloudKit schema is missing for 'UserProfile' in this environment.")
                        lines.append("  Fix: Create/deploy the record types in CloudKit Dashboard.")
                    }
                } else {
                    lines.append("Read:  \(error.localizedDescription)")
                }
            }

            // 3) CloudKit write test (update/create UserProfile) — only if display name is set
            // We run this even if the read failed, because a successful write can create schema in Development
            // (and it gives a more actionable error in Production).
            if cloudManager.myDisplayName.isEmpty {
                lines.append("Write: ⏭ skipped (display name is empty)")
            } else {
                let writeResult = await cloudManager.performBackgroundCheckDetailed()
                if writeResult.success {
                    lines.append("Write:  ok (saved UserProfile)")
                } else {
                    lines.append("Write:  failed")
                    if let msg = writeResult.errorMessage, !msg.isEmpty {
                        lines.append("  \(msg)")
                    }
                    if let code = writeResult.ckErrorCode {
                        lines.append("  CKError: \(code)")
                    }
                    if let retry = writeResult.retryAfterSeconds {
                        lines.append("  Retry after: \(Int(retry))s")
                    }
                }
            }

            if !readSucceeded {
                lines.append("Next: If write succeeded, try Ping again—read should start working after schema exists.")
            }

            await MainActor.run {
                diagnosticResult += lines.joined(separator: "\n") + "\n"
                isPingingCloudKit = false
            }
        }
    }
}
