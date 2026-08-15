import Foundation
import SwiftData
import Testing
@testable import AscendKit

/// App Store Connect orders uploaded screenshots by filename, and template names come from
/// user input, so naming has to stay sortable and filesystem-safe.
@MainActor
struct BatchExportNamingTests {
    private func template(_ name: String, device: DeviceType = .iPhone69) -> ScreenshotTemplate {
        ScreenshotTemplate(name: name, deviceType: device)
    }

    @Test func nameIsPrefixedWithAZeroPaddedPosition() {
        let name = BatchExportSheet.fileName(
            template: template("Hero"),
            locale: "en-US",
            index: 0,
            includeLocale: false
        )

        #expect(name.hasPrefix("01-"))
        #expect(name.hasSuffix(".png"))
    }

    @Test func positionsSortLexicographically() {
        let names = (0..<11).map {
            BatchExportSheet.fileName(template: template("Hero"), locale: "en-US", index: $0, includeLocale: false)
        }

        #expect(names == names.sorted())
    }

    @Test func localeIsIncludedOnlyWhenFilesShareAFolder() {
        let flat = BatchExportSheet.fileName(template: template("Hero"), locale: "de-DE", index: 0, includeLocale: true)
        let grouped = BatchExportSheet.fileName(template: template("Hero"), locale: "de-DE", index: 0, includeLocale: false)

        #expect(flat.contains("de-DE"))
        #expect(!grouped.contains("de-DE"))
    }

    @Test func deviceTypeIsPartOfTheName() {
        let name = BatchExportSheet.fileName(
            template: template("Hero", device: .iPadPro13),
            locale: "en-US",
            index: 0,
            includeLocale: false
        )

        #expect(name.contains(BatchExportSheet.sanitized(DeviceType.iPadPro13.rawValue)))
    }

    @Test func templatesOfDifferentDevicesDoNotCollide() {
        let phone = BatchExportSheet.fileName(template: template("Hero", device: .iPhone69), locale: "en-US", index: 0, includeLocale: false)
        let pad = BatchExportSheet.fileName(template: template("Hero", device: .iPadPro13), locale: "en-US", index: 0, includeLocale: false)

        #expect(phone != pad)
    }

    @Test(arguments: ["a/b", "a:b", "a?b", "a*b", "a|b", "a\"b", "a<b", "a>b", "a%b", "a\\b"])
    func pathSeparatorsAndReservedCharactersAreReplaced(name: String) {
        #expect(BatchExportSheet.sanitized(name) == "a-b")
    }

    @Test func spacesBecomeHyphensSoTheNameSurvivesShellUse() {
        #expect(BatchExportSheet.sanitized("First Run Screen") == "First-Run-Screen")
    }

    @Test func ordinaryNamesPassThroughUnchanged() {
        #expect(BatchExportSheet.sanitized("Hero_01.v2") == "Hero_01.v2")
    }

    /// A template named with a path separator must not escape the chosen export folder.
    @Test func templateNamesCannotIntroducePathComponents() {
        let name = BatchExportSheet.fileName(
            template: template("../../etc/passwd"),
            locale: "en-US",
            index: 2,
            includeLocale: true
        )

        #expect(!name.contains("/"))
        #expect(name.hasPrefix("03-en-US-"))
        #expect(URL(fileURLWithPath: "/tmp").appendingPathComponent(name).deletingLastPathComponent().path == "/tmp")
    }
}
