import Foundation
import Testing
@testable import SwitchboardCore

private func url(_ s: String) -> URL { URL(string: s)! }

@Suite("Picker list layout")
struct PickerLayoutTests {
    @Test("A few browsers: every row shows, no scrolling")
    func fits() {
        let layout = PickerLayout(rowCount: 4, size: .medium, availableHeight: 800)
        #expect(!layout.scrolls)
        #expect(layout.listHeight == 4 * 48 + 3 * PickerLayout.rowSpacing)
    }

    @Test("Many browsers on a short screen: the list scrolls and stays within the room")
    func scrolls() {
        let layout = PickerLayout(rowCount: 30, size: .medium, availableHeight: 500)
        #expect(layout.scrolls)
        #expect(layout.listHeight <= 500)
        // Shows a half row at the bottom, a hint that there's more.
        let rows = (layout.listHeight - layout.rowHeight / 2 + PickerLayout.rowSpacing) / (layout.rowHeight + PickerLayout.rowSpacing)
        #expect(rows.rounded() == rows)
    }

    @Test("Exactly enough room doesn't scroll")
    func exact() {
        let full = PickerLayout(rowCount: 10, size: .large, availableHeight: 10_000).listHeight
        #expect(!PickerLayout(rowCount: 10, size: .large, availableHeight: full).scrolls)
        #expect(PickerLayout(rowCount: 10, size: .large, availableHeight: full - 1).scrolls)
    }

    @Test("A tiny screen still shows two and a half rows")
    func floor() {
        let layout = PickerLayout(rowCount: 12, size: .small, availableHeight: 20)
        #expect(layout.scrolls)
        #expect(layout.listHeight >= 2.5 * PickerSize.small.rowHeight)
    }

    @Test("No browsers: empty list")
    func empty() {
        let layout = PickerLayout(rowCount: 0, size: .medium, availableHeight: 500)
        #expect(layout.listHeight == 0)
        #expect(!layout.scrolls)
    }

    @Test("The icon has the same inset above, below and beside it in every size")
    func evenInset() {
        for size in PickerSize.allCases {
            #expect(size.rowHeight - size.iconSize == 2 * PickerSize.rowInset)
        }
    }

    @Test("Sizes grow")
    func sizes() {
        #expect(PickerSize.small.rowHeight < PickerSize.medium.rowHeight)
        #expect(PickerSize.medium.rowHeight < PickerSize.large.rowHeight)
    }
}

@Suite("Picker keyboard selection")
struct PickerSelectionTests {
    @Test("Down and up wrap around, like Tab in a menu")
    func wraps() {
        #expect(PickerSelection.moved(from: 0, by: 1, count: 3) == 1)
        #expect(PickerSelection.moved(from: 2, by: 1, count: 3) == 0)
        #expect(PickerSelection.moved(from: 0, by: -1, count: 3) == 2)
        #expect(PickerSelection.moved(from: 5, by: 1, count: 3) == 0) // out of range is clamped first
        #expect(PickerSelection.moved(from: 0, by: 1, count: 0) == 0)
    }

    @Test("Number keys label the first nine rows")
    func keyLabels() {
        #expect(PickerSelection.keyLabel(for: 0) == "1")
        #expect(PickerSelection.keyLabel(for: 8) == "9")
        #expect(PickerSelection.keyLabel(for: 9) == nil)
        #expect(PickerSelection.keyLabel(for: -1) == nil)
    }

    @Test("Row subtitles name the profile, private and background options")
    func subtitles() {
        var target = Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome")
        #expect(target.pickerSubtitle == "")
        target.profile = BrowserProfile(directory: "Profile 1", name: "Work")
        #expect(target.pickerSubtitle == "Work")
        target.privateWindow = true
        target.opensInBackground = true
        #expect(target.pickerSubtitle == "Work · Private · Background")
    }
}

@Suite("Tracking parameters")
struct TrackingParameterTests {
    @Test("utm_* and click ids are removed, other parameters keep their order and encoding")
    func strips() {
        let cleaned = TrackingParameters.strip(url("https://example.com/a?id=7&utm_source=news&q=a%20b&fbclid=XYZ&UTM_Campaign=x#top"))
        #expect(cleaned.absoluteString == "https://example.com/a?id=7&q=a%20b#top")
    }

    @Test("Only tracking parameters: the query goes away entirely")
    func allTracking() {
        #expect(TrackingParameters.strip(url("https://example.com/?utm_medium=email&gclid=1")).absoluteString == "https://example.com/")
    }

    @Test("Links without tracking parameters are returned untouched")
    func untouched() {
        let original = url("https://example.com/search?q=utm_source&ref=home&a=1&&b")
        #expect(TrackingParameters.strip(original) == original)
        let noQuery = url("https://example.com/path#frag")
        #expect(TrackingParameters.strip(noQuery) == noQuery)
    }

    @Test("Files and other schemes are left alone")
    func otherSchemes() {
        let file = url("file:///tmp/a.html?utm_source=x")
        #expect(TrackingParameters.strip(file) == file)
    }

    @Test("Parameter names without a value and encoded names")
    func edgeNames() {
        #expect(TrackingParameters.strip(url("https://example.com/?fbclid&x=1")).absoluteString == "https://example.com/?x=1")
        #expect(TrackingParameters.strip(url("https://example.com/?utm%5Fsource=a&x=1")).absoluteString == "https://example.com/?x=1")
    }
}

@Suite("Config: picker settings")
struct PickerConfigTests {
    @Test("Older settings files load with the defaults")
    func defaults() throws {
        let json = #"{"targets":[],"rules":[]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.pickerSize == .medium)
        #expect(config.stripsTrackingParameters == false)
    }

    @Test("An unknown picker size from a newer version falls back instead of failing")
    func unknownSize() throws {
        let json = #"{"targets":[],"rules":[],"pickerSize":"huge","stripsTrackingParameters":true}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.pickerSize == .medium)
        #expect(config.stripsTrackingParameters)
    }

    @Test("Round trip")
    func roundTrip() throws {
        let config = Config(pickerSize: .large, stripsTrackingParameters: true)
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }
}
