import SwiftUI

@main
struct A320OverheadApp: App {
    @State private var model = PanelModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
