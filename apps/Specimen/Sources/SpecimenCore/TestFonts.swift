import CoreText
import Foundation

/// Session-scope registration of a folder of test fonts (test mode and `specimen-fixture`).
/// Never used on the owner's installed fonts.
public enum TestFonts {
    public static let extensions: Set<String> = ["ttf", "otf", "ttc", "otc"]

    public static func fontFiles(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { extensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted().map { directory.appendingPathComponent($0) }
    }

    /// Registers files that aren't registered yet at session scope (until logout at most).
    /// Returns the error messages, if any.
    @discardableResult
    public static func register(_ urls: [URL]) -> [String] {
        let fresh = urls.filter { CTFontManagerGetScopeForURL($0 as CFURL) == .none }
        guard !fresh.isEmpty else { return [] }
        return wait { CTFontManagerRegisterFontURLs(fresh as CFArray, .session, true, $0) }
    }

    /// Turns every face in `urls` back on, then unregisters them. (A face turned off loses its
    /// session registration, so unregistering alone would leave it behind as "off".)
    @discardableResult
    public static func cleanUp(_ urls: [URL]) -> [String] {
        let descriptors = urls.flatMap { CTFontManagerCreateFontDescriptorsFromURL($0 as CFURL) as? [CTFontDescriptor] ?? [] }
        if !descriptors.isEmpty { CTFontManagerEnableFontDescriptors(descriptors as CFArray, true) }
        let registered = urls.filter { CTFontManagerGetScopeForURL($0 as CFURL) != .none }
        guard !registered.isEmpty else { return [] }
        return wait { CTFontManagerUnregisterFontURLs(registered as CFArray, .session, $0) }
    }

    /// Runs a CoreText (un)registration and waits for its handler to say it's done.
    static func wait(_ start: (@escaping (CFArray, Bool) -> Bool) -> Void) -> [String] {
        let box = ErrorBox()
        let done = DispatchSemaphore(value: 0)
        start { errors, finished in
            box.append((errors as? [Error] ?? []).map(\.localizedDescription))
            if finished { done.signal() }
            return true
        }
        _ = done.wait(timeout: .now() + 10)
        return box.messages
    }
}

private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func append(_ messages: [String]) { lock.withLock { stored += messages } }
    var messages: [String] { lock.withLock { stored } }
}
