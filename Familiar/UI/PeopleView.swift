import SwiftUI

/// Placeholder; S4 ships the real list with thumbnails, detail and removal.
struct PeopleView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var people: [Person] = []
    var body: some View {
        List {
            if people.isEmpty {
                Text("No one remembered yet.").foregroundStyle(.secondary)
            }
            ForEach(people) { p in
                VStack(alignment: .leading) {
                    Text(p.name).font(.headline)
                    Text("met at \(p.met.placeName ?? "unknown place"), \(p.met.at.formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("People")
        .task { people = coordinator.services?.peopleStore.all() ?? [] }
    }
}
