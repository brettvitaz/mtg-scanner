import SwiftUI

public struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var connectionStatus: ConnectionStatus = .idle

    public init() {}

    public var body: some View {
        @Bindable var appModel = appModel
        NavigationStack {
            SettingsForm(
                appModel: appModel,
                connectionStatus: $connectionStatus
            )
            .navigationTitle("Settings")
        }
    }
}

// MARK: - ConnectionStatus

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

// MARK: - Settings Form

private struct SettingsForm: View {
    @Bindable var appModel: AppModel
    @Binding var connectionStatus: ConnectionStatus

    var body: some View {
        Form {
            apiSection
            recognitionSection
            autoScanSection
            motionBurstSection
        }
    }

    // MARK: - API Section

    @ViewBuilder
    private var apiSection: some View {
        Section("API") {
            TextField("Base URL", text: $appModel.apiBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .onChange(of: appModel.apiBaseURL) { _, _ in connectionStatus = .idle }

            Button("Reset to Default") {
                appModel.resetAPIBaseURL()
                connectionStatus = .idle
            }

            Button("Test Connection") { testConnection() }
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

    // MARK: - Recognition Section

    @ViewBuilder
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

    // MARK: - Auto Scan Section

    @ViewBuilder
    private var autoScanSection: some View {
        Section("Auto Scan") {
            captureDelayRow
            confidenceRow
            concurrentUploadsRow
            exposureBiasRow
        }
    }

    // MARK: - Motion Burst Section

    @ViewBuilder
    private var motionBurstSection: some View {
        MotionBurstSectionView(appModel: appModel)
    }

    private var exposureBiasRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Exposure Bias")
                Spacer()
                Text(String(format: "%+.1f EV", appModel.exposureBias))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $appModel.exposureBias, in: -3.0...3.0, step: 0.5)
                .accessibilityLabel("Exposure bias")
                .accessibilityValue(String(format: "%+.1f EV", appModel.exposureBias))
        }
    }

    private var captureDelayRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Capture Delay")
                Spacer()
                Text(String(format: "%.1f s", appModel.autoScanCaptureDelay)).foregroundStyle(.secondary)
            }
            Slider(value: $appModel.autoScanCaptureDelay, in: 0.5...5.0, step: 0.5)
                .accessibilityLabel("Capture delay")
                .accessibilityValue(String(format: "%.1f seconds", appModel.autoScanCaptureDelay))
        }
    }

    private var confidenceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Detection Confidence")
                Spacer()
                Text(String(format: "%.1f", appModel.autoScanConfidenceThreshold)).foregroundStyle(.secondary)
            }
            Slider(value: $appModel.autoScanConfidenceThreshold, in: 0.3...0.9, step: 0.1)
                .accessibilityLabel("Detection confidence")
                .accessibilityValue(String(format: "%.1f", appModel.autoScanConfidenceThreshold))
        }
    }

    private var concurrentUploadsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Concurrent Uploads")
                Spacer()
                Text("\(appModel.maxConcurrentUploads)").foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(appModel.maxConcurrentUploads) },
                    set: { appModel.maxConcurrentUploads = Int($0.rounded()) }
                ),
                in: 1...6,
                step: 1
            )
            .accessibilityLabel("Concurrent uploads")
            .accessibilityValue("\(appModel.maxConcurrentUploads)")
        }
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionStatusLabel: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .testing:
            Text("Testing…").font(.footnote).foregroundStyle(.secondary)
        case .success:
            Text("Connected").font(.footnote).foregroundStyle(.green)
        case .failure(let message):
            Text(message).font(.footnote).foregroundStyle(.red)
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

// MARK: - Motion Burst Section

private struct MotionBurstSectionView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        Section("Motion Detection") {
            presetPicker
            if appModel.motionBurstPreset == .custom {
                motionThresholdRow
                minPeakThresholdRow
            }
            Button("Reset to Defaults") { appModel.resetMotionBurstSettings() }
            Text(
                "Detection sensitivity for card drops. "
                + "Lower motion threshold = more sensitive. "
                + "Higher peak threshold = fewer false triggers from shadows."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var presetPicker: some View {
        Picker("Preset", selection: $appModel.motionBurstPreset) {
            ForEach(MotionBurstPreset.allCases, id: \.self) { preset in
                Text(preset.displayName).tag(preset)
            }
        }
    }

    private var motionThresholdRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Motion Threshold")
                Spacer()
                Text(String(format: "%.3f", appModel.motionBurstMotionThreshold)).foregroundStyle(.secondary)
            }
            Slider(value: $appModel.motionBurstMotionThreshold, in: 0.005...0.050, step: 0.005)
                .accessibilityLabel("Motion threshold")
        }
    }

    private var minPeakThresholdRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Peak Threshold")
                Spacer()
                Text(String(format: "%.3f", appModel.motionBurstMinPeakThreshold)).foregroundStyle(.secondary)
            }
            Slider(value: $appModel.motionBurstMinPeakThreshold, in: 0.020...0.100, step: 0.005)
                .accessibilityLabel("Peak threshold")
        }
    }
}
