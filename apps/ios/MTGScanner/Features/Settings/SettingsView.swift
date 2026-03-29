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
        // swiftlint:disable:next closure_body_length
        NavigationStack {
            // swiftlint:disable:next closure_body_length
            Form {
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

                Section("Recognition") {
                    Toggle("On-Device Crop", isOn: $appModel.onDeviceCropEnabled)

                    Text(
                        "When enabled, cards are detected and cropped on-device before upload."
                        + " When disabled, the full image is sent to the server."
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Current flow") {
                    Text("Photo Library picker → multipart upload → mocked recognition response.")
                }
            }
            .navigationTitle("Settings")
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
