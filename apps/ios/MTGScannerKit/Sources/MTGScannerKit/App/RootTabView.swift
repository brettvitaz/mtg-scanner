import SwiftUI

public struct RootTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        @Bindable var appModel = appModel
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

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        .onChange(of: appModel.shouldShowResults) { _, newValue in
            if newValue {
                selectedTab = 1
                appModel.shouldShowResults = false
            }
        }
        .alert("Server Unavailable", isPresented: $appModel.showConnectionAlert) {
            Button("OK", role: .cancel) {}
            Button("Settings") { selectedTab = 3 }
        } message: {
            Text(appModel.connectionAlertMessage)
        }
        .alert("Undo Delete?", isPresented: $appModel.showUndoAlert) {
            Button("Undo") { appModel.confirmUndo() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore the last deleted card.")
        }
        .onShake {
            appModel.undoLatestDelete()
        }
    }
}
