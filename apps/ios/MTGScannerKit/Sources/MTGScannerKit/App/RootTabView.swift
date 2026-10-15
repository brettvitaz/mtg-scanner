import SwiftUI
import UIKit

public struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var appModel
    @State private var scanMode: DetectionMode = .scan
    @State private var showsScanModePicker = false

    public init() {}

    public var body: some View {
        @Bindable var appModel = appModel
        TabView(selection: Binding(get: { appModel.selectedTab }, set: appModel.selectTab)) {
            ScanView(detectionMode: $scanMode, isActive: appModel.selectedTab == .scan)
                .tabItem {
                    Label(scanMode.displayName, systemImage: scanMode.systemImage)
                }
                .tag(AppTab.scan)

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
        .background(
            TabBarObserver(
                tabIndex: AppTab.scan.rawValue, resultsAccessibilityValue: appModel.resultsBadgeAccessibilityValue
            ) {
                showsScanModePicker = true
            }
        )
        .sheet(isPresented: $showsScanModePicker) {
            ScanModePickerSheet(selectedMode: $scanMode)
        }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await appModel.retryRecognitionFeedback() } }
        }
        .environment(\.undoSelectedTab, appModel.selectedTab.rawValue)
    }
}

private struct ScanModePickerSheet: View {
    @Binding var selectedMode: DetectionMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Scan Mode")
                .font(.headline)

            HStack(spacing: 16) {
                modeButton(.scan)
                modeButton(.auto)
            }
        }
        .padding(24)
        .presentationDetents([.height(220)])
    }

    private func modeButton(_ mode: DetectionMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            selectedMode = mode
            dismiss()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 30, weight: .semibold))
                Text(mode.displayName)
                    .font(.headline)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityLabel("\(mode.displayName) mode")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Selects this scan mode.")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct TabBarObserver: UIViewRepresentable {
    let tabIndex: Int
    let resultsAccessibilityValue: String
    let onTap: () -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.tabIndex = tabIndex
        view.resultsAccessibilityValue = resultsAccessibilityValue
        view.onTap = onTap
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.tabIndex = tabIndex
        view.resultsAccessibilityValue = resultsAccessibilityValue
        view.onTap = onTap
        DispatchQueue.main.async {
            view.installTapRecognizerIfPossible()
        }
    }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var tabIndex = AppTab.scan.rawValue
        var resultsAccessibilityValue = ""
        var onTap: () -> Void = {}
        private weak var observedTabBar: UITabBar?
        private lazy var tapRecognizer: ScanTabTapGestureRecognizer = {
            let recognizer = ScanTabTapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async {
                self.installTapRecognizerIfPossible()
            }
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow == nil {
                observedTabBar?.removeGestureRecognizer(tapRecognizer)
                observedTabBar = nil
            }
            super.willMove(toWindow: newWindow)
        }

        func installTapRecognizerIfPossible() {
            tapRecognizer.tabIndex = tabIndex
            guard let tabBar = findTabBarController(from: window?.rootViewController)?.tabBar else { return }
            // SwiftUI's tabItem label does not forward accessibilityValue to UITabBarItem.
            if let items = tabBar.items, items.indices.contains(AppTab.results.rawValue) {
                items[AppTab.results.rawValue].accessibilityValue = resultsAccessibilityValue
            }
            guard observedTabBar !== tabBar else { return }

            observedTabBar?.removeGestureRecognizer(tapRecognizer)
            observedTabBar = tabBar
            tabBar.addGestureRecognizer(tapRecognizer)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handleTap(_ recognizer: ScanTabTapGestureRecognizer) {
            if recognizer.state == .ended, recognizer.touchStartedOnSelectedTab {
                onTap()
            }
        }

        private func findTabBarController(from controller: UIViewController?) -> UITabBarController? {
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }

            for child in controller?.children ?? [] {
                if let tabBarController = findTabBarController(from: child) {
                    return tabBarController
                }
            }

            if let presented = controller?.presentedViewController {
                return findTabBarController(from: presented)
            }

            return nil
        }
    }

    private final class ScanTabTapGestureRecognizer: UITapGestureRecognizer {
        var tabIndex = AppTab.scan.rawValue
        private(set) var touchStartedOnSelectedTab = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            defer { super.touchesBegan(touches, with: event) }
            touchStartedOnSelectedTab = false

            guard let tabBar = view as? UITabBar,
                  let touch = touches.first,
                  let items = tabBar.items,
                  !items.isEmpty,
                  items.indices.contains(tabIndex) else {
                return
            }

            let location = touch.location(in: tabBar)
            let itemWidth = tabBar.bounds.width / CGFloat(items.count)
            let tappedIndex = min(max(Int(location.x / itemWidth), 0), items.count - 1)
            touchStartedOnSelectedTab = tappedIndex == tabIndex && tabBar.selectedItem === items[tabIndex]
        }

        override func reset() {
            super.reset()
            touchStartedOnSelectedTab = false
        }
    }
}
