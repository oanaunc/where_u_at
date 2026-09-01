import SwiftUI
import MapKit
import CoreLocation

/// Saved places power arrival and departure alerts. They live in the private
/// database and are never shared — the people you connect with can't tell that
/// "Home" exists, let alone where it is.
struct PlacesScreen: View {
    @Environment(AppState.self) private var state
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if state.places.isEmpty {
                    EmptyStateView(
                        symbol: "mappin.and.ellipse",
                        title: "No places yet",
                        message: "Add Home, Work or anywhere else, then get a nudge when someone arrives or leaves."
                    )
                } else {
                    List {
                        ForEach(state.places) { place in
                            HStack(spacing: 13) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Theme.brandSoft)
                                        .frame(width: 42, height: 42)
                                    Image(systemName: place.symbol)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Theme.sky)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(place.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text("\(Int(place.radius)) m radius")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 5)
                        }
                        .onDelete { indexes in
                            let doomed = indexes.map { state.places[$0] }
                            Task { for place in doomed { await state.deletePlace(place) } }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Places")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddPlaceSheet() }
        }
    }
}

private struct AddPlaceSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = Place.symbolChoices[0]
    @State private var radius: Double = 150
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var centre: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(spacing: 14) {
                    // The pin stays fixed at the centre; the map moves under it.
                    ZStack {
                        MapReader { _ in
                            Map(position: $camera)
                                .mapStyle(.standard(elevation: .flat))
                                .onMapCameraChange(frequency: .continuous) { context in
                                    centre = context.camera.centerCoordinate
                                }
                        }
                        Image(systemName: "mappin")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Theme.indigo)
                            .shadow(color: Theme.ink.opacity(0.25), radius: 5, y: 3)
                            .offset(y: -14)
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    TextField("Place name", text: $name)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(Theme.ink)
                        .tint(Theme.sky)
                        .padding(14)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Place.symbolChoices, id: \.self) { choice in
                                Button { symbol = choice } label: {
                                    Image(systemName: choice)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(symbol == choice ? .white : Theme.sky)
                                        .frame(width: 44, height: 44)
                                        .background(symbol == choice ? AnyShapeStyle(Theme.brand)
                                                                     : AnyShapeStyle(Color.white.opacity(0.8)),
                                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Radius · \(Int(radius)) m")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkMuted)
                        Slider(value: $radius, in: 50...1000, step: 25)
                            .tint(Theme.sky)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .navigationTitle("Add Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || centre == nil)
                }
            }
        }
    }

    private func save() {
        guard let centre else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        Task {
            await state.addPlace(name: trimmed, symbol: symbol, coordinate: centre, radius: radius)
            dismiss()
        }
    }
}

/// "Notify Me" from a person's page — arrival and departure rules per place.
struct NotifyMeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let connection: Connection

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if state.places.isEmpty {
                    EmptyStateView(
                        symbol: "bell.slash",
                        title: "Add a place first",
                        message: "Arrival alerts need somewhere to arrive at. Add Home or Work on the Places tab."
                    )
                } else {
                    List {
                        ForEach(state.places) { place in
                            Section {
                                ForEach(NotifyTrigger.allCases) { trigger in
                                    Toggle(isOn: Binding(
                                        get: { hasRule(place: place, trigger: trigger) },
                                        set: { state.setRule(pairingID: connection.pairingID,
                                                             placeID: place.id,
                                                             trigger: trigger,
                                                             enabled: $0) }
                                    )) {
                                        Text(trigger.label).font(.system(size: 15))
                                    }
                                    .tint(Theme.affirmative)
                                }
                            } header: {
                                Label(place.name, systemImage: place.symbol)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Notify me about \(connection.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .task { await NotificationService.shared.requestAuthorization() }
        }
    }

    private func hasRule(place: Place, trigger: NotifyTrigger) -> Bool {
        state.notifyRules.contains {
            $0.pairingID == connection.pairingID && $0.placeID == place.id
                && $0.trigger == trigger && $0.enabled
        }
    }
}
