// Generates Convert's test media (synthetic only). Only ever writes under /tmp.
//
//   swift run --package-path apps/Convert ConvertFixturesTool [/tmp/convert-test/fixtures] [--quick]
//
// --quick skips the 35-second clip.
import ConvertFixtures
import Foundation

let args = CommandLine.arguments.dropFirst()
let folder = URL(fileURLWithPath: args.first(where: { $0.hasPrefix("/") }) ?? "/tmp/convert-test/fixtures")
guard folder.path.hasPrefix("/tmp/") || folder.path.hasPrefix("/private/tmp/") else {
    FileHandle.standardError.write(Data("fixtures must live under /tmp\n".utf8))
    exit(1)
}
do {
    let made = try FixtureMaker.standardSet(in: folder, includeLong: !args.contains("--quick"))
        + (try await FixtureMaker.matroskaSet(in: folder))
    for url in made { print(url.path) }
} catch {
    FileHandle.standardError.write(Data("failed: \(error)\n".utf8))
    exit(1)
}
