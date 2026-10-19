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
        .onAppear { updateCameraVisibility() }
        .onChange(of: appModel.selectedTab) { _, _ in updateCameraVisibility() }
        .background(NativeTabPresentation(value: appModel.resultsBadgeAccessibilityValue))
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
            updateCameraVisibility()
            if phase == .active { Task { await appModel.retryRecognitionFeedback() } }
        }
        .environment(\.undoSelectedTab, appModel.selectedTab.rawValue)
    }
    private func updateCameraVisibility() {
        let captureSelected = appModel.selectedTab == .table || appModel.selectedTab == .station
        cameraSession.setCaptureVisible(captureSelected && scenePhase == .active)
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

/// Supplies consistent selected tab artwork and the Results accessibility value.
private struct NativeTabPresentation: UIViewRepresentable {
    let value: String

    func makeUIView(context: Context) -> TabPresentationView { TabPresentationView() }

    func updateUIView(_ view: TabPresentationView, context: Context) {
        view.value = value
        DispatchQueue.main.async { [weak view] in view?.updateTabItems() }
    }

    final class TabPresentationView: UIView {
        var value = ""

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.updateTabItems() }
        }

        func updateTabItems() {
            guard let tab = findTab(in: window?.rootViewController),
                  let items = tab.tabBar.items, items.indices.contains(AppTab.results.rawValue) else { return }
            items[AppTab.results.rawValue].accessibilityValue = value
            // Capture tabs impose a dark toolbar scheme that overrides SwiftUI's tint.
            // Supply the same selected artwork/title color for every native destination.
            for item in items {
                item.selectedImage = (item.selectedImage ?? item.image)?
                    .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
                let appearance = UITabBarAppearance(barAppearance: tab.tabBar.standardAppearance)
                for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                               appearance.compactInlineLayoutAppearance] {
                    layout.selected.iconColor = .systemBlue
                    layout.selected.titleTextAttributes[.foregroundColor] = UIColor.systemBlue
                }
                item.standardAppearance = appearance
                item.scrollEdgeAppearance = appearance
            }
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
