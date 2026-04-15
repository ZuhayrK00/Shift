import Foundation
import os.log
import Supabase

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
        try await BodyMeasurementRepository.upsert(measurement)
        try await enqueue(table: "body_measurements", op: "insert", payload: measurementPayload(measurement))
        return measurement
    }

    static func updateMeasurement(_ id: String, value: Double, unit: String, recordedAt: Date) async throws {
        let userId = try authManager.requireUserId()
        let entries = try await BodyMeasurementRepository.findAll(userId: userId)
        guard var measurement = entries.first(where: { $0.id == id }) else { return }
        measurement.value = value
        measurement.unit = unit
        measurement.recordedAt = recordedAt
        try await BodyMeasurementRepository.upsert(measurement)
        try await enqueue(table: "body_measurements", op: "update", payload: measurementPayload(measurement))
    }

    static func deleteMeasurement(_ id: String) async throws {
        try await BodyMeasurementRepository.delete(id)
        try await enqueue(table: "body_measurements", op: "delete", payload: ["id": id])
    }

    // MARK: - Photos

    static func getPhotos() async throws -> [ProgressPhoto] {
        let userId = try authManager.requireUserId()
        return try await ProgressPhotoRepository.findAll(userId: userId)
    }

    static func getLatestPhoto() async throws -> ProgressPhoto? {
        let userId = try authManager.requireUserId()
        return try await ProgressPhotoRepository.findLatest(userId: userId)
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

        let publicURL = try supabase.storage
            .from("progress-photos")
            .getPublicURL(path: path)

        let photo = ProgressPhoto(
            id: id, userId: userId, imageUrl: publicURL.absoluteString, recordedAt: recordedAt
        )
        try await ProgressPhotoRepository.upsert(photo)
        try await enqueue(table: "progress_photos", op: "insert", payload: photoPayload(photo))
        return photo
    }

    static func deletePhoto(_ photo: ProgressPhoto) async throws {
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
        try await ProgressPhotoRepository.delete(photo.id)
        try await enqueue(table: "progress_photos", op: "delete", payload: ["id": photo.id])
    }

    // MARK: - Private

    private static func enqueue(table: String, op: String, payload: [String: Any]) async throws {
        try await MutationQueueRepository.enqueue(table: table, op: op, payload: payload)
        SyncService.flushInBackground()
    }

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

    /// Extracts the storage path from a public URL.
    private static func extractStoragePath(from urlString: String) -> String? {
        guard let range = urlString.range(of: "progress-photos/") else { return nil }
        return String(urlString[range.upperBound...])
    }
}
