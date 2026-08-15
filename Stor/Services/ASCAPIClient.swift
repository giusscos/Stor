import Foundation
import CryptoKit

// MARK: - Response types

struct ASCPagedResponse<T: Codable>: Codable {
    let data: [T]
    let links: Links?

    struct Links: Codable {
        let next: String?
    }
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

    /// States in which App Store Connect still accepts metadata edits. Versions
    /// outside this set (READY_FOR_SALE, IN_REVIEW, …) reject PATCH requests.
    static let editableStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "INVALID_BINARY"
    ]

    var isEditable: Bool {
        Self.editableStates.contains(attributes.appStoreState)
    }

    /// Short label for pickers and badges.
    var displayState: String {
        Self.displayName(for: attributes.appStoreState)
    }

    static func displayName(for state: String) -> String {
        switch state {
        case "PREPARE_FOR_SUBMISSION": return "Prepare for Submission"
        case "DEVELOPER_REJECTED": return "Developer Rejected"
        case "REJECTED": return "Rejected"
        case "METADATA_REJECTED": return "Metadata Rejected"
        case "INVALID_BINARY": return "Invalid Binary"
        case "READY_FOR_SALE": return "Ready for Sale"
        case "IN_REVIEW": return "In Review"
        case "WAITING_FOR_REVIEW": return "Waiting for Review"
        case "PENDING_DEVELOPER_RELEASE": return "Pending Release"
        case "PROCESSING_FOR_APP_STORE": return "Processing"
        case "REPLACED_WITH_NEW_VERSION": return "Replaced"
        case "DEVELOPER_REMOVED_FROM_SALE": return "Removed from Sale"
        case "REMOVED_FROM_SALE": return "Removed from Sale"
        default:
            return state
                .replacingOccurrences(of: "_", with: " ")
                .localizedCapitalized
        }
    }

    /// Numeric components of `versionString`, for ordering releases like 1.10.0 above 1.9.0.
    var versionComponents: [Int] {
        attributes.versionString
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    static func isDescending(_ lhs: ASCAppStoreVersion, _ rhs: ASCAppStoreVersion) -> Bool {
        let l = lhs.versionComponents, r = rhs.versionComponents
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a > b }
        }
        return lhs.attributes.versionString > rhs.attributes.versionString
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
        let fileName: String?
        let fileSize: Int?
        let sourceFileChecksum: String?
        let imageAsset: ImageAsset?
        let displayPosition: Int?
        let uploaded: Bool?
        let assetDeliveryState: AssetDeliveryState?
        let uploadOperations: [UploadOperation]?

        struct ImageAsset: Codable {
            let templateUrl: String?
            let width: Int?
            let height: Int?

            /// Preview URL with `{w}` `{h}` `{f}` placeholders filled in.
            func previewURL(maxEdge: Int = 400) -> URL? {
                guard var template = templateUrl, !template.isEmpty else { return nil }
                let width = self.width ?? maxEdge
                let height = self.height ?? maxEdge
                let scale = min(1, Double(maxEdge) / Double(max(width, height)))
                let w = max(1, Int(Double(width) * scale))
                let h = max(1, Int(Double(height) * scale))
                template = template
                    .replacingOccurrences(of: "{w}", with: "\(w)")
                    .replacingOccurrences(of: "{h}", with: "\(h)")
                    .replacingOccurrences(of: "{f}", with: "png")
                return URL(string: template)
            }
        }

        struct AssetDeliveryState: Codable {
            let state: String?
        }

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

    var position: Int { attributes.displayPosition ?? .max }
}

// MARK: - Error

/// App Store Connect's JSON:API error envelope, e.g. `{"errors":[{"title":...,"detail":...}]}`.
private struct ASCErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let title: String?
        let detail: String?
    }
    let errors: [APIError]?
}

enum ASCAPIError: LocalizedError {
    case noVersionsFound
    case versionNotFound(String)
    case httpError(Int, String)
    case rateLimited
    case decodingError(Error)
    case incompleteUpload

    var errorDescription: String? {
        switch self {
        case .noVersionsFound: return "No app versions found for this app."
        case .versionNotFound(let id): return "Version \(id) is no longer available in App Store Connect."
        case .httpError(let code, let body):
            if let data = body.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(ASCErrorEnvelope.self, from: data),
               let detail = envelope.errors?.first?.detail {
                return "HTTP \(code): \(detail)"
            }
            return "HTTP \(code): \(body.prefix(300))"
        case .rateLimited: return "App Store Connect is rate limiting requests. Try again in a few minutes."
        case .decodingError(let e): return "Response decode error: \(e.localizedDescription)"
        case .incompleteUpload: return "The screenshot upload was incomplete and was not committed."
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
        try await getAllPages(ASCApp.self, path: "/apps?limit=200&fields[apps]=bundleId,name,primaryLocale")
    }

    /// All iOS versions, newest first, with editable versions ordered ahead of shipped ones.
    func fetchVersions(appId: String) async throws -> [ASCAppStoreVersion] {
        let versions = try await getAllPages(
            ASCAppStoreVersion.self,
            path: "/apps/\(appId)/appStoreVersions?filter[platform]=IOS&limit=50"
        )
        return versions.sorted { lhs, rhs in
            if lhs.isEditable != rhs.isEditable { return lhs.isEditable }
            return ASCAppStoreVersion.isDescending(lhs, rhs)
        }
    }

    func fetchVersionLocalizations(versionId: String) async throws -> [ASCVersionLocalization] {
        try await getAllPages(
            ASCVersionLocalization.self,
            path: "/appStoreVersions/\(versionId)/appStoreVersionLocalizations?limit=50"
        )
    }

    func fetchAppInfoLocalizations(appId: String) async throws -> [ASCAppInfoLocalization] {
        let infos = try await getAllPages(ASCAppInfo.self, path: "/apps/\(appId)/appInfos?limit=50")

        var result: [ASCAppInfoLocalization] = []
        for info in infos {
            result += try await getAllPages(
                ASCAppInfoLocalization.self,
                path: "/appInfos/\(info.id)/appInfoLocalizations?limit=50"
            )
        }
        return result
    }

    struct MetadataSyncResult {
        let version: ASCAppStoreVersion?
        let versionLocalizations: [ASCVersionLocalization]
        let appInfoLocalizations: [ASCAppInfoLocalization]
    }

    /// Syncs metadata for `versionId`, or for the version App Store Connect would let
    /// you edit today when no version is specified.
    func syncMetadata(appId: String, versionId: String? = nil) async throws -> MetadataSyncResult {
        async let versions = fetchVersions(appId: appId)
        async let infoLocs = fetchAppInfoLocalizations(appId: appId)

        let (fetchedVersions, fetchedInfoLocs) = try await (versions, infoLocs)
        guard !fetchedVersions.isEmpty else { throw ASCAPIError.noVersionsFound }

        let targetVersion: ASCAppStoreVersion?
        if let versionId {
            guard let match = fetchedVersions.first(where: { $0.id == versionId }) else {
                throw ASCAPIError.versionNotFound(versionId)
            }
            targetVersion = match
        } else {
            // fetchVersions sorts editable versions first, so this prefers the draft
            // over whatever is already live.
            targetVersion = fetchedVersions.first
        }

        var versionLocs: [ASCVersionLocalization] = []
        if let v = targetVersion {
            versionLocs = try await fetchVersionLocalizations(versionId: v.id)
        }

        return MetadataSyncResult(
            version: targetVersion,
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

        // 5. Upload to each operation URL provided by ASC. Every byte must land before
        //    the commit below, so a chunk we cannot send is a hard failure rather than
        //    something to skip — committing a partial upload marks it valid in ASC.
        guard let operations = screenshot.attributes.uploadOperations, !operations.isEmpty else {
            throw ASCAPIError.incompleteUpload
        }
        var uploadedBytes = 0
        for op in operations {
            guard let url = URL(string: op.url),
                  op.offset >= 0,
                  op.length > 0,
                  op.offset + op.length <= data.count
            else { throw ASCAPIError.incompleteUpload }

            var req = URLRequest(url: url)
            req.httpMethod = op.method
            req.httpBody = data.subdata(in: op.offset..<(op.offset + op.length))
            op.requestHeaders?.forEach { req.setValue($0.value, forHTTPHeaderField: $0.name) }

            let (_, uploadResponse) = try await URLSession.shared.data(for: req)
            if let http = uploadResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ASCAPIError.httpError(http.statusCode, "Screenshot chunk upload failed")
            }
            uploadedBytes += op.length
        }
        guard uploadedBytes == data.count else { throw ASCAPIError.incompleteUpload }

        // 6. Commit — tell ASC the upload is complete
        let commitBody: [String: Any] = ["data": [
            "type": "appScreenshots",
            "id": screenshot.id,
            "attributes": ["sourceFileChecksum": checksum, "uploaded": true]
        ]]
        try await patch("/appScreenshots/\(screenshot.id)", body: commitBody)
    }

    // MARK: - Screenshot sets

    func fetchScreenshotSets(localizationId: String) async throws -> [ASCScreenshotSet] {
        try await getAllPages(
            ASCScreenshotSet.self,
            path: "/appStoreVersionLocalizations/\(localizationId)/appScreenshotSets?limit=50"
        )
    }

    func fetchScreenshots(setId: String) async throws -> [ASCScreenshot] {
        let screenshots = try await getAllPages(
            ASCScreenshot.self,
            path: "/appScreenshotSets/\(setId)/appScreenshots?limit=50&fields[appScreenshots]=fileName,fileSize,sourceFileChecksum,imageAsset,displayPosition,uploaded,assetDeliveryState"
        )
        return screenshots.sorted { $0.position < $1.position }
    }

    func updateScreenshotPosition(id: String, position: Int) async throws {
        let body: [String: Any] = ["data": [
            "type": "appScreenshots",
            "id": id,
            "attributes": ["displayPosition": position]
        ]]
        try await patch("/appScreenshots/\(id)", body: body)
    }

    func deleteScreenshot(id: String) async throws {
        try await delete("/appScreenshots/\(id)")
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
        let responseData = try await send(request)
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
        let responseData = try await send(request)
        return try decode(ASCSingleResponse<ASCScreenshot>.self, from: responseData).data
    }

    private func md5Hex(of data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
    }

    private func delete(_ path: String) async throws {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(try jwt.generateToken(credentials: credentials))", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    private func patch(_ path: String, body: [String: Any]) async throws {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try jwt.generateToken(credentials: credentials))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(request)
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        return try await get(url: url)
    }

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try jwt.generateToken(credentials: credentials))", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    /// Follows `links.next` until App Store Connect stops paging. The page cap is a
    /// safety net against a malformed `next` that points back at itself.
    private func getAllPages<T: Codable>(_ type: T.Type, path: String) async throws -> [T] {
        guard var next = URL(string: base + path) else { throw URLError(.badURL) }

        var results: [T] = []
        var seen = Set<String>()
        for _ in 0..<Self.maxPages {
            guard seen.insert(next.absoluteString).inserted else { break }

            let page = try decode(ASCPagedResponse<T>.self, from: try await get(url: next))
            results.append(contentsOf: page.data)

            guard let link = page.links?.next, let url = URL(string: link) else { break }
            next = url
        }
        return results
    }

    /// Sends a request, retrying on 429 and 5xx with exponential backoff.
    private func send(_ request: URLRequest) async throws -> Data {
        var lastStatus = 0
        var lastBody = ""

        for attempt in 0..<Self.maxAttempts {
            if attempt > 0 {
                try await Task.sleep(for: Self.backoff(forAttempt: attempt))
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return data }
            if (200..<300).contains(http.statusCode) { return data }

            lastStatus = http.statusCode
            lastBody = String(data: data, encoding: .utf8) ?? ""

            let retryable = http.statusCode == 429 || (500..<600).contains(http.statusCode)
            guard retryable else { throw ASCAPIError.httpError(lastStatus, lastBody) }
        }

        throw lastStatus == 429 ? ASCAPIError.rateLimited : ASCAPIError.httpError(lastStatus, lastBody)
    }

    private static let maxPages = 50
    private static let maxAttempts = 4

    private static func backoff(forAttempt attempt: Int) -> Duration {
        let seconds = pow(2.0, Double(attempt - 1))
        let jitter = Double.random(in: 0...0.3)
        return .seconds(seconds + jitter)
    }

    private func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ASCAPIError.decodingError(error)
        }
    }
}
