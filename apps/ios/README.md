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

## CSV import for collections and decks

Open a collection or deck and choose **Import CSV** from its More options menu,
then select a CSV file. Empty collections and decks also have an **Import CSV**
button. Import supports CSV files exported by this app; it requires the configured
backend to resolve card printings and load their metadata.

Required headers are `title`, `edition`, `quantity`, and `foil`. Quantity must be a
positive whole number and foil must be `true` or `false`. Optional identity columns
are `set_code`, `collector_number`, and `scryfall_id`. Other export columns may be
present; metadata is populated from the chosen database printing. Headers may be
reordered, and additional columns are ignored. Files must use UTF-8 (an optional
BOM is supported). Quoted commas, escaped quotes, and multiline fields are supported.

`collector_number` may be absent or blank when title and edition identify exactly
one printing. The selected printing supplies the collector number. Numbers remain
strings, including suffixes and values such as `CSP-78`. If a supplied number or ID
conflicts with the other identity fields, or several printings match, choose a
printing in review or explicitly skip the row. Invalid quantities or foil values
must be corrected in the source CSV or skipped. Failed database lookups can be retried.

Nothing is added until every row is resolved or skipped and you tap **Import**.
Matching printings and foil states gain quantity, including repeated CSV rows;
foil and nonfoil copies remain separate. Existing card metadata is preserved.
Re-importing the same file adds its quantities again. A failed save restores the
destination's pre-import cards, quantities, and modification timestamp.
