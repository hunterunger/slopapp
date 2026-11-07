import Testing
@testable import CrateCore

/// Queue rows already show the archive's name: their messages must not repeat it, must fit
/// on one line, and must say what to do.
@Suite struct RowMessageTests {
    static let name = "Holiday Photos 2024.zip"

    static let errors: [CrateError] = [
        .notAnArchive(name: name), .passwordRequired(name: name), .wrongPassword(name: name),
        .unsupportedEncryption(name: name, format: "RAR"), .missingPart(archive: name, part: name),
        .missingPart(archive: name, part: "Holiday Photos 2024.z02"), .damaged(name: name, detail: "x"),
        .truncated(name: name), .suspiciousSize(name: name, limit: 1_000_000_000),
        .notEnoughSpace(name: name, needed: 5_000_000_000, available: 1_000),
        .destinationNotWritable(folder: "Downloads"), .unreadableSource(name: name),
        .passwordNotSupported(format: "Tar.gz"), .nothingToArchive, .writeFailed(name: name, detail: "x"),
        .partTooSmall(minimum: 1_048_576), .nothingToSplit(name: name), .notASplitSet(name: name),
    ]

    @Test func rowMessagesDontRepeatTheName() {
        for error in Self.errors {
            #expect(!error.rowMessage.contains(Self.name), "\(error.rowMessage)")
        }
    }

    @Test func rowMessagesFitOneLine() {
        for error in Self.errors {
            #expect(error.rowMessage.count <= 80, "\(error.rowMessage.count): \(error.rowMessage)")
            #expect(error.rowMessage.hasSuffix(".") || error.rowMessage.hasSuffix("…)."))
        }
    }

    @Test func passwordErrorsCanBeRetried() {
        #expect(!CrateError.passwordRequired(name: Self.name).isFinal)
        #expect(!CrateError.wrongPassword(name: Self.name).isFinal)
        #expect(!CrateError.notEnoughSpace(name: Self.name, needed: 1, available: 0).isFinal)
        #expect(CrateError.notAnArchive(name: Self.name).isFinal)
        #expect(CrateError.damaged(name: Self.name, detail: "").isFinal)
    }
}
