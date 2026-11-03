import CoreGraphics
import Foundation
import Testing
@testable import SnapperCore

@Suite("Files")
struct FilesTests {
    @Test func namesLikeMacOS() {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 3, 4)
        (components.hour, components.minute, components.second) = (9, 5, 7)
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = calendar.date(from: components)!
        #expect(FileNaming.baseName(for: date, timeZone: utc) == "Screenshot 2026-03-04 at 09.05.07")
    }

    @Test func collisionsGetANumber() {
        let taken: Set = ["Shot.png", "Shot 2.png"]
        #expect(FileNaming.uniqueName(base: "Shot", fileExtension: "png") { taken.contains($0) } == "Shot 3.png")
        #expect(FileNaming.uniqueName(base: "Other", fileExtension: "png") { taken.contains($0) } == "Other.png")
    }

    @Test func saveLocationOrder() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(SaveLocation.resolve(override: "/tmp/snapper-test", chosen: "/x", systemScreenshotFolder: "/y", home: home).path == "/tmp/snapper-test")
        #expect(SaveLocation.resolve(override: nil, chosen: "/x", systemScreenshotFolder: "/y", home: home).path == "/x")
        #expect(SaveLocation.resolve(override: " ", chosen: nil, systemScreenshotFolder: "/y", home: home).path == "/y")
        #expect(SaveLocation.resolve(override: nil, chosen: nil, systemScreenshotFolder: nil, home: home).path == "/Users/someone/Desktop")
    }

    @Test func encodesAndSavesWithoutOverwriting() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapper-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = TestImages.solid(width: 40, height: 20, red: 1, green: 0, blue: 0)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try ImageEncoder.save(image, format: .png, to: folder, date: date)
        let second = try ImageEncoder.save(image, format: .png, to: folder, date: date)
        #expect(first != second)
        #expect(second.lastPathComponent.hasSuffix(" 2.png"))
        let decoded = try #require(ImageEncoder.image(from: Data(contentsOf: first)))
        #expect(decoded.width == 40 && decoded.height == 20)
        let jpeg = try ImageEncoder.data(for: image, format: .jpeg)
        #expect(jpeg.starts(with: [0xFF, 0xD8]))
    }
}

@Suite("Saving again")
struct SaveAgainTests {
    @Test func savingTheSameCaptureAgainOverwritesItsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapper-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let red = TestImages.solid(width: 10, height: 10, red: 1, green: 0, blue: 0)
        let blue = TestImages.solid(width: 10, height: 10, red: 0, green: 0, blue: 1)
        let first = try ImageEncoder.save(red, format: .png, to: folder)
        let again = try ImageEncoder.save(blue, format: .png, to: folder, replacing: first)
        #expect(again == first)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
        let decoded = try #require(ImageEncoder.image(from: Data(contentsOf: again)))
        #expect(TestImages.pixel(decoded, x: 5, y: 5).b > 240)
        // Another format or folder makes a new file instead.
        let jpeg = try ImageEncoder.save(blue, format: .jpeg, to: folder, replacing: first)
        #expect(jpeg != first)
    }

    @Test func formatsAndExtensions() throws {
        #expect(ImageFormat(fileExtension: "JPEG") == .jpeg)
        #expect(ImageFormat(fileExtension: "heic") == .heic)
        #expect(ImageFormat(fileExtension: "gif") == nil)
        let heic = try ImageEncoder.data(for: TestImages.solid(width: 16, height: 16, red: 0, green: 1, blue: 0), format: .heic)
        #expect(heic.count > 0)
    }
}

@Suite("Capture cards")
struct CardQueueTests {
    let now = Date(timeIntervalSince1970: 1_000)

    @Test func autoCloseDeadlines() {
        var queue = CardQueue<Int>()
        queue.add(1, now: now, autoClose: .tenSeconds)
        queue.add(2, now: now.addingTimeInterval(5), autoClose: .tenSeconds)
        #expect(queue.due(at: now.addingTimeInterval(9)).isEmpty)
        #expect(queue.due(at: now.addingTimeInterval(10)) == [1])
        #expect(queue.due(at: now.addingTimeInterval(15)) == [1, 2])
        #expect(queue.nextDeadline == now.addingTimeInterval(10))
    }

    @Test func neverMeansNoDeadline() {
        var queue = CardQueue<Int>()
        queue.add(1, now: now, autoClose: .never)
        #expect(queue.due(at: now.addingTimeInterval(100_000)).isEmpty)
        #expect(queue.nextDeadline == nil)
    }

    @Test func hoverPausesAndRestarts() {
        var queue = CardQueue<Int>()
        queue.add(1, now: now, autoClose: .tenSeconds)
        queue.setHovering(1, true, now: now.addingTimeInterval(8), autoClose: .tenSeconds)
        #expect(queue.due(at: now.addingTimeInterval(60)).isEmpty)
        queue.setHovering(1, false, now: now.addingTimeInterval(60), autoClose: .tenSeconds)
        #expect(queue.due(at: now.addingTimeInterval(69)).isEmpty)
        #expect(queue.due(at: now.addingTimeInterval(70)) == [1])
    }

    @Test func limitPushesOutTheOldest() {
        var queue = CardQueue<Int>(limit: 2)
        queue.add(1, now: now, autoClose: .never)
        queue.add(2, now: now, autoClose: .never)
        #expect(queue.add(3, now: now, autoClose: .never) == [1])
        #expect(queue.ids == [2, 3])
        queue.remove(2)
        #expect(queue.ids == [3])
    }

    @Test func rescheduleAfterSettingChange() {
        var queue = CardQueue<Int>()
        queue.add(1, now: now, autoClose: .never)
        queue.reschedule(now: now, autoClose: .thirtySeconds)
        #expect(queue.nextDeadline == now.addingTimeInterval(30))
    }

    @Test func afterCaptureDefaultsToTheCardOnly() {
        #expect(AfterCapture.default == [.showCard])
        #expect(AutoClose.never.interval == nil)
        #expect(AutoClose.oneMinute.interval == 60)
    }
}

@Suite("Pins")
struct PinGeometryTests {
    @Test func digitsSetOpacity() {
        #expect(PinGeometry.opacity(forDigit: 0) == 1)
        #expect(PinGeometry.opacity(forDigit: 5) == 0.5)
        #expect(PinGeometry.opacity(forDigit: 10) == nil)
        #expect(PinGeometry.clampedOpacity(0) == PinGeometry.minimumOpacity)
    }

    @Test func initialSizeFitsTheScreenProportionally() {
        let size = PinGeometry.initialSize(imagePoints: CGSize(width: 3000, height: 1000), visible: CGSize(width: 1440, height: 900))
        #expect(size.width == 1360)
        #expect(abs(size.width / size.height - 3) < 0.01)
        #expect(PinGeometry.initialSize(imagePoints: CGSize(width: 200, height: 100), visible: CGSize(width: 1440, height: 900)) == CGSize(width: 200, height: 100))
    }

    @Test func zoomKeepsAMinimumAndALimit() {
        let limit = CGSize(width: 1000, height: 1000)
        #expect(PinGeometry.zoomed(CGSize(width: 100, height: 50), by: 2, limit: limit) == CGSize(width: 200, height: 100))
        let tiny = PinGeometry.zoomed(CGSize(width: 100, height: 50), by: 0.1, limit: limit)
        #expect(tiny.height == PinGeometry.minimumSide)
        #expect(PinGeometry.zoomed(CGSize(width: 800, height: 400), by: 4, limit: limit).width == 1000)
    }
}

enum TestImages {
    static func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Black and white vertical stripes, 1 px wide: blur and pixelate must flatten them.
    static func stripes(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for x in stride(from: 0, to: width, by: 2) {
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return context.makeImage()!
    }

    /// RGBA of one pixel (x, y from the top-left).
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[1], data[2], data[3])
    }
}
