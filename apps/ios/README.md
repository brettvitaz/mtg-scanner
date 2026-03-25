# iOS App

SwiftUI iPhone client for the MTG scanner MVP.

## What is implemented
- Real Xcode project at `apps/ios/MTGScanner.xcodeproj`
- SwiftUI tab app with Scan / Results / Settings screens
- Camera capture plus Photo Library picker on the scan screen
- Multipart upload to `POST /api/v1/recognitions`
- Mocked recognition results rendered in the Results tab

## Run it
1. Start the backend from the repo root:
   ```bash
   make api-bootstrap
   make api-run
   ```
2. Open the app project:
   ```bash
   open apps/ios/MTGScanner.xcodeproj
   ```
3. Run the `MTGScanner` scheme in the simulator or on a device.

## Local networking note
- `127.0.0.1` works in the iOS simulator.
- On a physical iPhone, update the API base URL in Settings to your Mac's LAN IP, for example `http://192.168.1.10:8000`.

## Caveats
- The backend still returns mocked/example recognition data.
- Camera capture requires a device or simulator configuration that exposes a camera source. The app falls back to Photo Library when camera capture is unavailable.
