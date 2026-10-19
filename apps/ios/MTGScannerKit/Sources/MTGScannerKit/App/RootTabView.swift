import SwiftData
import SwiftUI
import UIKit

public struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @State private var captureModel = AutoScanViewModel()
    @State private var cameraSession: CameraSessionManager
    private let captureContent: ((DetectionMode, Bool) -> AnyView)?

    public init() {
        captureContent = nil
        _cameraSession = State(initialValue: CameraSessionManager())
    }

    init(cameraSession: CameraSessionManager) {
        captureContent = nil
        _cameraSession = State(initialValue: cameraSession)
    }

    init(captureContent: @escaping (DetectionMode, Bool) -> AnyView) {
        self.captureContent = captureContent
        _cameraSession = State(initialValue: CameraSessionManager())
    }

    public var body: some View {
        @Bindable var appModel = appModel
        TabView(selection: Binding(get: { appModel.selectedTab }, set: appModel.selectTab)) {
            captureDestination(.scan, tab: .table)
                .tabItem { Label("Table", systemImage: DetectionMode.scan.systemImage) }
                .tag(AppTab.table)

            captureDestination(.auto, tab: .station)
                .tabItem { Label("Station", systemImage: DetectionMode.auto.systemImage) }
                .tag(AppTab.station)

            ResultsView()
                .tabItem {
                    Label("Results", systemImage: "list.bullet.rectangle")
                }
                .badge(appModel.resultsBadgeText)
                .tag(AppTab.results)

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(AppTab.library)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .background(ResultsTabAccessibility(value: appModel.resultsBadgeAccessibilityValue))
        .onChange(of: appModel.shouldShowResults) { _, newValue in
            if newValue {
                appModel.selectTab(.results)
                appModel.shouldShowResults = false
            }
        }
        .alert("Server Unavailable", isPresented: $appModel.showConnectionAlert) {
            Button("OK", role: .cancel) {}
            Button("Settings") { appModel.selectTab(.settings) }
        } message: {
            Text(appModel.connectionAlertMessage)
        }
        .task {
            appModel.modelContext = modelContext
            await appModel.retryRecognitionFeedback()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await appModel.retryRecognitionFeedback() } }
        }
        .environment(\.undoSelectedTab, appModel.selectedTab.rawValue)
    }
    @ViewBuilder
    private func captureDestination(_ mode: DetectionMode, tab: AppTab) -> some View {
        if let captureContent {
            captureContent(mode, appModel.selectedTab == tab)
        } else {
            ScanView(detectionMode: .constant(mode), isActive: appModel.selectedTab == tab,
                     autoScanViewModel: captureModel, cameraSession: cameraSession)
        }
    }

}

/// SwiftUI does not forward accessibilityValue to UITabBarItem.
private struct ResultsTabAccessibility: UIViewRepresentable {
    let value: String

    func makeUIView(context: Context) -> TabAccessibilityView { TabAccessibilityView() }

    func updateUIView(_ view: TabAccessibilityView, context: Context) {
        view.value = value
        DispatchQueue.main.async { [weak view] in view?.updateResultsValue() }
    }

    final class TabAccessibilityView: UIView {
        var value = ""

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.updateResultsValue() }
        }

        func updateResultsValue() {
            guard let tab = findTab(in: window?.rootViewController),
                  let items = tab.tabBar.items, items.indices.contains(AppTab.results.rawValue) else { return }
            items[AppTab.results.rawValue].accessibilityValue = value
        }

        private func findTab(in controller: UIViewController?) -> UITabBarController? {
            if let tab = controller as? UITabBarController { return tab }
            for child in controller?.children ?? [] {
                if let tab = findTab(in: child) { return tab }
            }
            return nil
        }
    }
}
