import CryptoKit
import Foundation

/// RFC 6238 TOTP (6 digits, 30 s) — what the RWTH MFA token uses.
enum TOTP {
    static let period: TimeInterval = 30
    static let digits = 6

    /// Seconds left in the current window (30 ... 1).
    static func secondsRemaining(at date: Date = Date()) -> Int {
        let into = Int(date.timeIntervalSince1970) % Int(period)
        return Int(period) - into
    }

    static func code(secret: String, at date: Date = Date()) -> String? {
        guard let key = base32Decode(normalize(secret)) else { return nil }
        let counter = UInt64(date.timeIntervalSince1970 / period)
        var bigEndian = counter.bigEndian
        let message = Data(bytes: &bigEndian, count: 8)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key))
        let bytes = Array(mac)
        guard bytes.count == 20 else { return nil }
        let offset = Int(bytes[19] & 0x0f)
        let binary = (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        let value = binary & 0x7fff_ffff
        let modulo = UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", value % modulo)
    }

    /// Accepts a bare Base32 secret or a full `otpauth://` enrolment URI.
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("otpauth://"),
           let components = URLComponents(string: text) {
            if let secret = components.queryItems?.first(where: { $0.name.lowercased() == "secret" })?.value {
                text = secret
            }
        }
        return text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }

    static func base32Decode(_ input: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var lookup = [Character: UInt8]()
        for (index, character) in alphabet.enumerated() { lookup[character] = UInt8(index) }

        var output = Data()
        var buffer: UInt32 = 0
        var bits = 0

        for character in input where character != "=" {
            guard let value = lookup[character] else { return nil }
            buffer = (buffer << 5) | UInt32(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> UInt32(bits)) & 0xff))
            }
        }
        return output.isEmpty ? nil : output
    }
}
