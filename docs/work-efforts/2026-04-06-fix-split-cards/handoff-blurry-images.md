# Handoff: Blurry Images from iOS Camera

## Problem

Images captured from the iOS app are blurry. The camera pipeline captures at full sensor resolution (12MP+) with 0.9 JPEG quality and no resizing, so the issue is not compression or downscaling.

## Root Cause

The camera is never configured with autofocus settings. `CameraSessionManager.configureOnSessionQueue()` creates the device and adds it to the session but never sets a focus mode, focus point, or range restriction. Photos are captured immediately without waiting for focus stability.

There is zero focus-related code anywhere in the iOS app — confirmed via grep for `focus`, `autoFocus`, `focusMode`, `lensPosition` across `apps/ios/`.

## Key File

`apps/ios/MTGScannerKit/Sources/MTGScannerKit/Features/CardDetection/Camera/CameraSessionManager.swift`

### Current state of `configureOnSessionQueue()` (line 37-66):

- Sets session preset to `.hd1920x1080` (for video detection performance — must stay)
- Adds back wide-angle camera as input
- Configures video data output (BGRA, discards late frames)
- Configures photo output with `maxPhotoDimensions` set to device maximum
- **Never touches focus configuration on the device**

### Current state of `capturePhoto()` (line 72-82):

- Creates default `AVCapturePhotoSettings`
- Sets `maxPhotoDimensions` if available
- Dispatches capture immediately on session queue
- **No focus lock or stability wait before capture**

## Proposed Fix

### 1. Configure autofocus during session setup

Add a `configureFocus(_ device:)` method called from `configureOnSessionQueue()` after `captureDevice = device` (line 49):

```swift
private func configureFocus(_ device: AVCaptureDevice) {
    guard (try? device.lockForConfiguration()) != nil else { return }
    if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
    }
    if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
    }
    if device.isAutoFocusRangeRestrictionSupported {
        device.autoFocusRangeRestriction = .near
    }
    device.unlockForConfiguration()
}
```

- `.continuousAutoFocus` keeps focus tracking as user moves camera
- `.near` range restriction biases toward close-up subjects (cards on a table)
- Center focus point is appropriate for card scanning
- All settings guarded with capability checks

### 2. Lock focus before photo capture

Modify `capturePhoto()` to trigger a single autofocus pass and wait for it to settle before capturing:

```swift
func capturePhoto(completion: @escaping (Data?) -> Void) {
    photoCaptureCompletion = completion
    sessionQueue.async { [weak self] in
        guard let self else { return }
        self.lockFocusThenCapture()
    }
}

private func lockFocusThenCapture() {
    guard let device = captureDevice,
          device.isFocusModeSupported(.autoFocus) else {
        captureWithCurrentSettings()
        return
    }
    do {
        try device.lockForConfiguration()
        device.focusMode = .autoFocus  // single pass, locks when done
        device.unlockForConfiguration()
    } catch {
        captureWithCurrentSettings()
        return
    }
    sessionQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        self?.captureWithCurrentSettings()
        self?.restoreContinuousAutoFocus()
    }
}

private func captureWithCurrentSettings() {
    let settings = AVCapturePhotoSettings()
    if maxPhotoDimensions.width > 0 {
        settings.maxPhotoDimensions = maxPhotoDimensions
    }
    photoOutput.capturePhoto(with: settings, delegate: self)
}

private func restoreContinuousAutoFocus() {
    guard let device = captureDevice,
          (try? device.lockForConfiguration()) != nil else { return }
    if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
    }
    device.unlockForConfiguration()
}
```

- `.autoFocus` triggers a single focus pass and locks when complete
- 0.3s delay gives time for focus to settle (can be tuned)
- After capture, restore `.continuousAutoFocus` so preview stays responsive
- Each method is under 15 lines

## Constraints

- Session preset must stay `.hd1920x1080` (required for real-time Vision detection performance)
- Swift 6.0, minimum iOS 18.0
- All camera work must stay on `sessionQueue` (dedicated serial DispatchQueue)
- No force unwraps in production code
- `[weak self]` in closures on long-lived objects
- `CameraSessionManager` is `@unchecked Sendable` — do not change this

## Testing

- `make ios-build` — verify app compiles
- `make ios-test` — verify existing tests pass
- Manual on-device testing: capture cards at various distances, inspect artifacts for sharpness
- No new unit tests needed (hardware interaction, no testable pure logic added)

## Image Pipeline Summary (for context)

1. Camera captures at full sensor resolution via `AVCapturePhotoOutput`
2. `photo.fileDataRepresentation()` returns full-res JPEG/HEIF
3. `UIImage(data:)` creates image — no resize
4. Orientation normalized via `UIGraphicsImageRenderer` at original scale
5. Cropped via `CIPerspectiveCorrection` (Path A) or `CGImage.cropping` (Path B) — no resize
6. JPEG encoded at `compressionQuality: 0.9` — no resize
7. Uploaded as-is to backend
