import XCTest
@testable import Qstats

final class AppUpdateManagerTests: XCTestCase {

    func testVersionComparison() {
        XCTAssertTrue(AppUpdateManager.isVersion("1.8.3", newerThan: "1.8.2"))
        XCTAssertTrue(AppUpdateManager.isVersion("v1.9.0", newerThan: "1.8.2"))
        XCTAssertTrue(AppUpdateManager.isVersion("2.0.0", newerThan: "1.99.9"))
        XCTAssertTrue(AppUpdateManager.isVersion("1.10.0", newerThan: "1.9.0"))

        XCTAssertFalse(AppUpdateManager.isVersion("1.8.2", newerThan: "1.8.2"))
        XCTAssertFalse(AppUpdateManager.isVersion("v1.8.2", newerThan: "1.8.2"))
        XCTAssertFalse(AppUpdateManager.isVersion("1.8.1", newerThan: "1.8.2"))
        XCTAssertFalse(AppUpdateManager.isVersion("1.7.0", newerThan: "1.8.2"))
    }

    func testArchitectureAssetMatching() {
        let mockAssets: [[String: Any]] = [
            [
                "name": "Qstats-1.8.3-intel.dmg",
                "browser_download_url": "https://github.com/qg-hs/Qstats/releases/download/v1.8.3/Qstats-1.8.3-intel.dmg",
                "size": 1500000
            ],
            [
                "name": "Qstats-1.8.3-apple-silicon.dmg",
                "browser_download_url": "https://github.com/qg-hs/Qstats/releases/download/v1.8.3/Qstats-1.8.3-apple-silicon.dmg",
                "size": 1400000
            ],
            [
                "name": "SHA256SUMS-arm64.txt",
                "browser_download_url": "https://github.com/qg-hs/Qstats/releases/download/v1.8.3/SHA256SUMS-arm64.txt",
                "size": 100
            ]
        ]

        let matched = AppUpdateManager.matchBestAsset(from: mockAssets)
        XCTAssertNotNil(matched)

        #if arch(arm64)
        XCTAssertEqual(matched?.name, "Qstats-1.8.3-apple-silicon.dmg")
        #else
        XCTAssertEqual(matched?.name, "Qstats-1.8.3-intel.dmg")
        #endif
    }

    func testFallbackAssetMatching() {
        let fallbackAssets: [[String: Any]] = [
            [
                "name": "Qstats-universal.dmg",
                "browser_download_url": "https://github.com/qg-hs/Qstats/releases/download/v1.8.3/Qstats-universal.dmg",
                "size": 2500000
            ],
            [
                "name": "notes.txt",
                "browser_download_url": "https://github.com/example/notes.txt",
                "size": 50
            ]
        ]

        let matched = AppUpdateManager.matchBestAsset(from: fallbackAssets)
        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.name, "Qstats-universal.dmg")
    }
}
