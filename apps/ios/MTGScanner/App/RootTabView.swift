import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ScanView()
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tag(0)

            ResultsView()
                .tabItem {
                    Label("Results", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
        .onChange(of: appModel.shouldShowResults) { _, newValue in
            if newValue {
                selectedTab = 1
                appModel.shouldShowResults = false
            }
        }
        .alert("Server Unavailable", isPresented: $appModel.showConnectionAlert) {
            Button("OK", role: .cancel) {}
            Button("Settings") { selectedTab = 2 }
        } message: {
            Text(appModel.connectionAlertMessage)
        }
    }
}
