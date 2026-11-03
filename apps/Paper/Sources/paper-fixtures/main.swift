import Foundation
import PaperFixtures

// Writes Paper's generated test PDFs: swift run --package-path apps/Paper paper-fixtures /tmp/paper-test
let path = CommandLine.arguments.dropFirst().first ?? "/tmp/paper-test/fixtures"
guard path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") else {
    FileHandle.standardError.write(Data("Fixtures only go under /tmp.\n".utf8))
    exit(1)
}
let names = try Fixtures.writeAll(to: URL(fileURLWithPath: path))
print("Wrote \(names.count) fixtures to \(path)")
