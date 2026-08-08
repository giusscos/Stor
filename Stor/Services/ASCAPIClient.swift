import Foundation
import CryptoKit

// MARK: - Response types

struct ASCPagedResponse<T: Codable>: Codable {
    let data: [T]
}

struct ASCSingleResponse<T: Codable>: Codable {
    let data: T
}

struct ASCApp: Codable, Identifiable, Hashable {
    let id: String
    let attributes: Attributes

    struct Attributes: Codable, Hashable {
        let bundleId: String
        let name: String
        let primaryLocale: String
    }
}

struct ASCAppStoreVersion: Codable {
    let id: String
    let attributes: Attributes

    struct Attributes: Codable {
        let versionString: String
        let appStoreState: String
        let platform: String
    }
}

struct ASCVersionLocalization: Codable {
    let id: String
    let attributes: Attributes

    struct Attributes: Codable {
        let locale: String
        let description: String?
        let keywords: String?
        let promotionalText: String?
        let whatsNew: String?
    }
}

struct ASCAppInfo: Codable {
    let id: String
}

struct ASCAppInfoLocalization: Codable {
    let id: String
    let attributes: Attributes

    struct Attributes: Codable {
        let locale: String
        let name: String?
        let subtitle: String?
    }
}

struct ASCScreenshotSet: Codable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Codable {
        let screenshotDisplayType: String
    }
}

struct ASCScreenshot: Codable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Codable {
        let uploadOperations: [UploadOperation]?

        struct UploadOperation: Codable {
            let method: String
            let url: String
            let offset: Int
            let length: Int
            let requestHeaders: [RequestHeader]?

            struct RequestHeader: Codable {
                let name: String
                let value: String
            }
        }
    }
}

// MARK: - Error

enum ASCAPIError: LocalizedError {
    case noVersionsFound
    case httpError(Int, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .noVersionsFound: return "No app versions found for this app."
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .decodingError(let e): return "Response decode error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Client

final class ASCAPIClient {
    private let base = "https://api.appstoreconnect.apple.com/v1"
    private let credentials: ASCCredentials
    private let jwt = ASCJWTGenerator()

    init(credentials: ASCCredentials) {
        self.credentials = credentials
    }

    // MARK: Public API

    func fetchApps() async throws -> [ASCApp] {
        let data = try await get("/apps?limit=200&fields[apps]=bundleId,name,primaryLocale")
        return try decode(ASCPagedResponse<ASCApp>.self, from: data).data
    }

    func fetchVersions(appId: String) async throws -> [ASCAppStoreVersion] {
        let data = try await get("/apps/\(appId)/appStoreVersions?filter[platform]=IOS&limit=5")
        return try decode(ASCPagedResponse<ASCAppStoreVersion>.self, from: data).data
    }

    func fetchVersionLocalizations(versionId: String) async throws -> [ASCVersionLocalization] {
        let data = try await get("/appStoreVersions/\(versionId)/appStoreVersionLocalizations?limit=50")
        return try decode(ASCPagedResponse<ASCVersionLocalization>.self, from: data).data
    }

    func fetchAppInfoLocalizations(appId: String) async throws -> [ASCAppInfoLocalization] {
        let infosData = try await get("/apps/\(appId)/appInfos?limit=5")
        let infos = try decode(ASCPagedResponse<ASCAppInfo>.self, from: infosData).data

        var result: [ASCAppInfoLocalization] = []
        for info in infos {
            let locsData = try await get("/appInfos/\(info.id)/appInfoLocalizations?limit=50")
            let locs = try decode(ASCPagedResponse<ASCAppInfoLocalization>.self, from: locsData).data
            result.append(contentsOf: locs)
        }
        return result
    }

    struct MetadataSyncResult {
        let version: ASCAppStoreVersion?
        let versionLocalizations: [ASCVersionLocalization]
        let appInfoLocalizations: [ASCAppInfoLocalization]
    }

    func syncMetadata(appId: String) async throws -> MetadataSyncResult {
        async let versions = fetchVersions(appId: appId)
        async let infoLocs = fetchAppInfoLocalizations(appId: appId)

        let (fetchedVersions, fetchedInfoLocs) = try await (versions, infoLocs)
        let latestVersion = fetchedVersions.first

        var versionLocs: [ASCVersionLocalization] = []
        if let v = latestVersion {
            versionLocs = try await fetchVersionLocalizations(versionId: v.id)
        }

        return MetadataSyncResult(
            version: latestVersion,
            versionLocalizations: versionLocs,
            appInfoLocalizations: fetchedInfoLocs
        )
    }

    // MARK: - Write (PATCH)

    func updateVersionLocalization(
        id: String,
        description: String?,
        keywords: String?,
        promotionalText: String?,
        whatsNew: String?
    ) async throws {
        var attrs: [String: Any] = [:]
        if let v = description      { attrs["description"]     = v }
        if let v = keywords         { attrs["keywords"]         = v }
        if let v = promotionalText  { attrs["promotionalText"] = v }
        if let v = whatsNew         { attrs["whatsNew"]         = v }
        let body: [String: Any] = ["data": ["type": "appStoreVersionLocalizations", "id": id, "attributes": attrs]]
        try await patch("/appStoreVersionLocalizations/\(id)", body: body)
    }

    func updateAppInfoLocalization(id: String, name: String?, subtitle: String?) async throws {
        var attrs: [String: Any] = [:]
        if let v = name     { attrs["name"]     = v }
        if let v = subtitle { attrs["subtitle"] = v }
        let body: [String: Any] = ["data": ["type": "appInfoLocalizations", "id": id, "attributes": attrs]]
        try await patch("/appInfoLocalizations/\(id)", body: body)
    }

    // MARK: - Screenshot upload

    /// Full screenshot upload flow: get/create screenshot set → reserve slot → upload → commit.
    func uploadScreenshot(
        data: Data,
        fileName: String,
        versionLocalizationId: String,
        screenshotDisplayType: String
    ) async throws {
        // 1. Get existing screenshot sets for this localization
        let setsData = try await get("/appStoreVersionLocalizations/\(versionLocalizationId)/appScreenshotSets")
        let sets = try decode(ASCPagedResponse<ASCScreenshotSet>.self, from: setsData).data

        // 2. Find or create the set for this display type
        let setId: String
        if let existing = sets.first(where: { $0.attributes.screenshotDisplayType == screenshotDisplayType }) {
            setId = existing.id
        } else {
            setId = try await createScreenshotSet(localizationId: versionLocalizationId, displayType: screenshotDisplayType)
        }

        // 3. Compute MD5 checksum for commit step
        let checksum = md5Hex(of: data)

        // 4. Reserve a screenshot slot
        let screenshot = try await reserveScreenshot(screenshotSetId: setId, fileName: fileName, fileSize: data.count)

        // 5. Upload to each operation URL provided by ASC
        if let operations = screenshot.attributes.uploadOperations {
            for op in operations {
                guard let url = URL(string: op.url) else { continue }
                let end = min(op.offset + op.length, data.count)
                guard end > op.offset else { continue }
                let chunk = data.subdata(in: op.offset..<end)

                var req = URLRequest(url: url)
                req.httpMethod = op.method
                req.httpBody = chunk
                op.requestHeaders?.forEach { req.setValue($0.value, forHTTPHeaderField: $0.name) }

                let (_, uploadResponse) = try await URLSession.shared.data(for: req)
                if let http = uploadResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw ASCAPIError.httpError(http.statusCode, "Screenshot chunk upload failed")
                }
            }
        }

        // 6. Commit — tell ASC the upload is complete
        let commitBody: [String: Any] = ["data": [
            "type": "appScreenshots",
            "id": screenshot.id,
            "attributes": ["sourceFileChecksum": checksum, "uploaded": true]
        ]]
        try await patch("/appScreenshots/\(screenshot.id)", body: commitBody)
    }

    // MARK: Private helpers

    private func createScreenshotSet(localizationId: String, displayType: String) async throws -> String {
        guard let url = URL(string: base + "/appScreenshotSets") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try jwt.generateToken(credentials: credentials))", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["data": [
            "type": "appScreenshotSets",
            "attributes": ["screenshotDisplayType": displayType],
            "relationships": [
                "appStoreVersionLocalization": [
                    "data": ["type": "appStoreVersionLocalizations", "id": localizationId]
                ]
            ]
        ]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (responseData, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ASCAPIError.httpError(http.statusCode, String(data: responseData, encoding: .utf8) ?? "")
        }
        return try decode(ASCSingleResponse<ASCScreenshotSet>.self, from: responseData).data.id
    }

    private func reserveScreenshot(screenshotSetId: String, fileName: String, fileSize: Int) async throws -> ASCScreenshot {
        guard let url = URL(string: base + "/appScreenshots") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try jwt.generateToken(credentials: credentials))", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["data": [
            "type": "appScreenshots",
            "attributes": ["fileName": fileName, "fileSize": fileSize],
            "relationships": [
                "appScreenshotSet": [
                    "data": ["type": "appScreenshotSets", "id": screenshotSetId]
                ]
            ]
        ]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (responseData, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ASCAPIError.httpError(http.statusCode, String(data: responseData, encoding: .utf8) ?? "")
        }
        return try decode(ASCSingleResponse<ASCScreenshot>.self, from: responseData).data
    }

    private func md5Hex(of data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
    }

    private func patch(_ path: String, body: [String: Any]) async throws {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try jwt.generateToken(credentials: credentials))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ASCAPIError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: base + path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try jwt.generateToken(credentials: credentials))", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ASCAPIError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ASCAPIError.decodingError(error)
        }
    }
}
