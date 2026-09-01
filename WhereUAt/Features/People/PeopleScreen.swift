import SwiftUI
import CoreLocation

struct PeopleScreen: View {
    @Environment(AppState.self) private var state
    @State private var showInvite = false
    @State private var search = ""

    private var sharingWithYou: [Connection] {
        filter(state.connectedPeople)
    }

    private var pending: [Connection] {
        filter(state.pendingInvites)
    }

    private func filter(_ list: [Connection]) -> [Connection] {
        guard !search.isEmpty else { return list }
        return list.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if state.connections.isEmpty {
                    EmptyStateView(
                        symbol: "person.2.badge.plus",
                        title: "Nobody yet",
                        message: "Invite someone you trust. They'll see you once they accept, and you'll see them."
                    )
                } else {
                    List {
                        if !sharingWithYou.isEmpty {
                            Section {
                                ForEach(sharingWithYou) { connection in
                                    NavigationLink {
                                        PersonDetailScreen(pairingID: connection.pairingID)
                                    } label: {
                                        PersonRow(connection: connection,
                                                  distanceText: distanceText(to: connection))
                                    }
                                }
                            } header: {
                                SectionHeader(title: "Sharing with you")
                            }
                        }

                        if !pending.isEmpty {
                            Section {
                                ForEach(pending) { connection in
                                    PendingInviteRow(connection: connection)
                                }
                            } header: {
                                SectionHeader(title: "Pending invites")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .safeAreaInset(edge: .top) {
                AccountNotice().padding(.horizontal, 16).padding(.bottom, 6)
            }
            .navigationTitle("People")
            .searchable(text: $search, prompt: "Search people")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInvite = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .refreshable { await state.sync() }
            .sheet(isPresented: $showInvite) { InviteScreen() }
        }
    }

    private func distanceText(to connection: Connection) -> String? {
        guard let mine = state.location.lastFix,
              let theirs = connection.presence?.location else { return nil }
        return DistanceText.string(metres: theirs.distance(from: mine))
    }
}

/// An invitation I sent that is still waiting to be accepted.
private struct PendingInviteRow: View {
    @Environment(AppState.self) private var state
    var connection: Connection
    @State private var confirmingCancel = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 46, height: 46)
                Image(systemName: "hourglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.sky)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Waiting for them to accept")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkMuted)
            }

            Spacer(minLength: 8)

            Button("Cancel") { confirmingCancel = true }
                .font(.system(size: 14, weight: .medium))
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.caution)
        }
        .padding(.vertical, 6)
        .confirmationDialog("Cancel this invitation?",
                            isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel invitation", role: .destructive) {
                Task { await state.remove(connection) }
            }
            Button("Keep it", role: .cancel) { }
        } message: {
            Text("The link you sent will stop working.")
        }
    }
}
