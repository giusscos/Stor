import Foundation
import CryptoKit

final class ASCJWTGenerator {
    func generateToken(credentials: ASCCredentials) throws -> String {
        let now = Date()
        let expiry = now.addingTimeInterval(1200)

        let header = try base64URLEncode([
            "alg": "ES256",
            "kid": credentials.keyId,
            "typ": "JWT"
        ])
        let payload = try base64URLEncode([
            "iss": credentials.issuerId,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(expiry.timeIntervalSince1970),
            "aud": "appstoreconnect-v1"
        ] as [String: Any])

        let signingInput = "\(header).\(payload)"
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        let signature = try privateKey.signature(for: Data(signingInput.utf8))

        return "\(signingInput).\(signature.rawRepresentation.base64URLEncoded())"
    }

    private func base64URLEncode(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return data.base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
