//
//  KSCorePlayerView.swift
//  KSPlayer
//
//  Created by kintan on 11/30/24.
//

import Foundation
import KSPlayer
import SwiftUI

@available(iOS 14.0, macOS 11.0, tvOS 14.0, *)
public struct KSCorePlayerView: View {
    @ObservedObject
    private var config: KSVideoPlayer.Coordinator
    public let url: URL
    public let options: KSOptions
    @Binding
    private var title: String
    private let subtitleDataSource: SubtitleDataSource?

    public init(config: KSVideoPlayer.Coordinator, url: URL, options: KSOptions, title: Binding<String>, subtitleDataSource: SubtitleDataSource?) {
        self.config = config
        self.url = url
        self.options = options
        _title = title
        self.subtitleDataSource = subtitleDataSource
    }

    public var body: some View {
        KSVideoPlayer(coordinator: config, url: url, options: options)
            .onStateChanged { playerLayer, state in
                if state == .readyToPlay {
                    if let subtitleDataSource {
                        config.playerLayer?.subtitleModel.addSubtitle(dataSource: subtitleDataSource)
                    }
                    if let movieTitle = playerLayer.player.dynamicInfo.metadata["title"] {
                        title = movieTitle
                    }
                }
            }
            .onBufferChanged { bufferedCount, consumeTime in
                KSLog("bufferedCount:\(bufferedCount),consumeTime:\(consumeTime)")
            }
        #if (os(iOS) || os(macOS))
        // translationView(subtitleModel:) 在 KSPlayer 二进制中是 package 访问级符号(仅 package.swiftinterface 可见,
        // Swift 5.9+ 工具链配合 -experimental-package-interface-load 加载;5.7 无 package 访问级,直接裁剪)
        #if compiler(>=5.9)
            .translationView(subtitleModel: config.playerLayer?.subtitleModel)
        #endif
        #endif
            .ignoresSafeArea()

        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(iOS)
        .focusable(!config.isMaskShow)
        #endif
        #if !os(visionOS)
        .onKeyPressLeftArrow {
            config.skip(interval: -15)
        }
        .onKeyPressRightArrow {
            config.skip(interval: 15)
        }
        .onKeyPressSapce {
            if config.state.isPlaying {
                config.playerLayer?.pause()
            } else {
                config.playerLayer?.play()
            }
        }
        #endif
        #if os(macOS)
        .navigationTitle(title)
        .onTapGesture(count: 2) {
            guard let view = config.playerLayer?.player.view else {
                return
            }
            view.window?.toggleFullScreen(nil)
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
        }
        .onExitCommand {
            config.playerLayer?.player.view.exitFullScreenMode()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                config.skip(interval: -15)
            case .right:
                config.skip(interval: 15)
            case .up:
                config.playerLayer?.player.playbackVolume += 0.2
            case .down:
                config.playerLayer?.player.playbackVolume -= 0.2
            @unknown default:
                break
            }
        }
        #elseif !os(tvOS)
        .onTapGesture(count: 2) {
            if config.state.isPlaying {
                config.playerLayer?.pause()
            } else {
                config.playerLayer?.play()
            }
        }
        #endif
    }
}

@available(iOS 14.0, macOS 11.0, tvOS 14.0, *)
extension KSCorePlayerView: Equatable {
    public nonisolated static func == (lhs: KSCorePlayerView, rhs: KSCorePlayerView) -> Bool {
        lhs.url == rhs.url
    }
}
