import SwiftUI

struct AvatarView: View {
    let avatarUrl: String?
    let displayName: String
    let size: AvatarSize

    enum AvatarSize {
        case small   // 32x32
        case medium  // 50x50
        case large   // 80x80
        case xlarge  // 100x100

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 50
            case .large: return 80
            case .xlarge: return 100
            }
        }

        var fontSize: CGFloat {
            dimension * 0.4
        }
    }

    var body: some View {
        Group {
            if let urlString = avatarUrl,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size.dimension, height: size.dimension)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .overlay {
                Text(initials)
                    .font(.system(size: size.fontSize))
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
    }

    private var initials: String {
        AvatarService.initials(from: displayName)
    }
}

// MARK: - Convenience Initializers

extension AvatarView {
    /// Initialize with User object
    init(user: User?, size: AvatarSize = .medium) {
        self.avatarUrl = user?.avatarUrl
        self.displayName = user?.displayName ?? user?.username ?? user?.email ?? "?"
        self.size = size
    }

    /// Initialize with optional avatar URL and display name
    init(avatarUrl: String?, displayName: String?, size: AvatarSize = .medium) {
        self.avatarUrl = avatarUrl
        self.displayName = displayName ?? "?"
        self.size = size
    }
}

// MARK: - Previews

#Preview("With Image URL") {
    AvatarView(
        avatarUrl: "https://i.pravatar.cc/300",
        displayName: "John Doe",
        size: .large
    )
}

#Preview("With Initials - Two Words") {
    AvatarView(
        avatarUrl: nil,
        displayName: "John Doe",
        size: .large
    )
}

#Preview("With Initials - One Word") {
    AvatarView(
        avatarUrl: nil,
        displayName: "John",
        size: .large
    )
}

#Preview("Sizes") {
    VStack(spacing: 20) {
        AvatarView(avatarUrl: nil, displayName: "John Doe", size: .small)
        AvatarView(avatarUrl: nil, displayName: "John Doe", size: .medium)
        AvatarView(avatarUrl: nil, displayName: "John Doe", size: .large)
        AvatarView(avatarUrl: nil, displayName: "John Doe", size: .xlarge)
    }
}
