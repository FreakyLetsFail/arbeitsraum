import SwiftUI

@main
struct LokalKIWorkspaceApp: App {
    @StateObject private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            WorkspaceRootView(store: store)
                .environmentObject(store.modelLibrary)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .help) {
                Link("Fehler oder Vorschlag melden (GitHub · online)", destination: URL(string: "https://github.com/FreakyLetsFail/arbeitsraum/issues/new/choose")!)
            }
        }
    }
}
