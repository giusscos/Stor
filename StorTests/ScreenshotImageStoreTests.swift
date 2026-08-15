import Foundation
import Testing
@testable import AscendKit

/// Layer images are content-addressed so that re-importing the same screenshot doesn't
/// duplicate megabytes on disk, and so editing a layer rewrites only a digest.
@MainActor
struct ScreenshotImageStoreTests {
    private func makeStore() -> (ScreenshotImageStore, URL) {
        let directory = URL.temporaryDirectory
            .appendingPathComponent("StorTests-\(UUID().uuidString)", isDirectory: true)
        return (ScreenshotImageStore(directory: directory), directory)
    }

    private func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func storedDataCanBeReadBack() {
        let (store, directory) = makeStore()
        defer { cleanUp(directory) }

        let data = Data("screenshot bytes".utf8)
        let ref = store.store(data)

        #expect(store.data(for: ref) == data)
    }

    @Test func identicalBytesShareOneFile() {
        let (store, directory) = makeStore()
        defer { cleanUp(directory) }

        let first = store.store(Data("same".utf8))
        let second = store.store(Data("same".utf8))

        #expect(first == second)
        let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files?.count == 1)
    }

    @Test func differentBytesGetDifferentReferences() {
        let (store, directory) = makeStore()
        defer { cleanUp(directory) }

        #expect(store.store(Data("a".utf8)) != store.store(Data("b".utf8)))
    }

    @Test func referenceIsTheSHA256Digest() {
        // Digest of the empty input, which pins the hash function and hex formatting.
        #expect(
            ScreenshotImageStore.reference(for: Data())
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test func unknownReferenceReturnsNilRatherThanThrowing() {
        let (store, directory) = makeStore()
        defer { cleanUp(directory) }

        #expect(store.data(for: "0000000000000000000000000000000000000000000000000000000000000000") == nil)
    }

    @Test func pruningRemovesOnlyUnreferencedFiles() {
        let (store, directory) = makeStore()
        defer { cleanUp(directory) }

        let kept = store.store(Data("keep".utf8))
        let dropped = store.store(Data("drop".utf8))

        store.pruneUnreferenced(keeping: [kept])

        #expect(store.data(for: kept) == Data("keep".utf8))
        #expect(store.data(for: dropped) == nil)
    }

    @Test func pruningWithNoReferencesEmptiesTheStore() {
        let (store, directory) = makeStore()
        defer { cleanUp(directory) }

        store.store(Data("one".utf8))
        store.store(Data("two".utf8))

        store.pruneUnreferenced(keeping: [])

        let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files?.isEmpty == true)
    }

    /// Layers must persist only the digest; re-encoding image bytes on every property
    /// edit is what made the editor slow before.
    @Test func layerEncodingCarriesTheReferenceNotTheBytes() throws {
        var layer = ScreenshotLayer(type: .image)
        layer.imageData = Data("pretend png".utf8)
        let ref = try #require(layer.imageRef)

        let encoded = try JSONEncoder().encode(layer)
        let json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(json["imageRef"] as? String == ref)
        #expect(json["imageData"] == nil)
        #expect(encoded.count < 2000)
    }

    @Test func legacyInlineImageDataIsMigratedIntoTheStore() throws {
        let bytes = Data("legacy png".utf8)
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "type": "image",
          "xFraction": 0.1, "yFraction": 0.1,
          "widthFraction": 0.8, "heightFraction": 0.4,
          "isVisible": true,
          "imageCornerRadius": 0, "imageFills": false,
          "contentScale": 1, "contentOffsetX": 0, "contentOffsetY": 0,
          "translations": {},
          "fontSizePt": 40, "colorHex": "#FFFFFF", "isBold": true,
          "fontFamily": "System", "fontWeightRaw": "bold", "isItalic": false,
          "tracking": 0, "alignmentRaw": "center",
          "textPaddingPt": 12, "textCornerRadiusPt": 20,
          "textUsesMarkdown": true,
          "fitWidthToContent": false, "fitHeightToContent": false,
          "imageData": "\(bytes.base64EncodedString())"
        }
        """

        var layers = [try JSONDecoder().decode(ScreenshotLayer.self, from: Data(json.utf8))]
        #expect(layers[0].imageData == bytes)

        let changed = ScreenshotLayer.migrateEmbeddedImages(in: &layers)

        #expect(changed)
        #expect(layers[0].imageRef == ScreenshotImageStore.reference(for: bytes))
        #expect(layers[0].imageData == bytes)
    }

    @Test func migratingAlreadyMigratedLayersReportsNoChange() {
        var layers = [ScreenshotLayer(type: .image)]
        #expect(ScreenshotLayer.migrateEmbeddedImages(in: &layers) == false)
    }
}
