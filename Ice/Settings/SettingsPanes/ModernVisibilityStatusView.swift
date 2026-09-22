import SwiftUI

/// Shows the live result outside the layout editor, which deliberately reveals items.
struct ModernVisibilityStatusView: View {
    @ObservedObject var manager: ModernMenuBarManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(manager.visibilityStatus, systemImage: "menubar.rectangle")
                .accessibilityIdentifier("modernVisibilityStatus")
            if let error = manager.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button("Retry hiding") {
                    manager.retryHiding()
                }
                .help("Try the saved hiding assignments again")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
