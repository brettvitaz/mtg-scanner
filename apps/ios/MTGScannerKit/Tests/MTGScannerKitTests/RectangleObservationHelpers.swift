import Vision

/// Creates a VNRectangleObservation with axis-aligned corners matching the bounding box.
///
/// VNRectangleObservation cannot be directly initialized; we use KVC to set properties.
/// Corner convention follows Vision's bottom-left origin.
func makeRectangleObservation(box: CGRect, confidence: Float) -> VNRectangleObservation {
    let obs = VNRectangleObservation()
    obs.setValue(box, forKey: "boundingBox")
    obs.setValue(confidence, forKey: "confidence")
    obs.setValue(CGPoint(x: box.minX, y: box.maxY), forKey: "topLeft")
    obs.setValue(CGPoint(x: box.maxX, y: box.maxY), forKey: "topRight")
    obs.setValue(CGPoint(x: box.maxX, y: box.minY), forKey: "bottomRight")
    obs.setValue(CGPoint(x: box.minX, y: box.minY), forKey: "bottomLeft")
    return obs
}
