import SwiftUI
import UIKit

struct ZoomableScanImage: UIViewRepresentable {
    let image: UIImage
    var initialZoom: CGFloat = 1

    func makeUIView(context: Context) -> ScanImageScrollView {
        ScanImageScrollView(image: image, initialZoom: initialZoom)
    }

    func updateUIView(_ uiView: ScanImageScrollView, context: Context) {}
}

final class ScanImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private let initialZoom: CGFloat
    private var previousSize = CGSize.zero

    init(image: UIImage, initialZoom: CGFloat) {
        imageView = UIImageView(image: image)
        self.initialZoom = initialZoom
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 8
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Captured card scan. Pinch to zoom and drag to pan."
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousSize, bounds.width > 0, bounds.height > 0,
              let image = imageView.image else { return }
        previousSize = bounds.size
        zoomScale = 1
        let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
        imageView.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * ratio,
                                                            height: image.size.height * ratio))
        contentSize = imageView.frame.size
        zoomScale = min(max(initialZoom, minimumZoomScale), maximumZoomScale)
        centerImage()
        if initialZoom > 1 {
            contentOffset = CGPoint(x: 0,
                                    y: max(0, contentSize.height - bounds.height))
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    private func centerImage() {
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: 0,
                                    bottom: 0, right: 0)
        imageView.center.x = max(bounds.width, contentSize.width) / 2
    }
}
