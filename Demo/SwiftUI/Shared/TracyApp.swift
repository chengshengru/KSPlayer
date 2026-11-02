//
//  TracyApp.swift
//  Shared
//
//  Created by kintan on 2021/5/3.
//

import AVFoundation
import AVKit
import KSPlayer
import SwiftUI
import UserNotifications

@main
struct TracyApp: App {
    // Swift 5.7 适配:属性与声明被 #if 分割的写法在 5.7 解析器中报 expected declaration,
    // 需将完整声明放入各分支
    #if os(macOS)
    @NSApplicationDelegateAdaptor
    private var appDelegate: AppDelegate
    #else
    @UIApplicationDelegateAdaptor
    private var appDelegate: AppDelegate
    #endif
    private let appModel = APPModel()
    init() {
        let arguments = ProcessInfo.processInfo.arguments.dropFirst()
        var dropNextArg = false
        var playerArgs = [String]()
        var filenames = [String]()
        KSLog("launch arguments \(arguments)")
        for argument in arguments {
            if dropNextArg {
                dropNextArg = false
                continue
            }
            if argument.starts(with: "--") {
                playerArgs.append(argument)
            } else if argument.starts(with: "-") {
                dropNextArg = true
            } else {
                filenames.append(argument)
            }
        }
        if let urlString = filenames.first {
            appModel.open(url: URL(fileURLWithPath: urlString))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
            #if !os(tvOS)
                .handlesExternalEvents(preferring: Set(arrayLiteral: "pause"), allowing: Set(arrayLiteral: "*"))
            #endif
        }
        #if !os(tvOS)
//        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .commands {
            CommandGroup(before: .newItem) {
                Button("Open") {
                    appModel.openFileImport = true
                }
                .keyboardShortcut("o")
            }
            CommandGroup(before: .newItem) {
                Button("Open URL") {
                    appModel.openURLImport = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        #endif
        // Xcode 14.2 本地适配:defaultSize/defaultPosition 为 macOS 13 API,macOS 12 下去除
        // Xcode 14.2 本地适配:WindowGroup(_:for:) 值窗口与 openWindow 为 macOS 13 API,
        // macOS 12 改为单窗口 + sheet 播放(见 ContentView)
        #if !os(macOS) && !os(tvOS)
        WindowGroup("player", for: URL.self) { $url in
            if let url {
                KSVideoPlayerView(url: url)
            }
        }
        WindowGroup("player", for: MovieModel.self) { $model in
            if let model {
                KSVideoPlayerView(model: model)
            }
        }
        #endif
        #if os(macOS)
        Settings {
            TabBarItem.Setting.destination(appModel: appModel)
        }
//        MenuBarExtra {
//            MenuBar()
//        } label: {
//            Image(systemName: "film.fill")
//        }
//        .menuBarExtraStyle(.menu)
        #endif
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    #if os(macOS)
    func applicationDidFinishLaunching(_: Notification) {
//        requestNotification()
    }
    #else
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
//        requestNotification()
        true
    }
    #endif

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.reduce("") { $0 + String(format: "%02x", $1) }
        print("Device push notification token - \(tokenString)")
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notification. Error \(error)")
    }

    private func requestNotification() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, error in
            if allowed {
                // register for remote push notification
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                print("Push notification allowed by user")
            } else {
                print("Error while requesting push notification permission. Error \(String(describing: error))")
            }
        }
    }
}

class APPModel: ObservableObject {
    @Published
    var openURL: URL?
    @Published
    var openPlayModel: MovieModel?
    @Published
    var tabSelected: TabBarItem = .Home
    #if !os(macOS)
    // Xcode 14.2 本地适配:NavigationPath 为 macOS 13 API,macOS 12 播放改由 sheet 承载,不需要导航路径
    @Published
    var path = NavigationPath()
    #endif
    #if os(macOS)
    /// macOS 12 播放项:以 sheet 呈现,替代 macOS 13 的 openWindow 多窗口
    @Published
    var playbackItem: PlaybackItem?
    #endif
    @Published
    var openFileImport = false
    @Published
    var openURLImport = false
    @Published
    var hiddenTitleBar = false
    @AppStorage("activeM3UURL")
    private var activeM3UURL: URL?
    @Published
    var activeM3UModel: M3UModel? = nil {
        didSet {
            if let activeM3UModel, activeM3UModel != oldValue {
                activeM3UURL = activeM3UModel.m3uURL
                Task { @MainActor in
                    _ = try? await activeM3UModel.parsePlaylist()
                    // 为了解决第一次添加m3u。没有数据的问题，所以需要在查询结果出来之后，在设置下。
                    if activeM3UModel == self.activeM3UModel {
                        self.activeM3UModel = activeM3UModel
                    }
                }
            }
        }
    }

    init() {
        #if DEBUG
//        KSOptions.logLevel = .debug
        #else
        var fileHandle = FileHandle.standardOutput
        if let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("log.txt") {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                fileHandle = handle
                _ = try? fileHandle.seekToEnd()
            }
        }
        KSOptions.logger = FileLog(fileHandle: fileHandle)
        #endif
//        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        _ = Defaults.shared
        KSOptions.subtitleDataSouces = [DirectorySubtitleDataSouce(), ShooterSubtitleDataSouce(), AssrtSubtitleDataSouce(token: "5IzWrb2J099vmA96ECQXwdRSe9xdoBUv"), OpenSubtitleDataSouce(apiKey: "0D0gt8nV6SFHVVejdxAMpvOT0wByfKE5")]
        if let activeM3UURL {
            addM3U(url: activeM3UURL)
        }
    }

    func addM3U(url: URL, name: String? = nil) {
        let request = M3UModel.fetchRequest()
        request.predicate = NSPredicate(format: "m3uURL == %@", url.description)
        let context = PersistenceController.shared.viewContext
        context.perform {
            self.activeM3UModel = try? context.fetch(request).first ?? M3UModel(context: context, url: url, name: name)
        }
    }

    func open(url: URL) {
        if url.isPlaylist {
            addM3U(url: url)
        } else {
            #if os(macOS)
            openURL = url
            #else
            path.append(url)
            #endif
        }
    }

    func content(model: MovieModel) -> some View {
        #if os(macOS)
        Button {
            self.openPlayModel = model
        } label: {
            MoiveView(model: model)
        }
        .buttonStyle(.borderless)
        #else
        NavigationLink(value: model) {
            MoiveView(model: model)
        }
        #if targetEnvironment(macCatalyst)
        .buttonStyle(.borderless)
        #else
        .buttonStyle(.automatic)
        #endif
        #endif
    }
}

#if os(macOS)
/// macOS 12 以 sheet 呈现的播放项(url 或已存在的 MovieModel 二选一)
struct PlaybackItem: Identifiable {
    let id = UUID()
    let url: URL?
    let model: MovieModel?
}
#endif

struct KSVideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(APPModel())
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
