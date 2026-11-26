//
// main.swift
//
// © 2026 iFynx Integrated Solutions P.S.C.
//

import Foundation
import RecoverKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    let usage = "usage: fynxpass-recover archive.fpx share.txt share.txt ...\n"
    FileHandle.standardError.write(Data(usage.utf8))
    exit(EXIT_FAILURE)
}

do {
    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    let shares = try arguments.dropFirst(2).map { path in
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }
    var json = try Recover.open(archive: archive, printedShares: shares)
    json.append(UInt8(ascii: "\n"))
    FileHandle.standardOutput.write(json)
} catch {
    // One plain message: which part was wrong is not said, on purpose.
    FileHandle.standardError.write(Data("recovery failed\n".utf8))
    exit(EXIT_FAILURE)
}
