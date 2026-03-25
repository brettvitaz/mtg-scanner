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

                    Text("Use your Mac's LAN IP instead of 127.0.0.1 when the app runs on a physical iPhone.")
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
