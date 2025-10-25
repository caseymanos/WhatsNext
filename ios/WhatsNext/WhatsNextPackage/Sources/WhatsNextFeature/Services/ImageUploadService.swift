import Foundation
import Supabase
import UIKit

enum ImageUploadError: LocalizedError {
    case compressionFailed
    case uploadFailed(String)
    case invalidImage
    case noImageData

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to process image. Please try a different photo."
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .invalidImage:
            return "Invalid image format. Please select a JPEG or PNG."
        case .noImageData:
            return "No image data available."
        }
    }
}

public final class ImageUploadService {
    private let supabase = SupabaseClientService.shared

    public init() {}

    /// Upload profile picture and return public URL
    public func uploadProfilePicture(userId: UUID, image: UIImage) async throws -> String {
        // Process image (resize and compress)
        guard let imageData = processImage(image) else {
            throw ImageUploadError.compressionFailed
        }

        // Generate filename
        let filename = "\(userId.uuidString)/avatar.jpg"

        do {
            // Upload to Supabase Storage
            _ = try await supabase.storage
                .from("avatars")
                .upload(
                    path: filename,
                    file: imageData,
                    options: FileOptions(
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )

            // Get public URL
            let publicURL = try supabase.storage
                .from("avatars")
                .getPublicURL(path: filename)

            return publicURL.absoluteString
        } catch {
            throw ImageUploadError.uploadFailed(error.localizedDescription)
        }
    }

    /// Delete profile picture
    public func deleteProfilePicture(userId: UUID) async throws {
        let filename = "\(userId.uuidString)/avatar.jpg"

        do {
            try await supabase.storage
                .from("avatars")
                .remove(paths: [filename])
        } catch {
            throw ImageUploadError.uploadFailed(error.localizedDescription)
        }
    }

    /// Upload message photo and return public URL
    public func uploadMessagePhoto(userId: UUID, conversationId: UUID, image: UIImage) async throws -> String {
        // Process image (resize to 1024x1024 max and compress)
        guard let imageData = processImage(image, maxSize: 1024) else {
            throw ImageUploadError.compressionFailed
        }

        // Generate unique filename
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(conversationId)/\(userId)_\(timestamp)_\(UUID().uuidString.prefix(8)).jpg"

        do {
            // Upload to Supabase Storage
            _ = try await supabase.storage
                .from("message-photos")
                .upload(
                    path: filename,
                    file: imageData,
                    options: FileOptions(
                        contentType: "image/jpeg",
                        upsert: false
                    )
                )

            // Get public URL
            let publicURL = try supabase.storage
                .from("message-photos")
                .getPublicURL(path: filename)

            return publicURL.absoluteString
        } catch {
            throw ImageUploadError.uploadFailed(error.localizedDescription)
        }
    }

    /// Upload multiple message photos and return public URLs
    public func uploadMessagePhotos(userId: UUID, conversationId: UUID, images: [UIImage]) async throws -> [String] {
        // Upload photos in parallel using TaskGroup
        return try await withThrowingTaskGroup(of: String.self) { group in
            for image in images {
                group.addTask {
                    try await self.uploadMessagePhoto(userId: userId, conversationId: conversationId, image: image)
                }
            }

            var urls: [String] = []
            for try await url in group {
                urls.append(url)
            }
            return urls
        }
    }

    /// Process image: resize and compress to JPEG 0.7 quality
    private func processImage(_ image: UIImage, maxSize: CGFloat = 512) -> Data? {
        // Resize to max size maintaining aspect ratio
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)

        // If already smaller than max, don't upscale
        let newSize: CGSize
        if ratio >= 1.0 {
            newSize = size
        } else {
            newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        }

        // Use UIGraphicsImageRenderer for better quality and performance
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // Compress to JPEG at 0.7 quality (sweet spot for mobile)
        return resizedImage.jpegData(compressionQuality: 0.7)
    }
}
