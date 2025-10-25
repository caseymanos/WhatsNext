import SwiftUI

public enum PhotoUploadState: Equatable {
    case pending(UIImage, caption: String?)
    case uploading(UIImage, caption: String?, progress: Double)
    case uploaded(url: String, caption: String?)
    case failed(UIImage, caption: String?, error: String)

    public static func == (lhs: PhotoUploadState, rhs: PhotoUploadState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.uploading, .uploading),
             (.uploaded, .uploaded),
             (.failed, .failed):
            return true
        default:
            return false
        }
    }

    var image: UIImage? {
        switch self {
        case .pending(let image, _),
             .uploading(let image, _, _),
             .failed(let image, _, _):
            return image
        case .uploaded:
            return nil
        }
    }

    var caption: String? {
        switch self {
        case .pending(_, let caption),
             .uploading(_, let caption, _),
             .uploaded(_, let caption),
             .failed(_, let caption, _):
            return caption
        }
    }

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(_, _, let error) = self {
            return error
        }
        return nil
    }
}

struct PhotoUploadView: View {
    @Binding var uploadState: PhotoUploadState
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Photo thumbnail
                if let image = uploadState.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            if uploadState.isUploading {
                                ProgressView()
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                } else if case .uploaded(let url, _) = uploadState, let imageUrl = URL(string: url) {
                    AsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        default:
                            Color.gray
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Cancel button
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white)
                        .background(Circle().fill(.black.opacity(0.6)))
                }
                .padding(4)
            }

            // Error state with retry button
            if uploadState.isFailed, let errorMessage = uploadState.errorMessage {
                VStack(spacing: 2) {
                    Text("Failed")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        onRetry()
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
