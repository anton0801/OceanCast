//
//  PayloadCrypto.swift
//  Ocean Cast
//
//  AES-256-GCM for the app -> API layer. The sealed box is base64 of
//  nonce(12) || ciphertext || tag(16) — the layout the server expects. The key
//  comes from the build's Info.plist and must equal the server's ATTR_PAYLOAD_KEY.
//

import Foundation
import CryptoKit

enum PayloadCrypto {
    static var isConfigured: Bool { key() != nil }

    /// Seals a JSON string, or returns nil when no key is configured (the caller
    /// then sends the body in the clear, which the server accepts outside prod).
    static func seal(_ plaintext: Data) -> String? {
        guard let key = key() else { return nil }
        do {
            let box = try AES.GCM.seal(plaintext, using: key)
            return box.combined?.base64EncodedString()
        } catch {
            return nil
        }
    }

    private static func key() -> SymmetricKey? {
        guard let hex = keyHex(), hex.count == 64, let raw = Data(hexString: hex) else { return nil }
        return SymmetricKey(data: raw)
    }

    /// Prefer an Info.plist value; fall back to the bundled BeaconKeys.plist,
    /// where the build actually keeps the key (custom Info.plist keys are not
    /// emitted by the generated-Info.plist path).
    private static func keyHex() -> String? {
        if let value = Bundle.main.object(forInfoDictionaryKey: BeaconConfig.cryptoKeyInfoPlistKey) as? String,
           !value.isEmpty {
            return value
        }
        if let url = Bundle.main.url(forResource: "BeaconKeys", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let value = dict[BeaconConfig.cryptoKeyInfoPlistKey] as? String,
           !value.isEmpty {
            return value
        }
        return nil
    }
}

private extension Data {
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = chars[index].hexDigitValue,
                  let low = chars[index + 1].hexDigitValue else { return nil }
            bytes.append(UInt8(high << 4 | low))
            index += 2
        }
        self.init(bytes)
    }
}
