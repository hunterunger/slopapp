import Testing
@testable import SlopKit

@Test func hexComponents() {
    let c = rgbComponents(0xFF8000)
    #expect(c.red == 1)
    #expect(abs(c.green - 128.0 / 255) < 0.0001)
    #expect(c.blue == 0)
}

@Test func appInfoReadsInfoPlist() {
    let info = AppInfo(
        infoDictionary: [
            "CFBundleName": "Awake",
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "7",
            "SlopappTagline": "Stay up.",
        ],
        fallbackName: "Fallback"
    )
    #expect(info == AppInfo(name: "Awake", version: "1.2.0", build: "7", tagline: "Stay up."))
    #expect(info.versionString == "Version 1.2.0 (7)")
}

@Test func appInfoFallsBackOutsideABundle() {
    let info = AppInfo(infoDictionary: [:], fallbackName: "Awake")
    #expect(info.name == "Awake")
    #expect(info.version == "dev")
}
