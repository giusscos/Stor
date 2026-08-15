import Testing
@testable import AscendKit

/// Picking the wrong App Store version silently pushes metadata to a release Apple will
/// reject, so ordering and editability get their own coverage.
struct ASCVersionSelectionTests {
    private func version(_ string: String, state: String = "PREPARE_FOR_SUBMISSION") -> ASCAppStoreVersion {
        ASCAppStoreVersion(
            id: "\(string)-\(state)",
            attributes: .init(versionString: string, appStoreState: state, platform: "IOS")
        )
    }

    @Test func numericOrderingBeatsLexicographic() {
        let sorted = [version("1.9.0"), version("1.10.0"), version("1.2.0")]
            .sorted(by: ASCAppStoreVersion.isDescending)

        #expect(sorted.map(\.attributes.versionString) == ["1.10.0", "1.9.0", "1.2.0"])
    }

    @Test func missingComponentsCountAsZero() {
        let sorted = [version("2"), version("2.0.1"), version("2.0")]
            .sorted(by: ASCAppStoreVersion.isDescending)

        #expect(sorted.first?.attributes.versionString == "2.0.1")
        // "2" and "2.0" are numerically equal, so the tiebreak is the raw string.
        #expect(sorted.last?.attributes.versionString == "2")
    }

    @Test func nonNumericSuffixesAreTolerated() {
        let sorted = [version("3.0.1-beta"), version("3.1")]
            .sorted(by: ASCAppStoreVersion.isDescending)

        #expect(sorted.first?.attributes.versionString == "3.1")
    }

    @Test(arguments: [
        ("PREPARE_FOR_SUBMISSION", true),
        ("DEVELOPER_REJECTED", true),
        ("METADATA_REJECTED", true),
        ("READY_FOR_SALE", false),
        ("IN_REVIEW", false),
        ("WAITING_FOR_REVIEW", false)
    ])
    func editabilityFollowsAppStoreState(state: String, expected: Bool) {
        #expect(version("1.0", state: state).isEditable == expected)
    }

    /// The sync path prefers an editable version even when a higher-numbered one is live.
    @Test func editableVersionWinsOverHigherLiveVersion() {
        let versions = [
            version("2.0.0", state: "READY_FOR_SALE"),
            version("1.5.0", state: "PREPARE_FOR_SUBMISSION")
        ]

        let chosen = versions.filter(\.isEditable).max(by: { ASCAppStoreVersion.isDescending($1, $0) })

        #expect(chosen?.attributes.versionString == "1.5.0")
    }
}
