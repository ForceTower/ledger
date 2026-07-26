import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MultipartFile: Sendable {
    var field: String
    var filename: String
    var mimeType: String
    var data: Data
}

/// A `multipart/form-data` body. The AI endpoints take an image, some text, or both.
struct MultipartForm: Sendable {
    var fields: [(name: String, value: String)] = []
    var files: [MultipartFile] = []

    var isEmpty: Bool { fields.isEmpty && files.isEmpty }

    func body(boundary: String) -> Data {
        var body = Data()
        for field in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            body.append(field.value)
            body.append("\r\n")
        }
        for file in files {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.filename)\"\r\n")
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        return body
    }
}

extension MultipartFile {
    /// The camera hands back HEIC and the photo library hands back whatever the user saved, neither of
    /// which the scan endpoints accept. Re-encoding also keeps the upload well under the server's 10 MB
    /// cap and near the resolution the model actually reads.
    static func imageUpload(
        from data: Data,
        filename: String,
        maxPixelSize: Int = 1568,
        quality: Double = 0.8
    ) -> MultipartFile? {
        guard let jpeg = jpegData(from: data, maxPixelSize: maxPixelSize, quality: quality) else { return nil }
        return MultipartFile(field: "image", filename: filename, mimeType: "image/jpeg", data: jpeg)
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
