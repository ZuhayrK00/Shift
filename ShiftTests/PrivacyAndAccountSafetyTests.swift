import XCTest
@testable import Shift

final class PrivacyAndAccountSafetyTests: XCTestCase {
    func testProgressPhotoStoragePathSupportsPrivatePath() {
        XCTAssertEqual(
            ProgressService.extractStoragePath(from: "user-id/photo.jpg"),
            "user-id/photo.jpg"
        )
    }

    func testProgressPhotoStoragePathMigratesLegacyPublicURL() {
        XCTAssertEqual(
            ProgressService.extractStoragePath(
                from: "https://example.supabase.co/storage/v1/object/public/progress-photos/user-id/photo.jpg"
            ),
            "user-id/photo.jpg"
        )
    }

    func testProgressPhotoStoragePathStripsSignedURLToken() {
        XCTAssertEqual(
            ProgressService.extractStoragePath(
                from: "https://example.supabase.co/storage/v1/object/sign/progress-photos/user-id/photo.jpg?token=secret"
            ),
            "user-id/photo.jpg"
        )
    }

    func testMinimumAgePolicy() {
        XCTAssertFalse(AgePolicy.isEligible(nil))
        XCTAssertFalse(AgePolicy.isEligible(12))
        XCTAssertTrue(AgePolicy.isEligible(13))
        XCTAssertTrue(AgePolicy.isEligible(120))
        XCTAssertFalse(AgePolicy.isEligible(121))
    }

    func testNewHealthSettingsDoNotReadActivityByDefault() {
        XCTAssertFalse(HealthKitSettings().showDailyActivity)
    }

    func testLegacyHealthSettingsDecodeActivityAsOptIn() throws {
        let data = Data(#"{"sync_workouts":true}"#.utf8)
        let settings = try JSONDecoder().decode(HealthKitSettings.self, from: data)
        XCTAssertTrue(settings.syncWorkouts)
        XCTAssertFalse(settings.showDailyActivity)
    }
}
