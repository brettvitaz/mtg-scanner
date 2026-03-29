import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    TextField("Base URL", text: $appModel.apiBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)

                    Button("Reset to Default") {
                        appModel.resetAPIBaseURL()
                    }

                    Text("The API address is saved between launches. Use your Mac's LAN or tailnet IP instead of 127.0.0.1 when the app runs on a physical iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Recognition") {
                    Toggle("On-Device Crop", isOn: $appModel.onDeviceCropEnabled)

                    Text("When enabled, cards are detected and cropped on-device before upload. When disabled, the full image is sent to the server.")
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
}
