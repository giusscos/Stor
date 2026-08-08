import SwiftUI

struct ContentView: View {
    @State private var credentials: ASCCredentials? = try? KeychainService.shared.load()
    @State private var selectedApp: AppRecord?

    var body: some View {
        Group {
            if credentials == nil {
                OnboardingView { saved in
                    credentials = saved
                }
            } else {
                NavigationSplitView {
                    AppSidebarView(
                        selectedApp: $selectedApp,
                        credentials: $credentials
                    )
                } detail: {
                    if let app = selectedApp {
                        AppDetailView(app: app)
                    } else {
                        ContentUnavailableView(
                            "No App Selected",
                            systemImage: "app.badge",
                            description: Text("Select an app from the sidebar, or add one with the + button.")
                        )
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
