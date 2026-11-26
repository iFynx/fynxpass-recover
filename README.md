# fynxpass-recover

An offline tool that opens a FynxPass `.fpx` archive with the printed **Legacy shares**, without the FynxPass app, an account or a network.

FynxPass Legacy splits the key of a sealed archive into printed shares, of which a set number together open it. If FynxPass is ever not there for the people you chose, they can still open what you left them with this tool and enough shares.

## What it needs

- A Mac with macOS 13 or later and Swift 6 (Xcode 16 or the Swift toolchain).
- The archive file (`.fpx`).
- At least as many printed shares as were set when the archive was made, each typed or pasted into its own text file. Spaces, line breaks and lowercase letters are fine. A typo is caught by the share's checksum.

## Build

```sh
git clone https://github.com/ifynx/fynxpass-recover.git
cd fynxpass-recover
swift build -c release
```

The tool is then at `.build/release/fynxpass-recover`.

## Use

```sh
.build/release/fynxpass-recover vault.fpx share-1.txt share-2.txt > items.json
```

On success it prints the items as JSON:

```json
[{"title":"Example Bank","typeID":"login","values":{"password":{"text":"…"},"username":{"text":"…"}}}]
```

Every value is either `{"text": "…"}` or `{"list": ["…"]}`. Passkey private keys are left out, as in the app's own export.

On any failure it prints one line, `recovery failed`, and exits with a non-zero status. It does not say which part was wrong: a share, the archive, or too few shares.

`items.json` holds every secret in clear text. Keep it on the machine you trust, and delete it when you are done.

## What it does not do

- **No network.** The code never opens a socket, a URL or a connection. The only files it reads are the ones you name, and it writes only to standard output.
- **Password exports are not supported.** An `.fpx` that FynxPass exported with a password (Settings → Export) opens in FynxPass itself (Import). This tool refuses it rather than guess.
- **The Recovery Kit is not used here.** The Recovery Kit restores your FynxPass account in the app. It is not a share and does not open a Legacy archive.

## How it works

- Printed share: Base32 (RFC 4648 alphabet) in groups of four, decoding to `version(1) ‖ threshold(1) ‖ index(1) ‖ y(32) ‖ SHA-256(first 35 bytes)[0..4]`.
- The key: Shamir secret sharing over GF(2⁸) (polynomial 0x11B), Lagrange interpolation at 0.
- The archive: `"FPX1" ‖ flag(1) ‖ salt(16) ‖ Argon2 m, t, p (3 × u32 little-endian) ‖ envelope`, flag `2` for a share-sealed archive. The envelope is `version(1) ‖ nonce(12) ‖ AES-256-GCM ciphertext ‖ tag(16)` with associated data `fpcp1.export.fpx`.
- The only cryptography library is Apple's CryptoKit.

## Tests

```sh
swift test
```

The vectors in `Tests/RecoverKitTests/Vectors` were written by the FynxPass app's own code: an archive, three printed shares (2 of 3), the JSON the app prints for them, and a password export the tool must refuse.

## License

MIT. See [LICENSE](LICENSE).
