import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    private enum ConnectionStatus {
        case idle
        case testing
        case success
        case failure(String)

        var isTesting: Bool {
            if case .testing = self { return true }
            return false
        }
    }

    @State private var connectionStatus: ConnectionStatus = .idle

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                recognitionSection
                quickScanSection
            }
            .navigationTitle("Settings")
        }
    }

    private var apiSection: some View {
        Section("API") {
            TextField("Base URL", text: $appModel.apiBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .onChange(of: appModel.apiBaseURL) { _ in connectionStatus = .idle }

            Button("Reset to Default") {
                appModel.resetAPIBaseURL()
                connectionStatus = .idle
            }

            Button("Test Connection", action: testConnection)
                .disabled(connectionStatus.isTesting)

            connectionStatusLabel

            Text(
                "The API address is saved between launches. "
                + "Use your Mac's LAN or tailnet IP instead of "
                + "127.0.0.1 when the app runs on a physical iPhone."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var recognitionSection: some View {
        Section("Recognition") {
            Toggle("On-Device Crop", isOn: $appModel.onDeviceCropEnabled)

            Text(
                "When enabled, cards are detected and cropped on-device before upload."
                + " When disabled, the full image is sent to the server."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var quickScanSection: some View {
        Section("Quick Scan") {
            Toggle("Enable Quick Scan Mode", isOn: $appModel.quickScanEnabled)
            if appModel.quickScanEnabled {
                quickScanCaptureDelayRow
                quickScanConfidenceRow
            }
            Text(
                "When enabled, Quick Scan mode appears in the Scan tab. "
                + "Place your phone above a scanning station and drop cards in — "
                + "each card is automatically captured and recognized."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var quickScanCaptureDelayRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Capture Delay")
                Spacer()
                Text(String(format: "%.1f s", appModel.quickScanCaptureDelay))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $appModel.quickScanCaptureDelay, in: 0.5...5.0, step: 0.5)
        }
    }

    private var quickScanConfidenceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Detection Confidence")
                Spacer()
                Text(String(format: "%.1f", appModel.quickScanConfidenceThreshold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $appModel.quickScanConfidenceThreshold, in: 0.3...0.9, step: 0.1)
        }
    }

    @ViewBuilder
    private var connectionStatusLabel: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .testing:
            Text("Testing…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .success:
            Text("Connected")
                .font(.footnote)
                .foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func testConnection() {
        connectionStatus = .testing
        let baseURL = appModel.apiBaseURL
        Task {
            do {
                try await APIClient().checkHealth(baseURL: baseURL)
                connectionStatus = .success
            } catch {
                connectionStatus = .failure(error.localizedDescription)
            }
        }
    }
}
