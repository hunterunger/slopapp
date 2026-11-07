import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// QR codes: generate with Core Image, read with Vision. All on device.
public enum QRCode {
    public enum Correction: String, CaseIterable, Sendable, Identifiable {
        case low = "L", medium = "M", quartile = "Q", high = "H"
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .low: "Low (7%)"
            case .medium: "Medium (15%)"
            case .quartile: "Quartile (25%)"
            case .high: "High (30%)"
            }
        }
    }

    public struct QRError: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String
        public init(description: String) { self.description = description }
    }

    /// The code as a black-on-white image, `scale` pixels per module, with the standard
    /// four-module quiet zone.
    public static func generate(_ text: String, correction: Correction = .medium, scale: Int = 10) throws -> CGImage {
        guard !text.isEmpty else { throw QRError(description: "Nothing to encode") }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw QRError(description: "QR generation isn't available") }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(correction.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else {
            throw QRError(description: "Too much text for a QR code at this error correction (the limit is about 2,900 bytes at Low)")
        }
        // Core Image adds a one-module margin; pad to four.
        let padded = output.transformed(by: CGAffineTransform(translationX: 3, y: 3))
            .composited(over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -3, dy: -3).offsetBy(dx: 3, dy: 3)))
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let image = context.createCGImage(scaled, from: scaled.extent) else { throw QRError(description: "Couldn't draw the QR code") }
        return image
    }

    public static func modules(_ text: String, correction: Correction = .medium) -> Int? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(correction.rawValue, forKey: "inputCorrectionLevel")
        return filter.outputImage.map { Int($0.extent.width) - 2 }
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Every QR code payload found in the image, top to bottom.
    public static func read(_ image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw QRError(description: "Couldn't scan the image")
        }
        let results = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        return results.compactMap(\.payloadStringValue)
    }

    public static func read(imageData: Data) throws -> [String] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw QRError(description: "That file isn't an image")
        }
        return try read(image)
    }

    // MARK: Payload templates

    public enum WiFiSecurity: String, CaseIterable, Sendable, Identifiable {
        case wpa = "WPA", wep = "WEP", none = "nopass"
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .wpa: "WPA/WPA2/WPA3"
            case .wep: "WEP"
            case .none: "None"
            }
        }
    }

    /// The de-facto Wi-Fi network format phones understand (`WIFI:T:WPA;S:name;P:pass;;`).
    public static func wifiPayload(ssid: String, password: String, security: WiFiSecurity, hidden: Bool) -> String {
        func escape(_ text: String) -> String {
            var out = ""
            for character in text {
                if "\\;,:\"".contains(character) { out.append("\\") }
                out.append(character)
            }
            return out
        }
        var payload = "WIFI:T:\(security.rawValue);S:\(escape(ssid));"
        if security != .none { payload += "P:\(escape(password));" }
        if hidden { payload += "H:true;" }
        return payload + ";"
    }
}
