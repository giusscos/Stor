import CryptoKit
import Foundation
import Testing
@testable import Stor

/// A malformed token fails every App Store Connect call with an opaque 401, so the
/// structure and signature are verified here against a throwaway key.
struct ASCJWTGeneratorTests {
    private let key = P256.Signing.PrivateKey()

    private func credentials(issuer: String = "69a6de70-0000-0000-0000-000000000001",
                             keyId: String = "ABC123DEFG") -> ASCCredentials {
        ASCCredentials(
            name: "Test",
            issuerId: issuer,
            keyId: keyId,
            privateKeyPEM: key.pemRepresentation
        )
    }

    private func segments(_ token: String) throws -> (header: [String: Any], payload: [String: Any]) {
        let parts = token.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        return (try decode(parts[0]), try decode(parts[1]))
    }

    private func decode(_ segment: String) throws -> [String: Any] {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        let data = try #require(Data(base64Encoded: base64))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func headerIdentifiesTheSigningKey() throws {
        let token = try ASCJWTGenerator().generateToken(credentials: credentials())
        let header = try segments(token).header

        #expect(header["alg"] as? String == "ES256")
        #expect(header["typ"] as? String == "JWT")
        #expect(header["kid"] as? String == "ABC123DEFG")
    }

    @Test func payloadTargetsAppStoreConnectAndExpiresWithinApplesLimit() throws {
        let token = try ASCJWTGenerator().generateToken(credentials: credentials())
        let payload = try segments(token).payload

        #expect(payload["aud"] as? String == "appstoreconnect-v1")
        #expect(payload["iss"] as? String == "69a6de70-0000-0000-0000-000000000001")

        let issuedAt = try #require(payload["iat"] as? Int)
        let expiry = try #require(payload["exp"] as? Int)
        // Apple rejects tokens whose lifetime exceeds 20 minutes.
        #expect(expiry - issuedAt <= 1200)
        #expect(expiry > issuedAt)
    }

    @Test func signatureVerifiesAgainstThePublicKey() throws {
        let token = try ASCJWTGenerator().generateToken(credentials: credentials())
        let parts = token.split(separator: ".").map(String.init)

        var base64 = parts[2]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        let raw = try #require(Data(base64Encoded: base64))

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: raw)
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)

        #expect(key.publicKey.isValidSignature(signature, for: signingInput))
    }

    @Test func base64URLEncodingHasNoPaddingOrURLUnsafeCharacters() throws {
        let token = try ASCJWTGenerator().generateToken(credentials: credentials())

        #expect(!token.contains("="))
        #expect(!token.contains("+"))
        #expect(!token.contains("/"))
    }

    @Test func tokenIsReusedForTheSameAccount() throws {
        let generator = ASCJWTGenerator()
        let account = credentials()

        let first = try generator.generateToken(credentials: account)
        let second = try generator.generateToken(credentials: account)

        #expect(first == second)
    }

    /// Switching accounts must re-sign; reusing the previous token would authenticate the
    /// request as the wrong team.
    @Test func tokenIsRegeneratedWhenTheAccountChanges() throws {
        let generator = ASCJWTGenerator()

        let first = try generator.generateToken(credentials: credentials())
        let second = try generator.generateToken(
            credentials: credentials(issuer: "11111111-2222-3333-4444-555555555555", keyId: "ZZZ999")
        )

        #expect(first != second)
        #expect(try segments(second).header["kid"] as? String == "ZZZ999")
    }

    @Test func invalidPEMThrowsInsteadOfProducingAToken() {
        let bad = ASCCredentials(issuerId: "issuer", keyId: "key", privateKeyPEM: "not a pem")

        #expect(throws: (any Error).self) {
            try ASCJWTGenerator().generateToken(credentials: bad)
        }
    }
}
