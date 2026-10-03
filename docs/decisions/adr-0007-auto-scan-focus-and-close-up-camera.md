# ADR 0007: Automatic fixed close-up lens and continuous focus for Auto Scan

## Status

Accepted. User testing confirmed that Close-up produces sharper growing-stack images;
throughput and full stack-height acceptance still require physical stand verification.

## Context

A mounted phone scans cards fed into a cavity. As the stack rises, the card plane moves
closer to the camera. Supplied iPhone 17 Pro image pairs show a sharper lower card and a
softer upper card using the main lens. Subsequent user testing confirmed that Close-up
improves sharpness. A camera setting adds work to this flow, and waiting for another
one-shot focus/exposure pass at the shutter slows scanning without overcoming lens limits.

## Decision

- Auto Scan selects the autofocus-capable physical ultra-wide camera when it supports
  the existing 1080p video/photo pipeline; otherwise it uses the physical wide camera.
  Keep that lens fixed for the session. Normal Scan uses the standard camera. No camera
  setting or model-specific branch is exposed, and the former camera preference is ignored.
- Target detected cards in native top-left YOLO coordinates. Ignore target jitter within
  0.02 normalized units to avoid restarting focus unnecessarily.
- Keep focus and exposure continuous. Observe focus adjustments and track idle periods on
  camera frames while the existing card-settling delay runs. Do not restart one-shot focus
  or exposure when the shutter is requested.
- Reuse prepared focus immediately when ready (100 ms since target change, 50 ms idle).
  If focus adjustment is ongoing, wait at most 0.5 seconds after the capture request, then
  capture with continuous autofocus active. Exposure adjustment does not block capture.
  Adjustment flags do not prove optical sharpness.
- Replace the controller on scan-mode changes, cancelling old capture, disconnecting old
  frames, and resetting zoom/calibration. Reapply exposure and supported torch controls.

## Consequences

Auto Scan handles the stand without asking users to select a lens, and focus work overlaps
the existing settling delay. Resolution, photo quality prioritization, recognition contracts,
and cropping stay unchanged. Selected lens and minimum focus distance are logged for
hardware diagnosis. Phones without a close-up lens may need a lower stack limit.

Validate low, middle, and maximum stacks and continuous feeding on the physical stand.
Check crop completeness, ultra-wide framing, illumination, and elapsed scan time.

## Follow-up: continuous adjustment must not block scanning

Physical testing repeatedly reached the focus timeout. The original gate included exposure
adjustment and cancelled capture when either adjustment persisted. Exposure is independent
of focus, and this strict gate prevented scanning. The bounded wait is now advisory: it
captures at its deadline rather than requiring manual retry. Autofocus remains continuous,
and deadline fallback is logged. This trades guaranteed idle status for forward progress;
physical image sharpness still needs validation.

## Physical acceptance check

Capture success alone cannot verify focus settling: the deadline path intentionally
returns a normal photo. Persistent `CameraFocus` logs distinguish `Focus settled`
from `Focus deadline fallback` for each capture, including extra wait, age of the
configured target, target point, physical lens, lens position, focus mode, and separate
focus/exposure adjustment flags. Configuration lock errors are logged and surfaced as
capture failures. Missing prepared state is a failure, never a deadline fallback;
failed initial configuration can be retried at the same point.

1. Connect the physical iPhone to macOS Console, select the device, start streaming,
   and filter by subsystem `com.mtgscanner` and category `CameraFocus`.
2. With the usual stand and lighting, scan ten cards each at low, middle, and maximum
   usable stack heights. Repeat with continuous feeding and manual stationary captures.
   In a Debug build, enable Settings → Save Raw Captures to Photos to preserve full
   camera images. Keep card order and save the logs with the resulting images to
   compare each batch.
3. Count settled captures, deadline fallbacks, and configuration failures separately.
   Report fallback rate and wait durations per height. A batch dominated by fallbacks
   does not demonstrate reliable settling, even if recognition succeeds.
4. Inspect the full photo and crop at native resolution: readable title, collector
   number and small print, complete card edges, motion blur, glare, and crop completeness.
   Record recognition accuracy and elapsed scan time alongside image usability.
5. Check that exposure-only adjustment does not extend the focus wait, and that a
   stopped/restarted session and centered targets continue to capture successfully.

Simulator tests cover settling decisions, configuration failure/retry, and failure
propagation to Auto Scan without uploading an image. They cannot establish lens focus
or physical sharpness. A settled log reports an idle autofocus window before requesting
the photo, not measured optical sharpness at exposure time. Judge usable scans by the
saved images; perfect images are not an acceptance requirement. If fallbacks remain
frequent, use their focus/exposure flags and stack heights to diagnose the remaining
problem rather than treating improved recognition as proof of settling.

Apple documents separate [focus adjustment](https://developer.apple.com/documentation/avfoundation/avcapturedevice/isadjustingfocus)
and [exposure adjustment](https://developer.apple.com/documentation/avfoundation/avcapturedevice/isadjustingexposure)
flags. Neither is an image sharpness measurement.
