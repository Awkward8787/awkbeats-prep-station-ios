import UIKit

/// Center-crops cover art to a square and saves it as a 1500 px JPEG (the size most stores ask for).
enum ArtworkProcessor {
    static let side: CGFloat = 1500

    static func normalized(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return normalized(image)
    }

    static func normalized(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let crop = min(size.width, size.height)
        let target = min(side, crop * image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let out = renderer.image { _ in
            let scale = target / crop
            let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
            let origin = CGPoint(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return out.jpegData(compressionQuality: 0.88)
    }
}
