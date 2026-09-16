import SwiftUI

/// Captures scene-bound window actions for menu commands and permission flows.
struct WindowActionsReader: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    let appState: AppState

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appState.assignWindowActions(open: openWindow, dismiss: dismissWindow)
            }
    }
}
