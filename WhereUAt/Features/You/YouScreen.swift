import SwiftUI
import PhotosUI

/// Profile plus the small set of settings the app actually needs.
struct YouScreen: View {
    @Environment(AppState.self) private var state
    @State private var showEditProfile = false
    @State private var confirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                List {
                    Section {
                        Button { showEditProfile = true } label: {
                            HStack(spacing: 14) {
                                Avatar(profile: state.myProfile, size: 58)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(state.myProfile.displayName.isEmpty ? "Add your name"
                                                                             : state.myProfile.displayName)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text(accountLine)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.inkMuted.opacity(0.6))
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }

                    Section("Notifications") {
                        row("bell.badge.fill", "Arrival alerts",
                            NotificationService.shared.isAuthorized ? "On" : "Off")
                        Button("Notification Settings") { OpenSettings.app() }
                            .font(.system(size: 15))
                    }

                    Section("Location") {
                        row("location.fill", "Location access", authorizationLabel)
                        row("scope", "Precise location", state.location.isPreciseLocation ? "On" : "Off")
                        Button("Open Settings") { OpenSettings.app() }
                            .font(.system(size: 15))
                    }

                    Section {
                        Text("Where U At keeps only your most recent location — no history of where you've been. Removing a connection deletes the copy of your location that person could read.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkMuted)
                    } header: {
                        Text("Data")
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmingDeleteAll = true
                        } label: {
                            Text("Delete All App Data")
                        }
                    }

                    Section("About") {
                        row("info.circle.fill", "Version", appVersion)
                        row("icloud.fill", "iCloud account",
                            state.accountStatus == .available ? "Connected" : "Not signed in")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("You")
            .sheet(isPresented: $showEditProfile) { EditProfileSheet() }
            .confirmationDialog("Delete all app data?",
                                isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    Task { await state.deleteAllData() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Every connection is removed and the copies of your location other people could read are deleted. This can't be undone.")
            }
        }
    }

    private var accountLine: String {
        state.accountStatus == .available
            ? "Connected through iCloud · no password needed"
            : "Sign in to iCloud in Settings"
    }

    private var authorizationLabel: String {
        switch state.location.authorization {
        case .authorizedAlways:    return "Always"
        case .authorizedWhenInUse: return "While Using"
        case .denied, .restricted: return "Off"
        default:                   return "Not set"
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }

    private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.system(size: 15))
            Spacer()
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkMuted)
        }
    }
}

private struct EditProfileSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorHex = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(spacing: 22) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(profile: preview, size: 110)
                            ZStack {
                                Circle().fill(Theme.brand).frame(width: 32, height: 32)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        }
                    }
                    .padding(.top, 20)
                    .onChange(of: photoItem) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self) {
                                photoData = ImageTools.squareJPEG(data, maxSide: 512)
                            }
                        }
                    }

                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 17, weight: .medium))
                        .padding(14)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(spacing: 10) {
                        Text("Your pin colour")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkMuted)
                        HStack(spacing: 12) {
                            ForEach(Theme.pinChoices, id: \.hexString) { color in
                                Button { colorHex = color.hexString } label: {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 30, height: 30)
                                        .overlay {
                                            Circle().strokeBorder(.white,
                                                lineWidth: colorHex == color.hexString ? 3 : 0)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = state.myProfile.displayName
                colorHex = state.myProfile.pinColorHex
                photoData = state.myProfile.avatarData
            }
        }
    }

    private var preview: PersonProfile {
        var p = state.myProfile
        p.displayName = name
        p.pinColorHex = colorHex
        p.avatarData = photoData
        return p
    }

    /// Saving pushes the new name/photo into every connection zone, so the change
    /// shows up for everyone rather than only locally.
    private func save() {
        var p = state.myProfile
        p.displayName = name.trimmingCharacters(in: .whitespaces)
        p.pinColorHex = colorHex
        p.avatarData = photoData
        p.updatedAt = Date()
        state.updateProfile(p)
        dismiss()
    }
}
