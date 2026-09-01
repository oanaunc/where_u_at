import SwiftUI
import MapKit
import CoreLocation

/// Full-screen map with a circular photo marker per person, a search field, and
/// a floating card for whoever is selected.
struct MapScreen: View {
    @Environment(AppState.self) private var state

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selected: UUID?
    @State private var search = ""
    @State private var showInvite = false
    @State private var showMySharing = false
    /// The demo frames everyone once on first appearance — not on every tab
    /// switch, which would override a focus the person just chose elsewhere.
    @State private var didAutoFrame = false

    private var visible: [Connection] {
        let live = state.connections.filter { $0.presence?.isSharing == true }
        guard !search.isEmpty else { return live }
        return live.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
            topBarWithNotice
            bottomLayer
        }
        .onChange(of: state.focusedPlaceID) { _, id in focus(placeID: id) }
        .onChange(of: state.focusedPairingID) { _, id in focus(pairingID: id) }
        .sheet(isPresented: $showInvite) { InviteScreen() }
        .sheet(isPresented: $showMySharing) { MySharingSheet() }
        .sheet(item: Binding(
            get: { selected.flatMap { state.connection(for: $0) } },
            set: { selected = $0?.pairingID }
        )) { connection in
            PersonDetailScreen(pairingID: connection.pairingID)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            if state.focusedPlaceID != nil || state.focusedPairingID != nil {
                focus(placeID: state.focusedPlaceID)
                focus(pairingID: state.focusedPairingID)
            } else if state.isScreenshotDemo && !didAutoFrame {
                didAutoFrame = true
                showEveryone()
            }
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $camera, selection: $selected) {
            UserAnnotation()

            ForEach(visible) { connection in
                if let presence = connection.presence {
                    Annotation(connection.displayName,
                               coordinate: presence.coordinate,
                               anchor: .bottom) {
                        PersonMarker(profile: connection.profile,
                                     isStale: presence.isStale)
                            .onTapGesture { selected = connection.pairingID }
                    }
                    .tag(connection.pairingID)
                }
            }

            // Saved places: a soft radius plus a label, so you can tell which
            // is which. The circle alone reads as an anonymous blue wash once
            // it's wider than the viewport.
            ForEach(state.places) { place in
                MapCircle(center: place.coordinate, radius: place.radius)
                    .foregroundStyle(Theme.sky.opacity(0.10))
                    .stroke(Theme.sky.opacity(0.35), lineWidth: 1)

                Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                    PlaceMarker(place: place, isFocused: state.focusedPlaceID == place.id)
                        .onTapGesture { state.focusedPlaceID = place.id }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .including([.cafe, .restaurant, .park])))
        .mapControls { MapCompass(); MapScaleView() }
        .ignoresSafeArea()
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)
                TextField("Where is…", text: $search)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.sky)
                    .submitLabel(.search)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 0.8))
            .shadow(color: Theme.ink.opacity(0.1), radius: 12, y: 4)

            Button { showMySharing = true } label: {
                Avatar(profile: state.myProfile, size: 42)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(state.effectivelySharing ? Theme.affirmative : Theme.paused)
                            .frame(width: 13, height: 13)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var topBarWithNotice: some View {
        VStack(spacing: 10) {
            topBar
            AccountNotice().padding(.horizontal, 16)
        }
    }

    // MARK: Bottom

    private var bottomLayer: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                Button {
                    showInvite = true
                } label: {
                    Label("Add Someone", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(Theme.brand, in: Capsule())
                        .shadow(color: Theme.sky.opacity(0.4), radius: 14, y: 6)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 10) {
                    mapButton("location.fill") {
                        withAnimation { camera = .userLocation(fallback: .automatic) }
                        state.location.requestOneShot()
                    }
                    mapButton("person.2.fill") { showEveryone() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func mapButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.sky)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.8))
                .shadow(color: Theme.ink.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// Frames one saved place, with a little room around its radius.
    private func focus(placeID: String?) {
        guard let placeID, let place = state.places.first(where: { $0.id == placeID }) else { return }
        // Convert the radius to a span so the whole circle fits with margin.
        let metresPerDegree = 111_000.0
        let delta = max((place.radius * 3) / metresPerDegree, 0.003)
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = .region(MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
            ))
        }
    }

    /// Centres on one person and opens their card.
    private func focus(pairingID: UUID?) {
        guard let pairingID,
              let presence = state.connection(for: pairingID)?.presence,
              presence.isSharing else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            camera = .region(MKCoordinateRegion(
                center: presence.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
            ))
        }
    }

    /// Frames everyone who is currently sharing, plus me.
    private func showEveryone() {
        state.focusedPlaceID = nil
        state.focusedPairingID = nil
        var points = visible.compactMap { $0.presence?.coordinate }
        if let mine = state.location.lastFix?.coordinate { points.append(mine) }
        guard !points.isEmpty else { return }

        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let centre = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.01),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.01)
        )
        withAnimation { camera = .region(MKCoordinateRegion(center: centre, span: span)) }
    }
}

// MARK: - Marker

/// Circular photo in a teardrop, matching the pins in the design.
struct PersonMarker: View {
    var profile: PersonProfile?
    var isStale: Bool

    private var tint: Color { profile?.pinColor ?? Theme.indigo }

    var body: some View {
        VStack(spacing: -6) {
            Avatar(profile: profile, size: 48)
                .opacity(isStale ? 0.55 : 1)

            Triangle()
                .fill(tint)
                .frame(width: 14, height: 10)
                .shadow(color: Theme.ink.opacity(0.2), radius: 3, y: 2)
        }
    }
}

/// A saved place on the map: symbol, name, and a highlighted state when it was
/// just tapped over on the Places tab.
struct PlaceMarker: View {
    var place: Place
    var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: place.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.brand, in: Circle())

            Text(place.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 11)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(isFocused ? Theme.sky : Color.white.opacity(0.7),
                                   lineWidth: isFocused ? 2 : 0.8)
        }
        .shadow(color: Theme.ink.opacity(0.18), radius: 8, y: 3)
        .scaleEffect(isFocused ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
