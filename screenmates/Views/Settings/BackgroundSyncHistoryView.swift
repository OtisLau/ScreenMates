import SwiftUI

/// Shows history of background sync events
struct BackgroundSyncHistoryView: View {
    let history: [[String: Any]]
    
    var body: some View {
        List {
            if history.isEmpty {
                Text("No background syncs yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(Array(history.enumerated()), id: \.offset) { index, entry in
                    if let timestamp = entry["timestamp"] as? Date,
                       let success = entry["success"] as? Bool,
                       let blocks = entry["blocks"] as? Int {
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(success ? .green : .red)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    
                                    Text(DateHelpers.relativeTime(from: timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(blocks) blocks")
                                        .font(.headline)
                                        .foregroundColor(.purple)
                                    
                                    Text(success ? "Synced" : "Failed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if !success {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let message = entry["error"] as? String, !message.isEmpty {
                                        Text(message)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    HStack(spacing: 12) {
                                        if let code = entry["ckErrorCode"] as? Int {
                                            Text("CKError: \(code)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        if let retry = entry["retryAfterSeconds"] as? Double {
                                            Text("Retry after: \(Int(retry))s")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Section {
                Text("Background syncs happen automatically when the app is closed. iOS schedules them approximately every 15 minutes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Background Sync History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
