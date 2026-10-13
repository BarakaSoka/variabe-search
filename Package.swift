// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Variabe Search",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "variabe", targets: ["variabe"]),
        .executable(name: "VariabeApp", targets: ["VariabeApp"]),
        .library(name: "VariabeKit", targets: ["VariabeKit"]),
    ],
    dependencies: [
        // In-app updates (the app only). build.sh embeds the framework in Contents/Frameworks and signs it.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // The engine: crawler, extractors, index store, the embedder interface and worker client, search. No UI.
        .target(name: "VariabeKit"),
        // llama.cpp (scripts/build-llama.sh builds it into Vendor/llama) and EmbeddingGemma 2 on it.
        .systemLibrary(name: "CLlama", path: "Sources/CLlama"),
        .target(
            name: "LlamaRuntime",
            dependencies: ["CLlama", "VariabeKit"],
            linkerSettings: [.unsafeFlags(["-L\(Context.packageDirectory)/Vendor/llama/lib"])]
        ),
        // Developer CLI: estimate / index / search / status / eval. Doubles as the eval harness, and the app runs it as
        // its indexing helper and its query encoder.
        .executableTarget(name: "variabe", dependencies: ["VariabeKit", "LlamaRuntime"]),
        // The menubar + hotkey app. build.sh wraps it into build.noindex/Variabe Search.app. (The product can't be called
        // "Variabe Search": on a case-insensitive disk it would collide with the `variabe` CLI binary.)
        .executableTarget(
            name: "VariabeApp",
            dependencies: ["VariabeKit", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "VariabeKitTests", dependencies: ["VariabeKit"]),
        .testTarget(name: "LlamaRuntimeTests", dependencies: ["LlamaRuntime"]),
    ]
)
