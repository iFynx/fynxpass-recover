//
// RecoverTests.swift
//
// © 2026 iFynx Integrated Solutions P.S.C.
//

import Foundation
import Testing
@testable import RecoverKit

/// The vectors were written by the FynxPass app's own code (an archive sealed with a random key,
/// that key split 2-of-3 into printed shares, and the JSON the app prints for it).
@Suite("fynxpass-recover")
struct RecoverTests {
    private static func vector(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Vectors"))
    }

    private static func share(_ number: Int) throws -> String {
        try String(contentsOf: vector("share-\(number).txt"), encoding: .utf8)
    }

    @Test("Any two of the three shares give exactly what the app prints",
          arguments: [(1, 2), (1, 3), (2, 3), (3, 1)])
    func anyTwo(pair: (Int, Int)) throws {
        let json = try Recover.open(
            archive: Data(contentsOf: Self.vector("vault.fpx")),
            printedShares: [Self.share(pair.0), Self.share(pair.1)]
        )
        let expected = try Data(contentsOf: Self.vector("expected.json")).dropLast()
        #expect(json == expected)
        #expect(!String(decoding: json, as: UTF8.self).contains("SECRET-PASSKEY"))
    }

    @Test("One share is not enough")
    func oneShare() throws {
        #expect(throws: Recover.Failure.notEnoughShares(provided: 1, required: 2)) {
            try Recover.open(archive: Data(contentsOf: Self.vector("vault.fpx")),
                             printedShares: [Self.share(1)])
        }
    }

    @Test("A mistyped share is caught by its checksum")
    func typo() throws {
        var text = try Self.share(1)
        let first = text.startIndex
        text.replaceSubrange(first ... first, with: text.first == "A" ? "B" : "A")
        #expect(throws: Recover.Failure.badShare) {
            try Recover.open(archive: Data(contentsOf: Self.vector("vault.fpx")),
                             printedShares: [text, Self.share(2)])
        }
    }

    @Test("A password-sealed export is refused, not misread")
    func passwordArchive() throws {
        #expect(throws: Recover.Failure.notAShareArchive) {
            try Recover.open(archive: Data(contentsOf: Self.vector("password.fpx")),
                             printedShares: [Self.share(1), Self.share(2)])
        }
    }

    @Test("A changed byte in the archive fails authentication")
    func tampered() throws {
        var archive = try Data(contentsOf: Self.vector("vault.fpx"))
        archive[archive.count - 20] ^= 0x01
        #expect(throws: Recover.Failure.decryptionFailed) {
            try Recover.open(archive: archive, printedShares: [Self.share(1), Self.share(2)])
        }
    }

    @Test("The built tool: JSON on success, one plain line and a non-zero exit otherwise")
    func tool() throws {
        let archive = try Self.vector("vault.fpx").path
        let ok = try run([archive, Self.vector("share-1.txt").path, Self.vector("share-3.txt").path])
        #expect(ok.status == 0)
        #expect(ok.out == (try Data(contentsOf: Self.vector("expected.json"))))
        let one = try run([archive, Self.vector("share-1.txt").path])
        #expect(one.status != 0 && one.out.isEmpty)
        #expect(String(decoding: one.err, as: UTF8.self) == "recovery failed\n")
        let usage = try run([])
        #expect(usage.status != 0)
        #expect(String(decoding: usage.err, as: UTF8.self).hasPrefix("usage:"))
    }

    private func run(_ arguments: [String]) throws -> (status: Int32, out: Data, err: Data) {
        let process = Process()
        // The build folder holds both the test bundle and the tool.
        process.executableURL = Bundle(for: Marker.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("fynxpass-recover")
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            out.fileHandleForReading.readDataToEndOfFile(),
            err.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

private final class Marker {}
