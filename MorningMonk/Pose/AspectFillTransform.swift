import CoreGraphics

/// Maps normalized image coordinates onto a view that shows the image with
/// aspect-fill (as `AVCaptureVideoPreviewLayer` does with `.resizeAspectFill`).
struct AspectFillTransform {
    let imageSize: CGSize
    let viewSize: CGSize

    var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 0 }
        return max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    func viewPoint(fromNormalized p: CGPoint) -> CGPoint {
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offset = CGPoint(x: (viewSize.width - drawn.width) / 2, y: (viewSize.height - drawn.height) / 2)
        return CGPoint(x: offset.x + p.x * drawn.width, y: offset.y + p.y * drawn.height)
    }
}
