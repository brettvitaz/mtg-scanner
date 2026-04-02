import SwiftUI

/// Displays pending and failed recognition counts as overlay badges.
///
/// Used by both Quick Scan and standard (table/binder) scan modes to show
/// async recognition job status in the upper-right corner of the scan screen.
struct RecognitionBadgeView: View {
    @ObservedObject var recognitionQueue: RecognitionQueue

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if recognitionQueue.pendingCount > 0 {
                pendingBadge
            }
            if recognitionQueue.failedCount > 0 {
                failedBadge
            }
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
    }

    private var failedBadge: some View {
        Text("\(recognitionQueue.failedCount) failed")
            .font(.caption.bold())
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}
