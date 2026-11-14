import SwiftUI

@main
struct A320OverheadApp: App {
    @State private var model = PanelModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            // Pending writes are batched once a second: do not lose them when iOS suspends us.
            if phase != .active { model.flushSaves() }
        }
    }
}
