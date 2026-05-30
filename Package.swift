// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sombra",
    platforms: [
        .macOS(.v14) // ScreenCaptureKit (SCScreenshotManager) + Vision rápido
    ],
    targets: [
        // Shim C sobre o llama.cpp (headers vendados em vendor/include).
        .target(
            name: "CLlama",
            path: "Sources/CLlama",
            cSettings: [
                .headerSearchPath("../../vendor/include")
            ]
        ),
        .executableTarget(
            name: "Sombra",
            dependencies: ["CLlama"],
            path: "Sources/Sombra",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreGraphics"),
                // Bibliotecas do llama.cpp (em ./Frameworks) + rpaths para
                // execução: dentro do .app (Contents/Frameworks) e direto da
                // árvore .build (caminho absoluto do projeto).
                .unsafeFlags([
                    "-L", "Frameworks",
                    "-lllama",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../../Frameworks"
                ])
            ]
        )
    ]
)
