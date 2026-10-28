// swift-tools-version:5.7
import Foundation
import PackageDescription

// G3: 平台声明不含 visionOS——`.visionOS` 枚举是 PackageDescription 5.9 API,
// 在 swift-tools-version:5.7 的 manifest 中被可用性门控,任何工具链(含 Xcode 15–26)都无法条件追加
// (实测 `if #available(_PackageDescription 5.9, *)` 亦不能解锁,自定义可用性域需 Swift 6.1+ 语言特性)。
// SPM 语义:未在 platforms 中声明的平台仍可直接构建,部署版本取自主工程;
// 因此 Xcode 15+ 下 visionOS 构建照常工作,仅失去"最低 visionOS 1.0"的显式声明(源码层 #if os(visionOS) 不受影响)。
var platforms: [SupportedPlatform] = [
    .iOS(.v13), .macCatalyst(.v14), .macOS(.v10_15), .tvOS(.v13),
//        .watchOS(.v9),
]

// G4: -experimental-package-interface-load 是 Swift 5.9 的实验性编译参数,
// 5.7 编译器不识别(会报 unknown flag),仅高版本工具链添加;
// 高版本下该 flag 用于加载 KSPlayer 二进制内的 package.swiftinterface(package 访问级符号),
// 5.7 无 package 访问级,对应调用点已在源码中以 #if compiler(>=5.9) 裁剪,无需该 flag
var packageInterfaceLoadSettings: [SwiftSetting] = []
#if compiler(>=5.9)
packageInterfaceLoadSettings.append(.unsafeFlags([
    "-experimental-package-interface-load",
]))
#endif

// G5: String Catalog(.xcstrings)需 Xcode 15+ 编译;
// 低版本回退到由 xcstrings 全量同源导出的 Resources/<lang>.lproj/Localizable.strings,
// 保证低版本构建的本地化行为与 main 产物一致(高版本分支排除该目录,避免 unhandled file 警告)
var uiResources: [Resource] = []
var uiExclude: [String] = []
#if compiler(>=5.9)
uiResources.append(.process("Localizable.xcstrings"))
uiExclude.append("Resources")
#else
uiResources.append(.process("Resources"))
#endif

let package = Package(
    name: "KSPlayer",
    defaultLocalization: "en",
    platforms: platforms,
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "KSPlayer",
            targets: ["KSPlayer"]
        ),
        .library(
            name: "KSPlayerUI",
            // todo clang: warning: using sysroot for 'iPhoneSimulator' but targeting 'MacOSX' [-Wincompatible-sysroot]
            type: ProcessInfo.processInfo.environment["dynamicFrameWork"] == nil ? .static : .dynamic,
            targets: ["KSPlayerUI"]
        ),
        .library(
            name: "MPVPlayer",
            type: ProcessInfo.processInfo.environment["dynamicFrameWork"] == nil ? .static : .dynamic,
            targets: ["MPVPlayer"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "KSPlayer",
            path: "Sources/KSPlayer.xcframework"
        ),
        .target(
            name: "MPVPlayer",
            dependencies: [
                .product(name: "libmpv", package: "FFmpegKit"),
                "KSPlayer",
            ],
            swiftSettings: packageInterfaceLoadSettings
        ),
        .target(
            name: "KSPlayerUI",
            dependencies: [
                "FFmpegKit",
                "KSPlayer",
            ],
            exclude: uiExclude,
            resources: uiResources,
            swiftSettings: packageInterfaceLoadSettings
        ),
        .testTarget(
            name: "KSPlayerUITests",
            dependencies: ["KSPlayerUI"],
            swiftSettings: packageInterfaceLoadSettings
        ),
    ]
    // G2: 原 swiftLanguageModes [.v5, .v6] 已移除——5.7 manifest 无该参数;
    // 移除后两代工具链统一以 Swift 5 language mode 编译(现状默认即 v5,行为零差异)
)

var ffmpegKitPath = FileManager.default.currentDirectoryPath + "/../FFmpegKit"
// spm FileManager.default.currentDirectoryPath返回的空字符，spm6.0#file返回的不是当前的目录。要改成用#filePath
if !FileManager.default.fileExists(atPath: ffmpegKitPath), let url = URL(string: #filePath) {
    let path = url.deletingLastPathComponent().path
    // 解决用xcode引入spm的时候，依赖关系出错的问题
    if !path.contains("/checkouts/") {
        ffmpegKitPath = path + "/../FFmpegKit"
    }
}

if FileManager.default.fileExists(atPath: ffmpegKitPath + "/Package.swift") {
    package.dependencies += [
        .package(path: ffmpegKitPath),
    ]
} else {
    package.dependencies += [
        .package(url: "https://github.com/kingslay/FFmpegKit.git", from: "9.0.2"),
    ]
}
