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

    func testAvatarStoragePathSupportsPrivatePath() {
        XCTAssertEqual(
            ProfileService.extractAvatarStoragePath(from: "user-id/avatar.jpg"),
            "user-id/avatar.jpg"
        )
    }

    func testAvatarStoragePathMigratesLegacyPublicURL() {
        XCTAssertEqual(
            ProfileService.extractAvatarStoragePath(
                from: "https://example.supabase.co/storage/v1/object/public/avatars/user-id/avatar.jpg"
            ),
            "user-id/avatar.jpg"
        )
    }

    func testAvatarStoragePathStripsSignedURLToken() {
        XCTAssertEqual(
            ProfileService.extractAvatarStoragePath(
                from: "https://example.supabase.co/storage/v1/object/sign/avatars/user-id/avatar.jpg?token=secret"
            ),
            "user-id/avatar.jpg"
        )
    }

    func testAccountDeletionBuildsUserScopedStoragePaths() {
        XCTAssertEqual(
            AccountDeletionService.storagePaths(
                userFolder: "/USER-ID/",
                fileNames: ["avatar.jpg", "progress 1.jpg"]
            ),
            ["user-id/avatar.jpg", "user-id/progress 1.jpg"]
        )
    }

    func testAccountDeletionRejectsEmptyAndNestedStorageNames() {
        XCTAssertEqual(
            AccountDeletionService.storagePaths(
                userFolder: "user-id",
                fileNames: ["", "/", "another-user/photo.jpg"]
            ),
            []
        )
        XCTAssertEqual(
            AccountDeletionService.storagePaths(
                userFolder: "/",
                fileNames: ["photo.jpg"]
            ),
            []
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
