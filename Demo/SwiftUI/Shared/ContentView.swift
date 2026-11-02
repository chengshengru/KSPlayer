import KSPlayer
import SwiftUI

struct ContentView: View {
    #if !os(macOS) && !os(tvOS)
    // Xcode 14.2 本地适配:openWindow 为 macOS 13 API,macOS 12 改用 sheet 播放
    @Environment(\.openWindow) private var openWindow
    #endif
    @EnvironmentObject
    private var appModel: APPModel
    private var initialView: some View {
        #if os(macOS)
        // Xcode 14.2 本地适配:NavigationSplitView 为 macOS 13 API,降级为 NavigationView 双栏;
        // 播放窗口(openWindow)改为全屏 overlay 内嵌(macOS 12 的 sheet + NSViewRepresentable 不显示)
        NavigationView {
            // Xcode 14.2 本地适配:非可选 selection 绑定为 macOS 13 API,改用可选绑定
            List(selection: Binding<TabBarItem?>(
                get: { appModel.tabSelected },
                set: { if let value = $0 { appModel.tabSelected = value } }
            )) {
                link(to: .Home)
                link(to: .Favorite)
                link(to: .Files)
            }
            .frame(minWidth: 180)
            appModel.tabSelected.destination(appModel: appModel)
        }
        .overlay {
            // 播放项存在时以全屏 overlay 覆盖主窗口,ESC 或"返回"退出播放
            if let item = appModel.playbackItem {
                ZStack(alignment: .topLeading) {
                    if let model = item.model {
                        KSVideoPlayerView(model: model)
                    } else if let url = item.url {
                        KSVideoPlayerView(url: url)
                    }
                    Button("返回") {
                        appModel.playbackItem = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    .padding()
                }
            }
        }
        #else
        TabView(selection: $appModel.tabSelected) {
            tab(to: .Home)
            tab(to: .Favorite)
            tab(to: .Files)
            tab(to: .Setting)
        }
        #endif
    }

    var body: some View {
        initialView
            .preferredColorScheme(.dark)
            .background(Color.black)
            .sheet(isPresented: $appModel.openURLImport) {
                URLImportView()
            }
            .onChange(of: appModel.openURL) { url in
                if let url {
                    #if os(macOS)
                    appModel.playbackItem = PlaybackItem(url: url, model: nil)
                    #else
                    openWindow(value: url)
                    #endif
                    appModel.openURL = nil
                }
            }
            .onChange(of: appModel.openPlayModel) { model in
                if let model {
                    #if os(macOS)
                    appModel.playbackItem = PlaybackItem(url: nil, model: model)
                    #else
                    openWindow(value: model)
                    #endif
                    appModel.openPlayModel = nil
                }
            }
        #if !os(tvOS)
            .onDrop(of: ["public.url", "public.file-url"], isTargeted: nil) { items -> Bool in
                guard let item = items.first, let identifier = item.registeredTypeIdentifiers.first else {
                    return false
                }
                item.loadItem(forTypeIdentifier: identifier, options: nil) { urlData, _ in
                    if let urlData = urlData as? Data {
                        let url = NSURL(absoluteURLWithDataRepresentation: urlData, relativeTo: nil) as URL
                        DispatchQueue.main.async {
                            appModel.open(url: url)
                        }
                    }
                }
                return true
            }
            .fileImporter(isPresented: $appModel.openFileImport, allowedContentTypes: [.movie, .audio, .data]) { result in
                guard let url = try? result.get() else {
                    return
                }
                if url.startAccessingSecurityScopedResource() {
                    appModel.open(url: url)
                }
            }
        #endif
            .onOpenURL { url in
                KSLog("onOpenURL")
                appModel.open(url: url)
            }
    }

    func link(to item: TabBarItem) -> some View {
        item.lable.tag(item)
    }

    #if !os(macOS)
    func tab(to item: TabBarItem) -> some View {
        Group {
            if item == .Home {
                NavigationStack(path: $appModel.path) {
                    item.destination(appModel: appModel)
                }
            } else {
                NavigationStack {
                    item.destination(appModel: appModel)
                }
            }
        }
        .tabItem {
            item.lable.tag(item)
        }.tag(item)
    }
    #endif
}

enum TabBarItem: Int {
    case Home
    case Favorite
    case Files
    case Setting
    var lable: Label<Text, Image> {
        switch self {
        case .Home:
            return Label("Home", systemImage: "house.fill")
        case .Favorite:
            return Label("Favorite", systemImage: "star.fill")
        case .Files:
            return Label("Files", systemImage: "folder.fill.badge.gearshape")
        case .Setting:
            return Label("Setting", systemImage: "gear")
        }
    }

    @MainActor
    @ViewBuilder
    func destination(appModel: APPModel) -> some View {
        switch self {
        case .Home:
            HomeView(m3uURL: appModel.activeM3UModel?.m3uURL)
                .navigationPlay()
        case .Favorite:
            FavoriteView()
                .navigationPlay()
        case .Files:
            FilesView()
        case .Setting:
            SettingView()
        }
    }
}

public extension View {
    @MainActor
    @ViewBuilder
    func navigationPlay() -> some View {
        #if os(macOS)
        // Xcode 14.2 本地适配:navigationDestination(for:) 为 macOS 13 API,
        // macOS 12 播放统一由 initialView 中的 sheet 承载
        self
        #else
        navigationDestination(for: URL.self) { url in
            KSVideoPlayerView(url: url)
            #if !os(macOS)
                .toolbar(.hidden, for: .tabBar)
            #endif
        }
        .navigationDestination(for: MovieModel.self) { model in
            model.view
        }
        #endif
    }
}

#if !os(macOS)
private extension MovieModel {
    @MainActor
    var view: some View {
        KSVideoPlayerView(model: self)
        #if !os(macOS)
            .toolbar(.hidden, for: .tabBar)
        #endif
    }
}
#endif
