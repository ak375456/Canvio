//
//  AudioPlayerViewModel.swift
//  Ponder
//

import SwiftUI
import AVFoundation
import Combine

@MainActor
class AudioPlayerViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    var elementID: UUID?

    func load(fileName: String, elementID: UUID) {
        // If same element already loaded, don't reload
        if self.elementID == elementID, player != nil { return }
        self.elementID = elementID
        stop()
        let url = AudioStorageService.url(for: fileName)
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default
            )
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            currentTime = 0
        } catch {
            print("⚠️ Audio load error: \(error)")
        }
    }

    func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: Double) {
        player?.currentTime = time
        currentTime = time
    }

    func skipForward() {
        let newTime = min((player?.duration ?? 0), currentTime + 10)
        seek(to: newTime)
    }

    func skipBackward() {
        let newTime = max(0, currentTime - 10)
        seek(to: newTime)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying && self.isPlaying {
                    // Finished
                    self.isPlaying = false
                    self.currentTime = 0
                    player.currentTime = 0
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "0:00" }
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
