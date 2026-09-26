// Oanarina Archi Tool — GPL-3.0-or-later
// Digital signatures (COL-022): Ed25519 (RFC 8032) with SHA-512 (FIPS 180-4) in pure Swift — the field and group
// arithmetic follows TweetNaCl (Bernstein, van Gastel, Janssen, Lange, Schwabe, Smetsers; public domain). Deliverables
// (PDF sheets, DWG/IFC exports, the .archi drawing itself…) are signed with a detached "<file>.sig" (JSON: signer,
// public key, SHA-256 and size of the file, time, signature); verification checks the file is unchanged, the signature
// valid, and the key among the drawing's trusted signers (TRUSTEDSIGNERS). Signing keys are generated locally and
// never leave the Mac.
import Foundation

public enum SHA512 {
    static let k: [UInt64] = [0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118, 0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2, 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65, 0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5, 0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df, 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b, 0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8, 0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3, 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec, 0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b, 0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b, 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817]
    static let h0: [UInt64] = [0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179]

    public static func hash(_ data: Data) -> [UInt8] { hash([UInt8](data)) }
    public static func hash(_ msg: [UInt8]) -> [UInt8] {
        var h = h0
        var m = msg
        let bitLen = UInt64(msg.count) &* 8
        m.append(0x80)
        while m.count % 128 != 112 { m.append(0) }
        m += [UInt8](repeating: 0, count: 8)
        for i in (0..<8).reversed() { m.append(UInt8((bitLen >> (8 * UInt64(i))) & 0xFF)) }
        var w = [UInt64](repeating: 0, count: 80)
        func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { (x >> n) | (x << (64 - n)) }
        var off = 0
        while off < m.count {
            for t in 0..<16 {
                var v: UInt64 = 0
                for b in 0..<8 { v = (v << 8) | UInt64(m[off + t * 8 + b]) }
                w[t] = v
            }
            for t in 16..<80 {
                let s0 = rotr(w[t - 15], 1) ^ rotr(w[t - 15], 8) ^ (w[t - 15] >> 7)
                let s1 = rotr(w[t - 2], 19) ^ rotr(w[t - 2], 61) ^ (w[t - 2] >> 6)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for t in 0..<80 {
                let S1 = rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ S1 &+ ch &+ k[t] &+ w[t]
                let S0 = rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = S0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
            off += 128
        }
        var out: [UInt8] = []
        for v in h { for i in (0..<8).reversed() { out.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) } }
        return out
    }
}

public enum Ed25519 {
    typealias GF = [Int64]
    static func gf(_ v: [Int64] = []) -> GF { var g = GF(repeating: 0, count: 16); for (i, x) in v.enumerated() { g[i] = x }; return g }
    static let gf0 = gf(), gf1 = gf([1])
    static let D = gf([0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070, 0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203])
    static let D2 = gf([0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0, 0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406])
    static let X = gf([0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c, 0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169])
    static let Y = gf([0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666])
    static let I = gf([0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43, 0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83])
    static let L: [Int64] = [0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10]

    static func car(_ o: inout GF) {
        for i in 0..<16 {
            o[i] = o[i] &+ (1 << 16)
            let c = o[i] >> 16
            if i < 15 { o[i + 1] = o[i + 1] &+ (c &- 1) } else { o[0] = o[0] &+ (c &- 1) &+ 37 &* (c &- 1) }
            o[i] = o[i] &- (c << 16)
        }
    }
    static func sel(_ p: inout GF, _ q: inout GF, _ b: Int64) {
        let c = ~(b &- 1)
        for i in 0..<16 { let t = c & (p[i] ^ q[i]); p[i] ^= t; q[i] ^= t }
    }
    static func pack25519(_ n: GF) -> [UInt8] {
        var t = n, m = gf()
        car(&t); car(&t); car(&t)
        for _ in 0..<2 {
            m[0] = t[0] &- 0xffed
            for i in 1..<15 { m[i] = t[i] &- 0xffff &- ((m[i - 1] >> 16) & 1); m[i - 1] &= 0xffff }
            m[15] = t[15] &- 0x7fff &- ((m[14] >> 16) & 1)
            let b = (m[15] >> 16) & 1
            m[14] &= 0xffff
            sel(&t, &m, 1 - b)
        }
        var o = [UInt8](repeating: 0, count: 32)
        for i in 0..<16 { o[2 * i] = UInt8(t[i] & 0xff); o[2 * i + 1] = UInt8((t[i] >> 8) & 0xff) }
        return o
    }
    static func neq(_ a: GF, _ b: GF) -> Bool { pack25519(a) != pack25519(b) }
    static func par(_ a: GF) -> Int64 { Int64(pack25519(a)[0] & 1) }
    static func unpack25519(_ n: [UInt8]) -> GF {
        var o = gf()
        for i in 0..<16 { o[i] = Int64(n[2 * i]) + (Int64(n[2 * i + 1]) << 8) }
        o[15] &= 0x7fff
        return o
    }
    static func A(_ a: GF, _ b: GF) -> GF { var o = gf(); for i in 0..<16 { o[i] = a[i] &+ b[i] }; return o }
    static func Z(_ a: GF, _ b: GF) -> GF { var o = gf(); for i in 0..<16 { o[i] = a[i] &- b[i] }; return o }
    static func M(_ a: GF, _ b: GF) -> GF {
        var t = [Int64](repeating: 0, count: 31)
        for i in 0..<16 { for j in 0..<16 { t[i + j] = t[i + j] &+ a[i] &* b[j] } }
        for i in 0..<15 { t[i] = t[i] &+ 38 &* t[i + 16] }
        var o = Array(t[0..<16])
        car(&o); car(&o)
        return o
    }
    static func S(_ a: GF) -> GF { M(a, a) }
    static func inv(_ i: GF) -> GF {
        var c = i
        for a in stride(from: 253, through: 0, by: -1) { c = S(c); if a != 2 && a != 4 { c = M(c, i) } }
        return c
    }
    static func pow2523(_ i: GF) -> GF {
        var c = i
        for a in stride(from: 250, through: 0, by: -1) { c = S(c); if a != 1 { c = M(c, i) } }
        return c
    }
    static func add(_ p: inout [GF], _ q: [GF]) {
        let a = M(Z(p[1], p[0]), Z(q[1], q[0]))
        let b = M(A(p[0], p[1]), A(q[0], q[1]))
        let c = M(M(p[3], q[3]), D2)
        var d = M(p[2], q[2]); d = A(d, d)
        let e = Z(b, a), f = Z(d, c), g = A(d, c), h = A(b, a)
        p[0] = M(e, f); p[1] = M(h, g); p[2] = M(g, f); p[3] = M(e, h)
    }
    static func cswap(_ p: inout [GF], _ q: inout [GF], _ b: Int64) { for i in 0..<4 { sel(&p[i], &q[i], b) } }
    static func pack(_ p: [GF]) -> [UInt8] {
        let zi = inv(p[2])
        let tx = M(p[0], zi), ty = M(p[1], zi)
        var r = pack25519(ty)
        r[31] ^= UInt8(par(tx) << 7)
        return r
    }
    static func scalarmult(_ q0: [GF], _ s: [UInt8]) -> [GF] {
        var p = [gf0, gf1, gf1, gf0], q = q0
        for i in stride(from: 255, through: 0, by: -1) {
            let b = Int64((s[i / 8] >> UInt8(i & 7)) & 1)
            cswap(&p, &q, b); add(&q, p); add(&p, p); cswap(&p, &q, b)
        }
        return p
    }
    static func scalarbase(_ s: [UInt8]) -> [GF] { scalarmult([X, Y, gf1, M(X, Y)], s) }

    static func modL(_ x: inout [Int64]) -> [UInt8] {
        for i in stride(from: 63, through: 32, by: -1) {
            var carry: Int64 = 0
            var j = i - 32
            while j < i - 12 {
                x[j] = x[j] &+ carry &- 16 &* x[i] &* L[j - (i - 32)]
                carry = (x[j] &+ 128) >> 8
                x[j] = x[j] &- (carry << 8)
                j += 1
            }
            x[j] = x[j] &+ carry
            x[i] = 0
        }
        var carry: Int64 = 0
        for j in 0..<32 {
            x[j] = x[j] &+ carry &- (x[31] >> 4) &* L[j]
            carry = x[j] >> 8
            x[j] &= 255
        }
        for j in 0..<32 { x[j] = x[j] &- carry &* L[j] }
        var r = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { x[i + 1] = x[i + 1] &+ (x[i] >> 8); r[i] = UInt8(x[i] & 255) }
        return r
    }
    static func reduce(_ r: [UInt8]) -> [UInt8] { var x = r.map { Int64($0) }; return modL(&x) }

    static func expand(_ seed: [UInt8]) -> [UInt8] {
        var d = SHA512.hash(seed)
        d[0] &= 248; d[31] &= 127; d[31] |= 64
        return d
    }

    /// Public key of a 32-byte secret seed.
    public static func publicKey(seed: [UInt8]) -> [UInt8] { pack(scalarbase(Array(expand(seed)[0..<32]))) }

    /// New key pair from the system's cryptographic random generator.
    public static func generateSeed() -> [UInt8] {
        var g = SystemRandomNumberGenerator()
        return (0..<32).map { _ in UInt8.random(in: 0...255, using: &g) }
    }

    /// 64-byte signature of a message.
    public static func sign(_ msg: [UInt8], seed: [UInt8]) -> [UInt8] {
        let d = expand(seed)
        let pk = pack(scalarbase(Array(d[0..<32])))
        let r = reduce(SHA512.hash(Array(d[32..<64]) + msg))
        let R = pack(scalarbase(r))
        let h = reduce(SHA512.hash(R + pk + msg))
        var x = [Int64](repeating: 0, count: 64)
        for i in 0..<32 { x[i] = Int64(r[i]) }
        for i in 0..<32 { for j in 0..<32 { x[i + j] = x[i + j] &+ Int64(h[i]) &* Int64(d[j]) } }
        return R + modL(&x)
    }

    static func unpackneg(_ p: [UInt8]) -> [GF]? {
        var r = [gf(), gf(), gf1, gf()]
        r[1] = unpack25519(p)
        var num = S(r[1])
        var den = M(num, D)
        num = Z(num, r[2]); den = A(r[2], den)
        let den2 = S(den), den4 = S(den2), den6 = M(den4, den2)
        var t = M(M(den6, num), den)
        t = pow2523(t); t = M(M(M(t, num), den), den)
        r[0] = M(t, den)
        var chk = M(S(r[0]), den)
        if neq(chk, num) { r[0] = M(r[0], I) }
        chk = M(S(r[0]), den)
        if neq(chk, num) { return nil }
        if par(r[0]) == Int64(p[31] >> 7) { r[0] = Z(gf0, r[0]) }
        r[3] = M(r[0], r[1])
        return r
    }

    /// Whether `sig` is a valid signature of `msg` by `publicKey`.
    public static func verify(_ msg: [UInt8], signature sig: [UInt8], publicKey pk: [UInt8]) -> Bool {
        guard sig.count == 64, pk.count == 32, var q = unpackneg(pk) else { return false }
        // S must be reduced (s < L): reject malleable signatures.
        let s = Array(sig[32..<64])
        guard reduce(s + [UInt8](repeating: 0, count: 32)) == s else { return false }
        let h = reduce(SHA512.hash(Array(sig[0..<32]) + pk + msg))
        var p = scalarmult(q, h)
        q = scalarbase(s)
        add(&p, q)
        return pack(p) == Array(sig[0..<32])
    }
}

public enum FileSignature {
    public struct SignatureError: Error, LocalizedError { public var message: String; public var errorDescription: String? { message } }

    public struct Key: Codable, Hashable {
        public var signer: String
        /// Base64 of the 32-byte secret seed and of the public key.
        public var seed: String
        public var publicKey: String
        public var created: String
    }
    public struct Record: Codable, Hashable {
        public var format = "archi-signature-1"
        public var algorithm = "Ed25519"
        public var file: String
        public var size: Int
        public var sha256: String
        public var signer: String
        public var publicKey: String
        public var signedAt: String
        public var signature: String
    }
    public enum Status: Equatable {
        case valid(signer: String, trusted: Bool)
        case modified
        case invalid
        case missing
    }

    public static func newKey(signer: String, now: Date = Date()) -> Key {
        let seed = Ed25519.generateSeed()
        return Key(signer: signer, seed: Data(seed).base64EncodedString(), publicKey: Data(Ed25519.publicKey(seed: seed)).base64EncodedString(),
                   created: ISO8601DateFormatter().string(from: now))
    }
    /// Default key file: ~/Library/Application Support/Oanarina Archi Tool/signing-key.json.
    public static var defaultKeyURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Oanarina Archi Tool/signing-key.json")
    }
    public static func saveKey(_ k: Key, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(k).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func loadKey(_ url: URL) throws -> Key {
        guard let d = try? Data(contentsOf: url), let k = try? JSONDecoder().decode(Key.self, from: d) else {
            throw SignatureError(message: "No signing key at \(url.path) (create one with SIGNKEY).")
        }
        return k
    }

    /// Canonical signed message of a record.
    static func message(_ r: Record) -> [UInt8] {
        Array("\(r.format)\n\(r.algorithm)\n\(r.file)\n\(r.size)\n\(r.sha256)\n\(r.signer)\n\(r.publicKey)\n\(r.signedAt)".utf8)
    }

    public static func sign(_ data: Data, name: String, key: Key, now: Date = Date()) throws -> Record {
        guard let seed = Data(base64Encoded: key.seed), seed.count == 32 else { throw SignatureError(message: "The signing key is damaged.") }
        var r = Record(file: name, size: data.count, sha256: UpdateCheck.sha256(data), signer: key.signer,
                       publicKey: Data(Ed25519.publicKey(seed: [UInt8](seed))).base64EncodedString(),
                       signedAt: ISO8601DateFormatter().string(from: now), signature: "")
        r.signature = Data(Ed25519.sign(message(r), seed: [UInt8](seed))).base64EncodedString()
        return r
    }

    public static func verify(_ data: Data, record r: Record, trusted: Set<String> = []) -> Status {
        guard let sig = Data(base64Encoded: r.signature), let pk = Data(base64Encoded: r.publicKey),
              Ed25519.verify(message(r), signature: [UInt8](sig), publicKey: [UInt8](pk)) else { return .invalid }
        guard data.count == r.size, UpdateCheck.sha256(data) == r.sha256 else { return .modified }
        return .valid(signer: r.signer, trusted: trusted.contains(r.publicKey))
    }

    public static func signatureURL(for url: URL) -> URL { url.appendingPathExtension("sig") }

    /// Signs a file, writing "<file>.sig".
    @discardableResult
    public static func signFile(_ url: URL, key: Key) throws -> Record {
        guard let data = try? Data(contentsOf: url) else { throw SignatureError(message: "Cannot read \(url.path)") }
        let r = try sign(data, name: url.lastPathComponent, key: key)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(r).write(to: signatureURL(for: url), options: .atomic)
        return r
    }

    public static func verifyFile(_ url: URL, trusted: Set<String> = []) -> (Status, Record?) {
        guard let sd = try? Data(contentsOf: signatureURL(for: url)), let r = try? JSONDecoder().decode(Record.self, from: sd) else { return (.missing, nil) }
        guard let data = try? Data(contentsOf: url) else { return (.modified, r) }
        return (verify(data, record: r, trusted: trusted), r)
    }

    static func trusted(_ doc: ArchiDocument) -> Set<String> {
        Set((doc.variable("TRUSTEDSIGNERS") ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static var commands: [CommandDef] { [signKey, signFileCmd, verifyCmd, trustCmd] }

    static var signKey: CommandDef {
        CommandDef("SIGNKEY", aliases: ["SIGNINGKEY", "NEWSIGNKEY"], category: "Collaborate",
                   summary: "Creates (or shows) your Ed25519 signing key, kept in Application Support; prints the public key others add to TRUSTEDSIGNERS.", modifies: false) { ed in
            let url = defaultKeyURL
            if let k = try? loadKey(url), try await ed.getKeyword("A signing key exists for \(k.signer). [Keep/New]", ["Keep", "New"], defaultValue: "Keep") != "New" {
                ed.print("Signer: \(k.signer)\nPublic key: \(k.publicKey)"); return
            }
            let name = try await ed.getWord("Signer name <\(ed.doc.info.author.isEmpty ? "Architect" : ed.doc.info.author)>")
            let k = newKey(signer: (name?.isEmpty ?? true) ? (ed.doc.info.author.isEmpty ? "Architect" : ed.doc.info.author) : name!)
            do { try saveKey(k, to: url) } catch { throw CommandError.invalid("Cannot save the key: \(error.localizedDescription)") }
            ed.print("New signing key for \(k.signer) saved to \(url.path).\nPublic key: \(k.publicKey)")
        }
    }
    static var signFileCmd: CommandDef {
        CommandDef("SIGNFILE", aliases: ["SIGNDOC", "DIGITALSIGN", "SIGN"], category: "Collaborate",
                   summary: "Signs a file (PDF, DWG, IFC, the drawing…) with your key: writes a detached <file>.sig with the signer, time, SHA-256 and Ed25519 signature.", modifies: false) { ed in
            let def = ed.fileURL?.lastPathComponent ?? ""
            let p = try await ed.getWord("Enter file to sign" + (def.isEmpty ? "" : " <\(def)>"))
            let url = (p?.isEmpty ?? true) ? ed.fileURL : IOCommands.resolve(ed, p!)
            guard let url else { throw CommandError.invalid("A file name is required.") }
            let key: Key
            do { key = try loadKey(defaultKeyURL) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "No signing key.") }
            do {
                let r = try signFile(url, key: key)
                ed.print("Signed \(url.lastPathComponent) as \(r.signer) (SHA-256 \(r.sha256.prefix(16))…); signature in \(signatureURL(for: url).lastPathComponent).")
            } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
        }
    }
    static var verifyCmd: CommandDef {
        CommandDef("VERIFYSIGNATURE", aliases: ["CHECKSIGNATURE", "SIGVERIFY"], category: "Collaborate",
                   summary: "Checks a file against its <file>.sig: valid signature, unchanged content, and whether the signer is trusted (TRUSTEDSIGNERS).", modifies: false) { ed in
            let url = try await IOCommands.path(ed, "Enter signed file")
            let (st, r) = verifyFile(url, trusted: trusted(ed.doc))
            switch st {
            case .missing: ed.print("\(url.lastPathComponent) has no signature (\(signatureURL(for: url).lastPathComponent) not found).")
            case .invalid: ed.print("INVALID: the signature of \(url.lastPathComponent) does not verify.")
            case .modified: ed.print("MODIFIED: \(url.lastPathComponent) changed after \(r?.signer ?? "the signer") signed it on \(r?.signedAt ?? "?").")
            case .valid(let s, let t): ed.print("Valid signature by \(s) on \(r?.signedAt ?? "?")" + (t ? " (trusted signer)." : " — the signer's key is not in TRUSTEDSIGNERS."))
            }
        }
    }
    static var trustCmd: CommandDef {
        CommandDef("TRUSTSIGNER", aliases: ["TRUSTKEY", "TRUSTEDSIGNERS"], category: "Collaborate",
                   summary: "Adds a signer's public key (or the key of a .sig file) to the drawing's trusted signers.") { ed in
            guard let w = try await ed.getWord("Enter public key or .sig file"), !w.isEmpty else { return }
            var key = w
            if w.lowercased().hasSuffix(".sig") {
                guard let d = try? Data(contentsOf: IOCommands.resolve(ed, w)), let r = try? JSONDecoder().decode(Record.self, from: d) else { throw CommandError.invalid("Cannot read \(w).") }
                key = r.publicKey
            }
            guard let raw = Data(base64Encoded: key), raw.count == 32 else { throw CommandError.invalid("Not an Ed25519 public key (32 bytes, base64).") }
            var t = trusted(ed.doc); t.insert(key)
            ed.doc.setVariable("TRUSTEDSIGNERS", t.sorted().joined(separator: ";"))
            ed.print("\(t.count) trusted signer key(s).")
        }
    }
}
