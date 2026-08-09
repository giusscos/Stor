import Foundation
import CryptoKit

final class ASCJWTGenerator {
    /// Apple caps App Store Connect tokens at 20 minutes. We reuse a token until it is
    /// close to expiry so a batch push does not re-sign on every request.
    private static let lifetime: TimeInterval = 1200
    private static let refreshMargin: TimeInterval = 120

    private var cachedToken: String?
    private var cachedKey: String?
    private var cachedExpiry: Date?

    func generateToken(credentials: ASCCredentials) throws -> String {
        let key = "\(credentials.issuerId)|\(credentials.keyId)"
        if let cachedToken, cachedKey == key, let cachedExpiry,
           Date() < cachedExpiry.addingTimeInterval(-Self.refreshMargin) {
            return cachedToken
        }

        let token = try signToken(credentials: credentials)
        cachedToken = token
        cachedKey = key
        cachedExpiry = Date().addingTimeInterval(Self.lifetime)
        return token
    }

    private func signToken(credentials: ASCCredentials) throws -> String {
        let now = Date()
        let expiry = now.addingTimeInterval(Self.lifetime)

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
