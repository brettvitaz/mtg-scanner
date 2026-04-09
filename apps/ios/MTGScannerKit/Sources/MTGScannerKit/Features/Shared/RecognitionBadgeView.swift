import SwiftUI

/// Displays pending and failed recognition counts as overlay badges.
///
/// Used by both Auto Scan and standard scan modes to show
/// async recognition job status in the upper-right corner of the scan screen.
struct RecognitionBadgeView: View {
    @Bindable var recognitionQueue: RecognitionQueue
    var onCancel: (() -> Void)?
    var onRetryFailed: (() -> Void)?
    var onClearFailed: (() -> Void)?
    @State private var showingFailedAlert = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if recognitionQueue.pendingCount > 0 {
                HStack(spacing: 6) {
                    pendingBadge
                    if let onCancel {
                        cancelButton(action: onCancel)
                    }
                }
            }
            if recognitionQueue.failedCount > 0 {
                failedBadge
            }
        }
        .alert("Recognition Failures", isPresented: $showingFailedAlert) {
            Button("Retry") { onRetryFailed?() }
            Button("Dismiss", role: .destructive) { onClearFailed?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(recognitionQueue.failedCount) card(s) could not be recognized. Retry or dismiss them.")
        }
    }

    private var pendingBadge: some View {
        HStack(spacing: 6) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.75)
            Text("\(recognitionQueue.pendingCount) recognizing")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recognition in progress")
        .accessibilityValue("\(recognitionQueue.pendingCount) pending")
    }

    private func cancelButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.8))
        }
        .accessibilityLabel("Cancel recognition")
        .accessibilityHint("Cancels pending card recognition requests.")
    }

    private var failedBadge: some View {
        Button {
            showingFailedAlert = true
        } label: {
            Text("\(recognitionQueue.failedCount) failed")
                .font(.caption.bold())
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .accessibilityLabel("Recognition failures")
        .accessibilityValue("\(recognitionQueue.failedCount) failed")
        .accessibilityHint("Tap to retry or dismiss failed cards.")
    }
}
