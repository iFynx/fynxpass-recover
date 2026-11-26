//
// Recover.swift
//
// © 2026 iFynx Integrated Solutions P.S.C.
//

import CryptoKit
import Foundation

/// Opens a FynxPass `.fpx` archive with the printed Legacy shares, offline.
/// Bytes in, items out: this file never opens a socket, a URL or a file.
public enum Recover {
    public enum Failure: Error, Equatable {
        case notAnArchive
        case notAShareArchive
        case badShare
        case notEnoughShares(provided: Int, required: Int)
        case sharesDisagree
        case decryptionFailed
        case unsupportedVersion(Int)
    }

    /// The archive's items as JSON: `[{typeID, title, values: {name: {text|list}}}]`, keys
    /// sorted, passkey private keys left out (the same output the app's export gives).
    public static func open(archive: Data, printedShares: [String]) throws -> Data {
        let shares = try printedShares.map { try readPrinted(String($0.filter { !$0.isWhitespace })) }
        let key = try Shamir.combine(shares)
        let body = try Archive.open(archive, key: key)
        return try Archive.items(body)
    }

    // MARK: Printed shares

    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Base32 (RFC 4648 alphabet, no padding) in groups of four joined by "-".
    static func readPrinted(_ text: String) throws -> Data {
        var bits = 0
        var value = 0
        var out = Data()
        for character in text.uppercased() where character != "-" {
            guard let index = alphabet.firstIndex(of: character) else { throw Failure.badShare }
            value = ((value << 5) | index) & 0xFFFF
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((value >> bits) & 0xFF))
            }
        }
        return out
    }
}

/// FPCP Shamir shares over GF(2⁸): version(1) ‖ threshold(1) ‖ index(1) ‖ y(32) ‖ SHA-256(…)[0..4].
enum Shamir {
    static let keyLength = 32
    static let checksumLength = 4
    static let shareLength = 3 + keyLength + checksumLength

    static func parse(_ share: Data) throws -> (threshold: Int, index: Int, y: Data) {
        guard share.count == shareLength else { throw Recover.Failure.badShare }
        let body = Data(share.dropLast(checksumLength))
        guard Data(SHA256.hash(data: body).prefix(checksumLength)) == share.suffix(checksumLength)
        else { throw Recover.Failure.badShare }
        let bytes = [UInt8](body)
        guard bytes[0] == 1 else { throw Recover.Failure.unsupportedVersion(Int(bytes[0])) }
        guard bytes[1] >= 2, bytes[2] != 0 else { throw Recover.Failure.badShare }
        return (Int(bytes[1]), Int(bytes[2]), Data(bytes[3...]))
    }

    static func combine(_ shares: [Data]) throws -> Data {
        let parsed = try shares.map(parse)
        guard let threshold = parsed.first?.threshold else {
            throw Recover.Failure.notEnoughShares(provided: 0, required: 2)
        }
        guard parsed.allSatisfy({ $0.threshold == threshold }),
              Set(parsed.map(\.index)).count == parsed.count
        else { throw Recover.Failure.sharesDisagree }
        guard parsed.count >= threshold else {
            throw Recover.Failure.notEnoughShares(provided: parsed.count, required: threshold)
        }
        let selected = Array(parsed.prefix(threshold))
        var secret = [UInt8](repeating: 0, count: keyLength)
        for (i, share) in selected.enumerated() {
            var numerator = 1
            var denominator = 1
            for (j, other) in selected.enumerated() where i != j {
                numerator = gfMul(numerator, other.index)
                denominator = gfMul(denominator, share.index ^ other.index)
            }
            let basis = gfMul(numerator, gfInv(denominator))
            let y = [UInt8](share.y)
            for position in 0 ..< keyLength {
                secret[position] ^= UInt8(gfMul(Int(y[position]), basis))
            }
        }
        return Data(secret)
    }

    static func gfMul(_ aIn: Int, _ bIn: Int) -> Int {
        var a = aIn
        var b = bIn
        var result = 0
        for _ in 0 ..< 8 {
            result ^= -(b & 1) & a
            a = (a << 1) ^ (0x11B & -((a >> 7) & 1))
            b >>= 1
        }
        return result & 0xFF
    }

    /// a²⁵⁴ = a⁻¹ in GF(2⁸); never called with 0 (share indices are distinct).
    static func gfInv(_ a: Int) -> Int {
        var result = 1
        var base = a
        for _ in 0 ..< 7 {
            base = gfMul(base, base)
            result = gfMul(result, base)
        }
        return result
    }
}

/// `.fpx`: "FPX1" ‖ flag(1) ‖ salt(16) ‖ Argon2 m, t, p (3 × u32 LE) ‖ envelope.
/// flag 2 = sealed with a raw key (the Legacy shares); flag 1 = sealed with a password.
/// envelope: version(1) ‖ nonce(12) ‖ AES-256-GCM ciphertext ‖ tag(16), AAD "fpcp1.export.fpx".
enum Archive {
    static let label = Data("fpcp1.export.fpx".utf8)

    static func open(_ data: Data, key: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 4 + 1 + 16 + 12 + 1 + 12 + 16, Array(bytes.prefix(4)) == Array("FPX1".utf8) else {
            throw Recover.Failure.notAnArchive
        }
        guard bytes[4] == 2 else { throw Recover.Failure.notAShareArchive }
        let envelope = Array(bytes[(4 + 1 + 16 + 12)...])
        guard envelope[0] == 1 else { throw Recover.Failure.unsupportedVersion(Int(envelope[0])) }
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: envelope[1 ..< 13]),
                ciphertext: envelope[13 ..< (envelope.count - 16)],
                tag: envelope[(envelope.count - 16)...]
            )
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: label)
        } catch {
            throw Recover.Failure.decryptionFailed
        }
    }

    /// Keeps text and list values, as the app reads its own archives.
    static func items(_ body: Data) throws -> Data {
        guard let rows = try JSONSerialization.jsonObject(with: body) as? [[String: Any]] else {
            throw Recover.Failure.notAnArchive
        }
        let items: [[String: Any]] = rows.compactMap { row in
            guard let typeID = row["typeID"] as? String, let title = row["title"] as? String else {
                return nil
            }
            var values: [String: Any] = [:]
            for (name, raw) in row["values"] as? [String: Any] ?? [:] {
                if typeID == "passkey", name == "privateKey" {
                    continue
                }
                if let text = raw as? [String: String], let value = text["text"] {
                    values[name] = ["text": value]
                } else if let list = raw as? [String: [String]], let value = list["list"] {
                    values[name] = ["list": value]
                }
            }
            return ["typeID": typeID, "title": title, "values": values]
        }
        return try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
    }
}
