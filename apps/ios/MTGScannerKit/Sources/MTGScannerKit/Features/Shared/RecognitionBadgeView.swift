import SwiftUI

/// Aggregate queue activity, anchored to the latest capture rather than an individual job.
struct RecognitionBadgeView: View {
    @Bindable var recognitionQueue: RecognitionQueue
    var image: UIImage?
    var showsThumbnail = true
    var onCancel: (() -> Void)?
    var onRetryFailed: (() -> Void)?
    var onClearFailed: (() -> Void)?
    @State private var showingActions = false

    private var hasWork: Bool { recognitionQueue.pendingCount > 0 || recognitionQueue.failedCount > 0 }
    private var summary: String {
        "\(recognitionQueue.pendingCount) pending, \(recognitionQueue.failedCount) failed"
    }

    var body: some View {
        Group {
            if hasWork {
                Button { showingActions = true } label: {
                    VStack(spacing: 4) {
                        if showsThumbnail { thumbnail }
                        status
                    }
                    .frame(minWidth: 44, minHeight: showsThumbnail ? 76 : 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recognition queue")
                .accessibilityValue(summary)
                .accessibilityHint("Opens recognition actions for all pending and failed requests.")
                .accessibilityIdentifier("capture-recognition-queue")
            } else if showsThumbnail {
                thumbnail.padding(.bottom, 24)
            }
        }
        .confirmationDialog("Recognition", isPresented: $showingActions, titleVisibility: .visible) {
            if recognitionQueue.pendingCount > 0, let onCancel {
                Button("Cancel pending recognition", role: .destructive, action: onCancel)
            }
            if recognitionQueue.failedCount > 0 {
                Button("Retry failed") { onRetryFailed?() }
                Button("Dismiss failures", role: .destructive) { onClearFailed?() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(summary)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(width: 36, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel("Last captured card")
        } else if hasWork {
            Image(systemName: "photo.on.rectangle")
                .frame(width: 36, height: 48)
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: 36, height: 48).accessibilityHidden(true)
        }
    }

    private var status: some View {
        HStack(spacing: 4) {
            if recognitionQueue.failedCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
            } else if recognitionQueue.pendingCount > 0 {
                ProgressView().tint(.white).controlSize(.mini)
            }
            Text(statusText)
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.black.opacity(0.65), in: Capsule())
        .captureControlSurface(in: Capsule())
    }

    private var statusText: String {
        guard showsThumbnail else { return summary }
        if recognitionQueue.pendingCount > 0 { return "\(recognitionQueue.pendingCount) pending" }
        return "\(recognitionQueue.failedCount) failed"
    }
}
