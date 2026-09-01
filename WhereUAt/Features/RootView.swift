import SwiftUI
import CloudKit

/// Map · People · Places · Privacy · You — the five places everything else opens from.
struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .map

    enum Tab: Hashable { case map, people, places, privacy, you }

    var body: some View {
        @Bindable var state = state

        Group {
            if !state.hasCompletedOnboarding {
                OnboardingFlow()
            } else {
                TabView(selection: $selection) {
                    MapScreen()
                        .tabItem { Label("Map", systemImage: "map.fill") }
                        .tag(Tab.map)

                    PeopleScreen()
                        .tabItem { Label("People", systemImage: "person.2.fill") }
                        .tag(Tab.people)
                        .badge(state.pendingIncomingCount)

                    PlacesScreen()
                        .tabItem { Label("Places", systemImage: "mappin.and.ellipse") }
                        .tag(Tab.places)

                    PrivacyScreen()
                        .tabItem { Label("Privacy", systemImage: "lock.shield.fill") }
                        .tag(Tab.privacy)

                    YouScreen()
                        .tabItem { Label("You", systemImage: "person.crop.circle.fill") }
                        .tag(Tab.you)
                }
            }
        }
        // An invitation can arrive at any moment, including on a cold launch.
        .sheet(item: $state.pendingInvitation) { metadata in
            InvitationScreen(metadata: metadata)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await state.sync() } }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { state.errorMessage != nil },
                                    set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

extension AppState {
    /// Invitations sent that nobody has accepted yet — surfaced on the People tab.
    var pendingIncomingCount: Int { pendingInvites.count }
}

/// `CKShare.Metadata` isn't `Identifiable`, but sheets want it to be.
extension CKShare.Metadata: @retroactive Identifiable {
    public var id: String { share.recordID.recordName + share.recordID.zoneID.zoneName }
}
