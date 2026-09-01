//
//  YouTubeElementView.swift
//  Ponder
//

import SwiftUI
import SwiftData
import WebKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct YouTubeElementView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var canvasHistory: CanvasUndoManager
    @Bindable var element: YouTubeElementModel
    let canvasScale: CGFloat
    let canvasBoundary: CGSize
    @ObservedObject var vm: YouTubeElementViewModel
    let isMultiSelectMode: Bool
    var isSelectedInMultiSelect: Bool = false
    var usesFloatingPlayback: Bool = false
    var onExternalTap: (() -> Void)? = nil
    var isCanvasGestureActive: Bool = false
    var smartDragAdjustment = CanvasSmartDragAdjustment()

    @State private var dragOffset: CGSize = .zero
    @State private var isResizing = false
    @State private var resizeStartSize: CGSize = .zero
    @State private var stopToken: UUID? = nil

    private var isSelected: Bool { vm.editingID == element.id }
    private var isPlaying: Bool { vm.activePlayingID == element.id }
    private let handleSize: CGFloat = 26
    private let cornerRadius: CGFloat = 14

    var body: some View {
        ZStack {
            card
            selectionRing
            if isSelected && !isMultiSelectMode {
                Button {
                    vm.delete(element: element, context: context, undoManager: canvasHistory)
                } label: {
                    handleCircle(icon: "trash", color: .red)
                }
                .buttonStyle(.plain)
                .offset(x: -(element.width / 2), y: -(element.height / 2))

                resizeHandle
                    .offset(x: element.width / 2, y: element.height / 2)
            }
        }
        .frame(width: element.width, height: element.height)
        .position(x: element.x + dragOffset.width, y: element.y + dragOffset.height)
        .gesture(canMove ? moveDragGesture : nil)
        .onChange(of: vm.stopPlaybackRequestID) { _, requestID in
            if requestID == element.id {
                stopToken = UUID()
            }
        }
    }

    private var card: some View {
        ZStack {
            if isPlaying && !usesFloatingPlayback {
                YouTubePlayerWebView(
                    videoID: element.videoID,
                    startSeconds: element.playbackSeconds,
                    stopToken: stopToken
                ) { seconds in
                    vm.finishStopPlayback(for: element.id, playbackSeconds: seconds,
                                          element: element, context: context)
                    stopToken = nil
                }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                preview
            }

            if isPlaying && usesFloatingPlayback {
                floatingPlaybackBadge
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(isSelected && !isMultiSelectMode ? Color.red.opacity(0.7) : Color.secondary.opacity(0.2),
                              lineWidth: isSelected && !isMultiSelectMode ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMultiSelectMode, !isCanvasGestureActive else { return }
            if !isSelected {
                onExternalTap?()
                vm.editingID = element.id
            }
        }
    }

    private var preview: some View {
        ZStack {
            AsyncImage(url: URL(string: element.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackThumbnail
                case .empty:
                    fallbackThumbnail
                        .overlay(ProgressView().tint(.white))
                @unknown default:
                    fallbackThumbnail
                }
            }
            .frame(width: element.width, height: element.height)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.05), .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    if let watchURL = element.watchURL {
                        Link(destination: watchURL) {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                    }
                }
                .padding(10)

                Spacer()

                if isPlaying && usesFloatingPlayback {
                    Button {
                        vm.requestStopPlayback(for: element.id)
                    } label: {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.48)).frame(width: 48, height: 48)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop floating YouTube playback")
                } else {
                    Button {
                        guard !isCanvasGestureActive else { return }
                        onExternalTap?()
                        vm.editingID = element.id
                        stopToken = nil
                        vm.activePlayingID = element.id
                    } label: {
                        ZStack {
                            Circle().fill(Color.red).frame(width: 48, height: 48)
                            Image(systemName: "play.fill")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play YouTube video")
                }

                Spacer()

                Text(element.title.isEmpty ? "YouTube Video" : element.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
    }

    private var floatingPlaybackBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 10, weight: .bold))
            Text("Floating")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.46), in: Capsule())
    }

    private var fallbackThumbnail: some View {
        ZStack {
            Rectangle().fill(Color(red: 0.12, green: 0.12, blue: 0.13))
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isMultiSelectMode {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    isSelectedInMultiSelect ? Color.blue : Color.white.opacity(0.35),
                    lineWidth: isSelectedInMultiSelect ? 2.5 : 1
                )
                .frame(width: element.width, height: element.height)
                .overlay(alignment: .topTrailing) {
                    if isSelectedInMultiSelect {
                        ZStack {
                            Circle().fill(Color.blue).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 8, y: -8)
                    }
                }
        }
    }

    private var resizeHandle: some View {
        handleCircle(icon: "arrow.up.left.and.arrow.down.right", color: .red)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isResizing {
                            resizeStartSize = CGSize(width: element.width, height: element.height)
                            isResizing = true
                        }
                        let width = max(180, resizeStartSize.width + value.translation.width)
                        let height = max(120, resizeStartSize.height + value.translation.height)
                        element.width = width
                        element.height = height
                    }
                    .onEnded { _ in
                        isResizing = false
                        vm.updateSize(
                            element: element,
                            width: element.width,
                            height: element.height,
                            context: context,
                            undoManager: canvasHistory,
                            previousSize: resizeStartSize
                        )
                    }
            )
    }

    private func handleCircle(icon: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: handleSize, height: handleSize)
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var moveDragGesture: some Gesture {
        DragGesture()
            .onChanged {
                guard canMove else {
                    dragOffset = .zero
                    smartDragAdjustment.cancelled()
                    return
                }
                dragOffset = smartDragAdjustment.changed($0.translation)
            }
            .onEnded { _ in
                guard canMove else {
                    dragOffset = .zero
                    smartDragAdjustment.cancelled()
                    return
                }
                let t = smartDragAdjustment.ended(dragOffset)
                dragOffset = .zero
                vm.updatePosition(
                    element: element,
                    translation: t,
                    boundary: canvasBoundary,
                    context: context,
                    undoManager: canvasHistory
                )
            }
    }

    private var canMove: Bool {
        isSelected && !isMultiSelectMode && !isCanvasGestureActive && (!isPlaying || usesFloatingPlayback)
    }
}

struct YouTubePlayerWebView: View {
    let videoID: String
    let startSeconds: Double
    let stopToken: UUID?
    let onStop: (Double) -> Void

    var body: some View {
        PlatformWebView(videoID: videoID, startSeconds: startSeconds,
                        stopToken: stopToken, onStop: onStop)
    }
}

#if canImport(UIKit)
private struct PlatformWebView: UIViewRepresentable {
    let videoID: String
    let startSeconds: Double
    let stopToken: UUID?
    let onStop: (Double) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onStop = onStop

        if context.coordinator.loadedVideoID != videoID {
            context.coordinator.loadedVideoID = videoID
            webView.loadHTMLString(embedHTML(videoID: videoID, startSeconds: startSeconds), baseURL: Self.baseURL)
        }

        if let stopToken, context.coordinator.handledStopToken != stopToken {
            context.coordinator.handledStopToken = stopToken
            context.coordinator.stopAndReport(webView: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStop: onStop)
    }

    private static let baseURL = URL(string: "https://canvio.local")!

    private func embedHTML(videoID: String, startSeconds: Double) -> String {
        let start = max(0, Int(startSeconds.rounded(.down)))
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
            #player { position: fixed; inset: 0; width: 100%; height: 100%; }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            var startSeconds = \(start);
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                width: '100%',
                height: '100%',
                videoId: '\(videoID)',
                playerVars: {
                  playsinline: 1,
                  rel: 0,
                  modestbranding: 1,
                  enablejsapi: 1,
                  origin: 'https://canvio.local',
                  start: startSeconds
                },
                events: {
                  'onReady': function(event) { event.target.playVideo(); }
                }
              });
            }
            window.canvioCurrentTime = function() {
              if (player && player.getCurrentTime) { return player.getCurrentTime(); }
              return startSeconds;
            };
            window.canvioPause = function() {
              if (player && player.pauseVideo) { player.pauseVideo(); }
            };
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoID: String?
        var handledStopToken: UUID?
        var onStop: (Double) -> Void

        init(onStop: @escaping (Double) -> Void) {
            self.onStop = onStop
        }

        func stopAndReport(webView: WKWebView) {
            webView.evaluateJavaScript("window.canvioCurrentTime ? window.canvioCurrentTime() : 0") { [weak self, weak webView] result, _ in
                let seconds = result as? Double ?? 0
                webView?.evaluateJavaScript("window.canvioPause && window.canvioPause();")
                self?.onStop(seconds)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if navigationAction.navigationType == .linkActivated,
               url.host?.contains("youtube.com") == true {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
#elseif canImport(AppKit)
private struct PlatformWebView: NSViewRepresentable {
    let videoID: String
    let startSeconds: Double
    let stopToken: UUID?
    let onStop: (Double) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onStop = onStop

        if context.coordinator.loadedVideoID != videoID {
            context.coordinator.loadedVideoID = videoID
            webView.loadHTMLString(embedHTML(videoID: videoID, startSeconds: startSeconds), baseURL: Self.baseURL)
        }

        if let stopToken, context.coordinator.handledStopToken != stopToken {
            context.coordinator.handledStopToken = stopToken
            context.coordinator.stopAndReport(webView: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStop: onStop)
    }

    private static let baseURL = URL(string: "https://canvio.local")!

    private func embedHTML(videoID: String, startSeconds: Double) -> String {
        let start = max(0, Int(startSeconds.rounded(.down)))
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
            #player { position: fixed; inset: 0; width: 100%; height: 100%; }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            var startSeconds = \(start);
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                width: '100%',
                height: '100%',
                videoId: '\(videoID)',
                playerVars: {
                  playsinline: 1,
                  rel: 0,
                  modestbranding: 1,
                  enablejsapi: 1,
                  origin: 'https://canvio.local',
                  start: startSeconds
                },
                events: {
                  'onReady': function(event) { event.target.playVideo(); }
                }
              });
            }
            window.canvioCurrentTime = function() {
              if (player && player.getCurrentTime) { return player.getCurrentTime(); }
              return startSeconds;
            };
            window.canvioPause = function() {
              if (player && player.pauseVideo) { player.pauseVideo(); }
            };
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoID: String?
        var handledStopToken: UUID?
        var onStop: (Double) -> Void

        init(onStop: @escaping (Double) -> Void) {
            self.onStop = onStop
        }

        func stopAndReport(webView: WKWebView) {
            webView.evaluateJavaScript("window.canvioCurrentTime ? window.canvioCurrentTime() : 0") { [weak self, weak webView] result, _ in
                let seconds = result as? Double ?? 0
                webView?.evaluateJavaScript("window.canvioPause && window.canvioPause();")
                self?.onStop(seconds)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if navigationAction.navigationType == .linkActivated,
               url.host?.contains("youtube.com") == true {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
#endif
