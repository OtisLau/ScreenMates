import SwiftUI
import FamilyControls
import DeviceActivity
import BackgroundTasks
import Combine // <--- THIS WAS MISSING!

struct ContentView: View {
    @StateObject var cloudMate = CloudMate.shared
    @Environment(\.scenePhase) var scenePhase
    
    // --- TRAFFIC CONTROLLER ---
    var body: some View {
        Group {
            if !cloudMate.isSetupDone {
                OnboardingView()
            } else if cloudMate.myGroupID.isEmpty {
                GroupSelectionView()
            } else {
                DashboardView()
            }
        }
        // FIXED: Updated syntax for iOS 17+ to remove yellow warning
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                scheduleAppRefresh()
            }
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.otishlau.screenmates.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

// --- VIEW 1: ONBOARDING & PERMISSIONS ---
struct OnboardingView: View {
    @StateObject var cloudMate = CloudMate.shared
    @State var selection = FamilyActivitySelection()
    @State var isPickerPresented = false
    let center = AuthorizationCenter.shared
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "hand.raised.fill").font(.system(size: 60)).foregroundColor(.purple)
            Text("Welcome to ScreenMates").font(.largeTitle).bold()
            Text("To start, we need to know which apps distract you.").multilineTextAlignment(.center).padding()
            
            Button("1. Grant Permissions") {
                Task { try? await center.requestAuthorization(for: .individual) }
            }.buttonStyle(.bordered)
            
            Button("2. Select Distracting Apps") {
                isPickerPresented = true
            }.buttonStyle(.bordered)
            
            if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty {
                Button("3. Save & Continue") {
                    startMonitoring(selection: selection)
                    cloudMate.isSetupDone = true
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
    }
    
    func startMonitoring(selection: FamilyActivitySelection) {
        let center = DeviceActivityCenter()
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        // TEST MODE: 1 Minute = 1 Block
        let blockSize = 1
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        
        for i in 1...48 {
            let eventName = DeviceActivityEvent.Name("block_\(i)")
            let minutes = i * blockSize
            let event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: minutes)
            )
            events[eventName] = event
        }
        
        do {
            center.stopMonitoring()
            try center.startMonitoring(
                DeviceActivityName("dailyTracking"),
                during: schedule,
                events: events
            )
            print("✅ Monitoring Started with \(events.count) Checkpoints")
        } catch { print("Error: \(error)") }
    }
}

// --- VIEW 2: GROUP SELECTION ---
struct GroupSelectionView: View {
    @StateObject var cloudMate = CloudMate.shared
    @State private var groupInput = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Join a Squad").font(.title).bold()
            
            TextField("Enter Group ID", text: $groupInput)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.allCharacters)
                .padding()
            
            Button("Join Group") {
                cloudMate.joinGroup(groupID: groupInput.uppercased())
            }.disabled(groupInput.isEmpty).buttonStyle(.borderedProminent)
            
            Text("OR").foregroundColor(.gray)
            
            Button("Create New Group") {
                cloudMate.createGroup { newID in
                    print("Created Group: \(newID)")
                }
            }.buttonStyle(.bordered)
        }
        .padding()
    }
}

// --- VIEW 3: THE DASHBOARD (Main App) ---
struct DashboardView: View {
    @StateObject var cloudMate = CloudMate.shared
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 25) {
                    // Header
                    VStack {
                        Text("GROUP ID").font(.caption).foregroundColor(.gray)
                        Text(cloudMate.myGroupID).font(.largeTitle).bold().kerning(2)
                    }.padding().background(Color.purple.opacity(0.1)).cornerRadius(12)
                    
                    // Leaderboard
                    VStack(alignment: .leading, spacing: 15) {
                        Text("LEADERBOARD").font(.caption).bold().foregroundColor(.secondary)
                        
                        ForEach(cloudMate.groupMembers) { member in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(member.name == cloudMate.myID ? "You" : member.name)
                                        .font(.headline)
                                    Text("Last update: \(member.lastUpdate.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption2).foregroundColor(.gray)
                                }
                                Spacer()
                                // Calculate Time: Blocks * 1 (Since we are in Test Mode)
                                Text("\(member.blocks * 1) min")
                                    .font(.title2).bold()
                                    .foregroundColor(member.blocks > 8 ? .red : .green)
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        
                        if cloudMate.groupMembers.isEmpty {
                            Text("Waiting for data...").padding()
                        }
                    }
                    .padding()
                    
                    Button("Force Refresh") {
                        cloudMate.updateMyProfile() // Upload my latest data
                        cloudMate.fetchGroupData() // Download friends data
                    }.padding(.top, 20)
                }
            }
            .navigationTitle("ScreenMates")
            .onAppear {
                cloudMate.fetchGroupData()
                cloudMate.updateMyProfile()
            }
            .onReceive(timer) { _ in
                // Periodically check for new data while looking at screen
                cloudMate.fetchGroupData()
            }
        }
    }
}
