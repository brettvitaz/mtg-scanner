import AVFoundation
import UIKit

/// A `UIViewController` that simulates the camera preview in preview/simulator builds.
///
/// Layer hierarchy:
/// ```
/// view
///   ├─ imageView  (UIImageView — cycles through fixture card images)
///   └─ overlayView (UIView — hosts CAShapeLayer overlays from detection)
/// ```
///
/// Uses ``FixtureFrameSource`` to feed pixel buffers to ``CardDetectionEngine``,
/// running the real detection pipeline without AVFoundation hardware.
///
/// Coordinate mapping: Vision returns normalized corners in native image space
/// (origin bottom-left). We apply a Y-flip then scale to the imageView's aspect-fit
/// rect to match how the overlay appears over the displayed image.
final class FixtureCameraViewController: UIViewController {

    // MARK: - Public

    var onDetectedCardsChanged: (([DetectedCard]) -> Void)?

    // MARK: - Private

    private let frameSource: FixtureFrameSource
    private let engine = CardDetectionEngine()
    private let imageView = UIImageView()
    private let overlayView = UIView()
    private var layerPool: [CAShapeLayer] = []
    private var currentImageSize: CGSize = .zero
    private var currentImages: [UIImage] = []
    private var imageIndex = 0

    private let frameQueue = DispatchQueue(
        label: "com.mtgscanner.fixture-camera-vc",
        qos: .userInitiated
    )

    // MARK: - Init

    init(frameSource: FixtureFrameSource = FixtureFrameSource()) {
        self.frameSource = frameSource
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupImageView()
        setupOverlayView()
        loadFixtureImages()
        wireDetectionEngine()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        frameSource.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        frameSource.stop()
        clearOverlays()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        imageView.frame = view.bounds
        overlayView.frame = view.bounds
        overlayView.layer.sublayers?.forEach { $0.frame = overlayView.bounds }
    }

    // MARK: - Setup

    private func setupImageView() {
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)
    }

    private func setupOverlayView() {
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        overlayView.frame = view.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlayView)
    }

    private func loadFixtureImages() {
        currentImages = FixtureFrameSource.fixtureNames.compactMap { name in
            guard let url = Bundle.module.url(forResource: name, withExtension: nil)
                    ?? Self.findBundleURL(name: name) else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
        if let first = currentImages.first {
            imageView.image = first
            currentImageSize = first.size
        }
    }

    private static func findBundleURL(name: String) -> URL? {
        for ext in ["jpg", "jpeg", "png"] {
            if let url = Bundle.module.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private func wireDetectionEngine() {
        engine.updateDetectionMode(.scan)

        frameSource.onPixelBuffer = { [weak self] pixelBuffer, _ in
            guard let sampleBuffer = Self.makeSampleBuffer(from: pixelBuffer) else { return }
            self?.engine.processFrame(sampleBuffer)
        }

        engine.onDetection = { [weak self] cards in
            guard let self else { return }
            self.onDetectedCardsChanged?(cards)
            // Advance to the next fixture image on each detection cycle.
            let nextImage = self.currentImages.isEmpty ? nil
                : self.currentImages[self.imageIndex % self.currentImages.count]
            self.imageIndex &+= 1
            Task { @MainActor in
                if let img = nextImage {
                    self.imageView.image = img
                    self.currentImageSize = img.size
                }
                self.updateOverlays(cards)
            }
        }
    }

    // MARK: - Overlay rendering

    /// Maps Vision normalized coordinates (origin bottom-left, landscape image space)
    /// to points in the `overlayView` using the imageView's aspect-fit content rect.
    private func updateOverlays(_ cards: [DetectedCard]) {
        growPoolIfNeeded(to: cards.count)

        let imageBounds = imageRect(for: currentImageSize, in: overlayView.bounds)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (i, card) in cards.enumerated() {
            let path = quadPath(for: card, in: imageBounds)
            layerPool[i].path = path.cgPath
            layerPool[i].isHidden = false
        }
        for i in cards.count..<layerPool.count {
            layerPool[i].isHidden = true
        }
    }

    private func clearOverlays() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layerPool.forEach { $0.isHidden = true }
        CATransaction.commit()
    }

    private func growPoolIfNeeded(to count: Int) {
        while layerPool.count < count {
            let layer = makeOverlayLayer()
            overlayView.layer.addSublayer(layer)
            layerPool.append(layer)
        }
    }

    private func makeOverlayLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.systemGreen.cgColor
        layer.fillColor = UIColor.systemGreen.withAlphaComponent(0.15).cgColor
        layer.lineWidth = 2.0
        layer.isHidden = true
        layer.actions = ["path": NSNull(), "hidden": NSNull()]
        return layer
    }

    /// Vision corner (normalized, origin bottom-left, in the 1920×1080 landscape buffer)
    /// → point in the aspect-fit image rect on screen.
    private func visionPoint(_ pt: CGPoint, in imageBounds: CGRect) -> CGPoint {
        CGPoint(
            x: imageBounds.minX + pt.x * imageBounds.width,
            y: imageBounds.minY + (1.0 - pt.y) * imageBounds.height
        )
    }

    private func quadPath(for card: DetectedCard, in imageBounds: CGRect) -> UIBezierPath {
        let tl = visionPoint(card.topLeft, in: imageBounds)
        let tr = visionPoint(card.topRight, in: imageBounds)
        let br = visionPoint(card.bottomRight, in: imageBounds)
        let bl = visionPoint(card.bottomLeft, in: imageBounds)
        let path = UIBezierPath()
        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: br)
        path.addLine(to: bl)
        path.close()
        return path
    }

    /// Returns the rectangle that `scaleAspectFit` draws into inside `bounds`.
    private func imageRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(
            x: bounds.midX - w / 2,
            y: bounds.midY - h / 2,
            width: w,
            height: h
        )
    }

    // MARK: - CMSampleBuffer factory

    nonisolated static func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer?
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 5),
            presentationTimeStamp: CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}
