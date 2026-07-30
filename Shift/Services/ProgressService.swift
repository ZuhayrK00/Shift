import Foundation
import os.log
import Supabase
@preconcurrency import GRDB

private let logger = Logger(subsystem: "com.shift.app", category: "ProgressService")

struct ProgressService {

    // MARK: - Measurements

    static func getLatestPerType() async throws -> [BodyMeasurement] {
        let userId = try authManager.requireUserId()
        return try await BodyMeasurementRepository.findLatestPerType(userId: userId)
    }

    static func getMeasurements(type: String) async throws -> [BodyMeasurement] {
        let userId = try authManager.requireUserId()
        return try await BodyMeasurementRepository.findByType(userId: userId, type: type)
    }

    static func addMeasurement(type: String, value: Double, unit: String, recordedAt: Date = Date()) async throws -> BodyMeasurement {
        let userId = try authManager.requireUserId()
        let id = UUID().uuidString.lowercased()
        let measurement = BodyMeasurement(
            id: id, userId: userId, type: type, value: value, unit: unit, recordedAt: recordedAt
        )
        let mutation = LocalMutation(
            table: "body_measurements",
            op: "insert",
            payload: measurementPayload(measurement)
        )
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try measurement.save(db)
        }
        return measurement
    }

    static func updateMeasurement(_ id: String, value: Double, unit: String, recordedAt: Date) async throws {
        let userId = try authManager.requireUserId()
        let entries = try await BodyMeasurementRepository.findAll(userId: userId)
        guard var measurement = entries.first(where: { $0.id == id }) else { return }
        measurement.value = value
        measurement.unit = unit
        measurement.recordedAt = recordedAt
        let mutation = LocalMutation(
            table: "body_measurements",
            op: "update",
            payload: measurementPayload(measurement)
        )
        let measurementToSave = measurement
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try measurementToSave.save(db)
        }
    }

    static func deleteMeasurement(_ id: String) async throws {
        let userId = try authManager.requireUserId()
        let mutation = LocalMutation(table: "body_measurements", op: "delete", payload: ["id": id])
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try db.execute(
                sql: "DELETE FROM body_measurements WHERE id = ? AND user_id = ?",
                arguments: [id, userId]
            )
        }
    }

    // MARK: - Photos

    static func getPhotos() async throws -> [ProgressPhoto] {
        let userId = try authManager.requireUserId()
        let photos = try await ProgressPhotoRepository.findAll(userId: userId)
        let indexedPaths = photos.enumerated().compactMap { index, photo in
            extractStoragePath(from: photo.imageUrl).map { (index, $0) }
        }
        guard !indexedPaths.isEmpty else { return photos }

        do {
            let signedURLs = try await supabase.storage
                .from("progress-photos")
                .createSignedURLs(
                    paths: indexedPaths.map(\.1),
                    expiresIn: 3_600
                )
            guard signedURLs.count == indexedPaths.count else {
                logger.error("Private photo URL response count did not match the request.")
                return photos
            }
            var displayPhotos = photos
            for ((index, _), signedURL) in zip(indexedPaths, signedURLs) {
                displayPhotos[index].imageUrl = signedURL.absoluteString
            }
            return displayPhotos
        } catch {
            logger.error("Failed to create private photo URLs: \(error.localizedDescription)")
            return photos
        }
    }

    static func getLatestPhoto() async throws -> ProgressPhoto? {
        let userId = try authManager.requireUserId()
        guard let photo = try await ProgressPhotoRepository.findLatest(userId: userId) else {
            return nil
        }
        return await photoWithTemporaryURL(photo)
    }

    static func uploadPhoto(imageData: Data, recordedAt: Date = Date()) async throws -> ProgressPhoto {
        let userId = try authManager.requireUserId()
        let id = UUID().uuidString.lowercased()
        let timestamp = Int(Date().timeIntervalSince1970)
        let path = "\(userId.lowercased())/\(timestamp)_\(id.prefix(8)).jpg"

        // Upload to Supabase Storage
        _ = try await supabase.storage
            .from("progress-photos")
            .upload(path, data: imageData, options: .init(contentType: "image/jpeg", upsert: true))

        // Persist only the private object path. A short-lived signed URL is
        // generated when the photo is displayed and is never synced or cached
        // as part of the user's record.
        let storedPhoto = ProgressPhoto(
            id: id, userId: userId, imageUrl: path, recordedAt: recordedAt
        )
        let mutation = LocalMutation(
            table: "progress_photos",
            op: "insert",
            payload: photoPayload(storedPhoto)
        )
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try storedPhoto.save(db)
        }
        return await photoWithTemporaryURL(storedPhoto)
    }

    static func deletePhoto(_ photo: ProgressPhoto) async throws {
        let userId = try authManager.requireUserId()
        guard photo.userId == userId else { return }
        // Delete from storage
        if let path = extractStoragePath(from: photo.imageUrl) {
            do {
                try await supabase.storage
                    .from("progress-photos")
                    .remove(paths: [path])
            } catch {
                logger.error("Failed to delete photo from storage: \(error.localizedDescription)")
            }
        }
        let mutation = LocalMutation(
            table: "progress_photos",
            op: "delete",
            payload: ["id": photo.id]
        )
        try await MutationQueueRepository.performAtomically(mutations: [mutation]) { db in
            try db.execute(
                sql: "DELETE FROM progress_photos WHERE id = ? AND user_id = ?",
                arguments: [photo.id, userId]
            )
        }
    }

    // MARK: - Private

    private static func measurementPayload(_ m: BodyMeasurement) -> [String: Any] {
        [
            "id": m.id,
            "user_id": m.userId,
            "type": m.type,
            "value": m.value,
            "unit": m.unit,
            "recorded_at": ISO8601DateFormatter.shared.string(from: m.recordedAt)
        ]
    }

    private static func photoPayload(_ p: ProgressPhoto) -> [String: Any] {
        [
            "id": p.id,
            "user_id": p.userId,
            "image_url": p.imageUrl,
            "recorded_at": ISO8601DateFormatter.shared.string(from: p.recordedAt)
        ]
    }

    /// Accepts new path-only records plus legacy public and signed URLs.
    static func extractStoragePath(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.contains("://") {
            return trimmed.split(separator: "?", maxSplits: 1).first.map(String.init)
        }

        guard let range = trimmed.range(of: "progress-photos/") else { return nil }
        let suffix = String(trimmed[range.upperBound...])
        return suffix.split(separator: "?", maxSplits: 1).first.map(String.init)
    }

    private static func photoWithTemporaryURL(_ photo: ProgressPhoto) async -> ProgressPhoto {
        guard let path = extractStoragePath(from: photo.imageUrl) else { return photo }
        do {
            let signedURL = try await supabase.storage
                .from("progress-photos")
                .createSignedURL(path: path, expiresIn: 3_600)
            var displayPhoto = photo
            displayPhoto.imageUrl = signedURL.absoluteString
            return displayPhoto
        } catch {
            logger.error("Failed to create a private photo URL: \(error.localizedDescription)")
            return photo
        }
    }
}
