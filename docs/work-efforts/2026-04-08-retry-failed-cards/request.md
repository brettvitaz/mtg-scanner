# Request: Retry Failed Cards

**Date:** 2026-04-08
**Author:** Brett Vitaz

## Goal

When a communication error with the API occurs during card scanning, any cards queued for recognition are permanently lost. Users need the ability to retry failed scans once the issue is resolved, or explicitly dismiss them.

## Requirements

1. Failed scans must be preserved (not discarded) so they can be re-submitted.
2. The user must be able to retry all failed scans at once.
3. The user must be able to dismiss (discard) all failed scans at once.
4. The failure indicator must be interactive — tapping it presents the retry/dismiss options.
5. Retried jobs must get their automatic one-attempt retry, same as a freshly queued job.

## Scope

**In scope:**
- Storing failed jobs in memory so they survive until the user acts on them.
- Bulk retry and bulk dismiss via a tap-to-alert interaction on the existing failed badge.
- Both scan modes (standard and Auto Scan) must support the feature.

**Out of scope:**
- Per-card retry (only bulk retry/dismiss).
- Persistent storage of failed jobs across app launches.
- Exponential backoff or smarter retry scheduling.
- Surfacing the specific error reason to the user.

## Verification

```bash
make ios-test   # all existing and new tests pass
make ios-lint   # zero violations
```

Manual: scan a card while the API is unreachable → red "N failed" badge appears → tap badge → alert shows Retry / Dismiss / Cancel → Retry re-submits jobs, Dismiss clears the badge.

## Context

Files the agent should read before starting:

- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/RecognitionQueue.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Shared/RecognitionBadgeView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/AutoScan/AutoScanView.swift`
- `apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/Scan/ScanView.swift`
- `apps/ios/MTGScannerKit/Tests/MTGScannerKitTests/RecognitionQueueTests.swift`
