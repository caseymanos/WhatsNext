import SwiftUI

/// In-app banner that displays when a message arrives while app is in foreground
public struct InAppMessageBanner: View {
    let conversationName: String
    let senderName: String
    let messageContent: String
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    @State private var isPresented = false
    @State private var offset: CGFloat = -100
    
    public var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(senderName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.white)
                }
            
            // Message content
            VStack(alignment: .leading, spacing: 4) {
                Text(conversationName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(senderName): \(messageContent)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
        .padding(.horizontal)
        .offset(y: offset)
        .onTapGesture {
            dismiss()
            onTap()
        }
        .onAppear {
            // Animate in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                offset = 0
            }
            
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                dismiss()
            }
        }
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            offset = -100
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }
}

/// Manager for displaying in-app message banners
@MainActor
public class InAppBannerManager: ObservableObject {
    public static let shared = InAppBannerManager()
    
    @Published public var currentBanner: BannerData?
    
    private init() {}
    
    public func showBanner(
        conversationId: UUID,
        conversationName: String,
        senderName: String,
        messageContent: String
    ) {
        // Replace any existing banner
        currentBanner = BannerData(
            id: UUID(),
            conversationId: conversationId,
            conversationName: conversationName,
            senderName: senderName,
            messageContent: messageContent
        )
    }
    
    public func dismissBanner() {
        currentBanner = nil
    }
    
    public struct BannerData: Identifiable {
        public let id: UUID
        public let conversationId: UUID
        public let conversationName: String
        public let senderName: String
        public let messageContent: String
    }
}

/// View modifier to add banner support to a view
public struct InAppBannerModifier: ViewModifier {
    @ObservedObject var bannerManager = InAppBannerManager.shared
    let onBannerTap: (UUID) -> Void
    
    public func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if let banner = bannerManager.currentBanner {
                InAppMessageBanner(
                    conversationName: banner.conversationName,
                    senderName: banner.senderName,
                    messageContent: banner.messageContent,
                    onTap: {
                        onBannerTap(banner.conversationId)
                    },
                    onDismiss: {
                        bannerManager.dismissBanner()
                    }
                )
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
    }
}

public extension View {
    func inAppBanner(onTap: @escaping (UUID) -> Void) -> some View {
        modifier(InAppBannerModifier(onBannerTap: onTap))
    }
}

#Preview {
    VStack {
        Text("App Content")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.1))
    }
    .inAppBanner { _ in }
    .onAppear {
        InAppBannerManager.shared.showBanner(
            conversationId: UUID(),
            conversationName: "Team Chat",
            senderName: "John Doe",
            messageContent: "Hey, did you see the latest updates?"
        )
    }
}

