import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Export as Images: one file per page, as the page looks (annotations included).
public enum ImageExport {
    public enum Format: String, CaseIterable, Codable, Sendable {
        case png, jpeg, tiff, heic

        public var title: String {
            switch self {
            case .png: "PNG"
            case .jpeg: "JPEG"
            case .tiff: "TIFF"
            case .heic: "HEIC"
            }
        }

        public var type: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .tiff: .tiff
            case .heic: .heic
            }
        }

        public var fileExtension: String { type.preferredFilenameExtension ?? rawValue }

        /// Formats this Mac can write (HEIC needs a hardware encoder on some Macs).
        public static var available: [Format] {
            let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
            return allCases.filter { writable.contains($0.type.identifier) }
        }
    }

    public static let resolutions: [Int] = [72, 150, 300]

    public enum ExportError: Error, LocalizedError, Equatable {
        case renderFailed(page: Int)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .renderFailed(let page): "Paper couldn't draw page \(page + 1)."
            case .writeFailed(let name): "Paper couldn't write “\(name)”."
            }
        }
    }

    /// "Report page 03.png": numbers padded to the page count's width so files sort.
    public static func fileName(base: String, page: Int, count: Int, format: Format) -> String {
        let digits = String(max(count, 1)).count
        let number = String(repeating: "0", count: max(0, digits - String(page + 1).count)) + String(page + 1)
        return "\(base) page \(number).\(format.fileExtension)"
    }

    /// The page as displayed (crop box, rotation, annotations) on white, at `dpi`.
    public static func image(of page: PDFPage, dpi: Int) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let size = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        let scale = min(CGFloat(dpi) / 72, 12_000 / max(size.width, size.height, 1))
        let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        // draw(with:to:) applies the crop box and rotation, and draws annotations.
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }

    /// Writes the pages into `folder`. Calls `progress(done, total)` after each page and stops
    /// early (returning what was written) when it returns false.
    @discardableResult
    public static func export(_ document: PDFDocument, pages: IndexSet, format: Format, dpi: Int, to folder: URL,
                              baseName: String, progress: (Int, Int) -> Bool = { _, _ in true }) throws -> [URL] {
        var written: [URL] = []
        let total = pages.count
        for (offset, index) in pages.enumerated() {
            guard let page = document.page(at: index) else { continue }
            guard let image = image(of: page, dpi: dpi) else { throw ExportError.renderFailed(page: index) }
            let url = folder.appendingPathComponent(fileName(base: baseName, page: index, count: document.pageCount, format: format))
            try write(image, to: url, format: format, dpi: dpi)
            written.append(url)
            if !progress(offset + 1, total) { break }
        }
        return written
    }

    static func write(_ image: CGImage, to url: URL, format: Format, dpi: Int) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw ExportError.writeFailed(url.lastPathComponent)
        }
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if format == .jpeg || format == .heic { properties[kCGImageDestinationLossyCompressionQuality] = 0.85 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.writeFailed(url.lastPathComponent) }
    }
}

/// A password-protected copy (File > Save Protected Copy…). PDFKit writes standard AES
/// encryption; the open password and the permissions password are separate.
public struct Protection: Sendable, Equatable {
    /// Needed to open the file at all. Empty: anyone can open it.
    public var openPassword: String
    /// Needed to change the permissions below. Required when anything is restricted.
    public var permissionsPassword: String
    public var allowPrinting: Bool
    public var allowCopying: Bool
    public var allowChanges: Bool
    public var allowComments: Bool

    public init(openPassword: String = "", permissionsPassword: String = "", allowPrinting: Bool = true,
                allowCopying: Bool = true, allowChanges: Bool = true, allowComments: Bool = true) {
        self.openPassword = openPassword
        self.permissionsPassword = permissionsPassword
        self.allowPrinting = allowPrinting
        self.allowCopying = allowCopying
        self.allowChanges = allowChanges
        self.allowComments = allowComments
    }

    public var restricts: Bool { !(allowPrinting && allowCopying && allowChanges && allowComments) }

    public enum Problem: Error, Equatable, LocalizedError {
        case nothingToProtect
        case needsPermissionsPassword
        case samePasswords
        case writeFailed
        case checkFailed

        public var errorDescription: String? {
            switch self {
            case .nothingToProtect: "Set an open password or restrict something first."
            case .needsPermissionsPassword: "Restricting printing or editing needs a permissions password."
            case .samePasswords: "Use a different permissions password from the open password, or anyone who can open the file could lift the restrictions."
            case .writeFailed: "Paper couldn't write the protected copy."
            case .checkFailed: "The protected copy didn't check out, so it wasn't saved."
            }
        }
    }

    /// What's wrong with these settings, or nil.
    public var problem: Problem? {
        if openPassword.isEmpty && !restricts { return .nothingToProtect }
        if restricts && permissionsPassword.isEmpty { return .needsPermissionsPassword }
        if restricts && !openPassword.isEmpty && openPassword == permissionsPassword { return .samePasswords }
        return nil
    }

    /// `PDFAccessPermissions` bits (it's an NS_ENUM of flags, so Swift sees it as an enum).
    var permissionBits: UInt {
        var value: UInt = 1 << 5 // content accessibility (screen readers) always allowed
        if allowPrinting { value |= 1 << 0 | 1 << 1 }
        if allowChanges { value |= 1 << 2 | 1 << 3 }
        if allowCopying { value |= 1 << 4 }
        if allowComments { value |= 1 << 6 | 1 << 7 }
        return value
    }

    /// The protected bytes, checked by reopening them.
    public func protect(_ document: PDFDocument) throws -> Data {
        if let problem { throw problem }
        // PDFKit only encrypts with an owner password. Without restrictions it can be random:
        // nobody needs it, and the open password still protects the file.
        let owner = permissionsPassword.isEmpty ? UUID().uuidString + UUID().uuidString : permissionsPassword
        var options: [PDFDocumentWriteOption: Any] = [.ownerPasswordOption: owner, .accessPermissionsOption: NSNumber(value: permissionBits)]
        if !openPassword.isEmpty { options[.userPasswordOption] = openPassword }
        guard let data = document.dataRepresentation(options: options) else { throw Problem.writeFailed }
        try check(data)
        return data
    }

    func check(_ data: Data) throws {
        guard let copy = PDFDocument(data: data), copy.isEncrypted else { throw Problem.checkFailed }
        if !openPassword.isEmpty {
            guard copy.isLocked, copy.unlock(withPassword: openPassword) else { throw Problem.checkFailed }
        } else if copy.isLocked {
            throw Problem.checkFailed
        }
        if restricts {
            if !allowPrinting && copy.allowsPrinting { throw Problem.checkFailed }
            if !allowCopying && copy.allowsCopying { throw Problem.checkFailed }
        }
    }
}
