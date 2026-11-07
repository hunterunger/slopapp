import Foundation
import Testing

/// Shared CI runners are much slower than a real Mac; speed budgets get 4x headroom there.
private let ciSlack = ProcessInfo.processInfo.environment["CI"] == nil ? 1 : 4
@testable import SpecimenCore

@Suite struct IndexerTests {
    func makeSystem() -> FakeFontSystem {
        let faces = [
            SystemFace(postScriptName: "Mono-Regular", familyName: "Plain One", styleName: "Regular", path: "/u/a.otf", isMonospaceTrait: true),
            SystemFace(postScriptName: "Serif-Regular", familyName: "Plain Two", styleName: "Regular", path: "/u/b.otf", stylisticClass: 2),
            SystemFace(postScriptName: "Var-Regular", familyName: "Plain Three", styleName: "Regular", path: "/u/c.ttf"),
        ]
        let system = FakeFontSystem(faces, details: [
            faces[2].id: FaceDetails(panose: [2, 11, 0, 0, 0, 0, 0, 0, 0, 0], axes: [VariationAxis(tag: "wght", name: "Weight", minimum: 100, maximum: 900, defaultValue: 400)]),
        ])
        system.dates = ["/u/a.otf": Date(timeIntervalSince1970: 1), "/u/b.otf": Date(timeIntervalSince1970: 2), "/u/c.ttf": Date(timeIntervalSince1970: 3)]
        return system
    }

    @Test func buildsAndClassifies() {
        let result = FontIndexer(system: makeSystem()).build(cache: IndexCache())
        #expect(result.faces.map(\.category) == [.monospaced, .serif, .sansSerif])
        #expect(result.faces[2].isVariable)
        #expect(result.faces[2].axes.first?.summary == "Weight 100–900")
        #expect(result.freshlyRead == 3)
    }

    @Test func reusesCacheUntilFileChanges() {
        let system = makeSystem()
        let first = FontIndexer(system: system).build(cache: IndexCache())
        let second = FontIndexer(system: system).build(cache: first.cache)
        #expect(second.freshlyRead == 0)
        #expect(system.detailsCalls == 3)
        system.dates["/u/b.otf"] = Date(timeIntervalSince1970: 99)
        let third = FontIndexer(system: system).build(cache: second.cache)
        #expect(third.freshlyRead == 1)
        #expect(third.faces == first.faces.map { var f = $0; if f.path == "/u/b.otf" { f.fileModified = Date(timeIntervalSince1970: 99) }; return f })
    }

    @Test func cacheRoundTripsAndToleratesDamage() throws {
        let dir = temporaryDirectory()
        let url = dir.appendingPathComponent("Cache/index.plist")
        let built = FontIndexer(system: makeSystem()).build(cache: IndexCache())
        try built.cache.save(to: url)
        #expect(IndexCache.load(from: url) == built.cache)
        #expect(IndexCache.load(from: url).faces.count == 3)
        try Data("garbage".utf8).write(to: url)
        #expect(IndexCache.load(from: url).entries.isEmpty)
        #expect(IndexCache.load(from: dir.appendingPathComponent("missing")).entries.isEmpty)
    }

    @Test func applyStatesNeedsSameFaces() {
        let system = makeSystem()
        let faces = FontIndexer(system: system).build(cache: IndexCache()).faces
        #expect(FontIndexer.applyStates(Array(system.listFaces().dropLast()), to: faces) == nil)
    }

    @Test func stressCopiesAreUnique() {
        let faces = FontIndexer(system: makeSystem()).build(cache: IndexCache()).faces
        let many = FontIndexer.stressCopies(faces, copies: 10)
        #expect(many.count == 30)
        #expect(Set(many.map(\.id)).count == 30)
        #expect(FontFamily.group(many).count == 30)
    }

    @Test func indexesTenThousandFacesQuickly() {
        let faces = (0..<10_000).map { SystemFace(postScriptName: "F\($0)", familyName: "Family \($0 / 5)", styleName: "S\($0 % 5)", path: "/u/\($0).otf", weight: Double($0 % 5) / 5) }
        let system = FakeFontSystem(faces)
        let clock = ContinuousClock()
        var families: [FontFamily] = []
        var items: [GridEntry] = []
        let elapsed = clock.measure {
            let built = FontIndexer(system: system).build(cache: IndexCache())
            families = FontFamily.group(built.faces)
            items = LibraryFilter.items(in: families, query: LibraryQuery(search: "family 19"))
        }
        #expect(families.count == 2000)
        #expect(!items.isEmpty)
        #expect(elapsed < .seconds(3) * ciSlack)
        let filterTime = clock.measure { _ = LibraryFilter.items(in: families, query: LibraryQuery(search: "s3")) }
        print("10k faces: index+group+filter \(elapsed), one search over 2,000 families \(filterTime)")
        #expect(filterTime < .milliseconds(150) * ciSlack)
    }
}
