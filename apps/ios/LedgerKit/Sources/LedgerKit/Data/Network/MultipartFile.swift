import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MultipartFile: Sendable {
    var field: String
    var filename: String
    var mimeType: String
    var data: Data

    func multipartBody(boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }
}

extension MultipartFile {
    /// The camera hands back HEIC and the photo library hands back whatever the user saved, neither of
    /// which `POST /scan/photo` accepts. Re-encoding also keeps the upload well under the server's 10 MB
    /// cap and near the resolution the model actually reads.
    static func scanPhoto(from data: Data, maxPixelSize: Int = 1568, quality: Double = 0.8) -> MultipartFile? {
        guard let jpeg = jpegData(from: data, maxPixelSize: maxPixelSize, quality: quality) else { return nil }
        return MultipartFile(field: "image", filename: "scan.jpg", mimeType: "image/jpeg", data: jpeg)
    }

    private static func jpegData(from data: Data, maxPixelSize: Int, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Bakes in the EXIF orientation so the model sees the photo the right way up.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let output = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
