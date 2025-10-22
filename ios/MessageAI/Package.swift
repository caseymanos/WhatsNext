// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MessageAI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MessageAI",
            targets: ["MessageAI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/supabase-community/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "MessageAI",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "."
        )
    ]
)

