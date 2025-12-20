import SwiftUI
import FamilyControls
import DeviceActivity
import UserNotifications

struct ContentView: View {
    @State var selection = FamilyActivitySelection()
    @State var isPickerPresented = false
    @State var friendIDInput: String = ""
    
    @StateObject var cloudMate = CloudMate.shared
    
    // REPLACE with your App Group ID
    let sharedDefaults = UserDefaults(suiteName: "group.com.otishlau.screenmates")
    
    let center = AuthorizationCenter.shared
    let activityCenter = DeviceActivityCenter()

    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                // Header
                VStack(spacing: 5) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.purple)
                    Text("ScreenMates")
                        .font(.largeTitle)
                        .bold()
                }
                .padding(.top)

                // Your Status
                VStack(spacing: 10) {
                    Text("MY STATUS")
                        .font(.caption).bold().foregroundColor(.secondary)
                    
                    VStack {
                        Text("My ID Code:").font(.caption).foregroundColor(.gray)
                        Text(cloudMate.myID)
                            .font(.title2).fontWeight(.heavy).kerning(1)
                            .textSelection(.enabled)
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.1)).cornerRadius(12)
                    
                    Text("Last Upload: \(cloudMate.lastSyncStatus)")
                        .font(.caption2).foregroundColor(.gray)
                }
                .padding(.horizontal)

                // Friend Monitor
                VStack(spacing: 15) {
                    Text("FRIEND MONITOR")
                        .font(.caption).bold().foregroundColor(.secondary)
                    
                    HStack {
                        TextField("Enter Friend's ID", text: $friendIDInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.allCharacters)
                        
                        Button {
                            cloudMate.checkFriendStatus(friendCode: friendIDInput)
                        } label: {
                            Image(systemName: "arrow.clockwise.circle.fill").font(.title2)
                        }
                    }
                    
                    Text(cloudMate.friendStatus)
                        .font(.headline).padding()
                        .frame(maxWidth: .infinity)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .cornerRadius(10)
                }
                .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(15).padding(.horizontal)
                
                // Controls
                VStack(spacing: 15) {
                    Button("Select Apps") { isPickerPresented = true }
                        .buttonStyle(.bordered)
                    
                    Button("Start Tracking (15 min)") { startMonitoring() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty)
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            setupPermissions()
            checkForAndUploadEvents()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkForAndUploadEvents()
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
    }
    
    var statusColor: Color {
        if cloudMate.friendStatus.contains("SAFE") || cloudMate.friendStatus.contains("Clean") { return .green }
        if cloudMate.friendStatus.contains("LIMIT HIT") { return .red }
        return .blue
    }
    
    func checkForAndUploadEvents() {
        if let lastHitDate = sharedDefaults?.object(forKey: "LastLimitHitDate") as? Date {
            cloudMate.logThresholdEvent()
            sharedDefaults?.removeObject(forKey: "LastLimitHitDate")
        }
    }
    
    func setupPermissions() {
        Task {
            try? await center.requestAuthorization(for: .individual)
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }
    
    func startMonitoring() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        // 15 Minute Limit
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: 1)
        )
        
        do {
            activityCenter.stopMonitoring()
            try activityCenter.startMonitoring(
                DeviceActivityName("dailyTotalTracking"),
                during: schedule,
                events: [DeviceActivityEvent.Name("totalTimeLimit"): event]
            )
        } catch { print("Error: \(error)") }
    }
}
