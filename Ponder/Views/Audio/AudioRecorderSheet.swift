//
//  AudioRecorderSheet.swift
//  Ponder
//

import SwiftUI
import AVFoundation

struct AudioRecorderSheet: View {
    let onSave: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingTime: Double = 0
    @State private var timer: Timer?
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 30)
    @State private var levelTimer: Timer?
    @State private var permissionDenied = false
    @State private var permissionChecked = false
    @State private var recordedURL: URL?     // ← temp file URL

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if permissionDenied {
                permissionDeniedView
            } else if !permissionChecked {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                recorderBody
            }
        }
        .onAppear { requestPermission() }
        .onDisappear { cleanup() }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Text("Cancel").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
            Text("Record Audio").font(.headline)
            Spacer()

            if !isRecording, recordedURL != nil {
                Button {
                    if let url = recordedURL {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onSave(url)
                        }
                    }
                } label: {
                    Text("Use")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Text("").frame(width: 40)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Recorder body
    private var recorderBody: some View {
        VStack(spacing: 32) {
            Spacer()

            // Waveform level meter
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<audioLevels.count, id: \.self) { i in
                    Capsule()
                        .fill(isRecording ? Color.red.opacity(0.8) : Color.secondary.opacity(0.3))
                        .frame(width: 3, height: max(4, audioLevels[i] * 60))
                        .animation(.easeOut(duration: 0.08), value: audioLevels[i])
                }
            }
            .frame(height: 64)

            // Timer display
            Text(formattedTime(recordingTime))
                .font(.system(size: 48, weight: .thin, design: .monospaced))
                .foregroundStyle(isRecording ? .red : .primary)
                .animation(.easeInOut(duration: 0.2), value: isRecording)

            // Record / Stop button
            Button {
                if isRecording { stopRecording() }
                else { startRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 88, height: 88)
                    if isRecording {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                            .frame(width: 36, height: 36)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 64, height: 64)
                    }
                }
                .animation(.spring(duration: 0.3), value: isRecording)
            }
            .buttonStyle(.plain)

            Text(isRecording ? "Tap to stop"
                 : recordedURL != nil ? "Tap to re-record"
                 : "Tap to start")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Preview player — loads directly from temp URL
            if !isRecording, let url = recordedURL {
                AudioPreviewPlayer(url: url)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Permission denied
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("Microphone Access Required")
                .font(.title3.weight(.semibold))
            Text("Ponder needs microphone access to record audio. Please enable it in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #elseif os(macOS)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
                #endif
            } label: {
                Text("Open Settings")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Permission request
    private func requestPermission() {
        #if os(iOS)
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                permissionDenied = !granted
                permissionChecked = true
            }
        }
        #elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionDenied = false
            permissionChecked = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    permissionDenied = !granted
                    permissionChecked = true
                }
            }
        default:
            permissionDenied = true
            permissionChecked = true
        }
        #endif
    }

    // MARK: - Recording
    private func startRecording() {
        // Create a fresh temp file each time
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            #endif

            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            isRecording = true
            recordingTime = 0
            // Store URL now — file is being written here
            recordedURL = url

            // Time ticker
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in recordingTime += 0.1 }
            }

            // Level meter
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                Task { @MainActor in
                    recorder?.updateMeters()
                    let power = recorder?.averagePower(forChannel: 0) ?? -60
                    let level = CGFloat((power + 60) / 60)
                    var newLevels = audioLevels
                    newLevels.removeFirst()
                    newLevels.append(max(0.05, level))
                    audioLevels = newLevels
                }
            }
        } catch {
            print("⚠️ Recording start error: \(error)")
        }
    }

    private func stopRecording() {
        recorder?.stop()
        isRecording = false
        timer?.invalidate(); timer = nil
        levelTimer?.invalidate(); levelTimer = nil
        audioLevels = Array(repeating: 0.1, count: 30)
        // recordedURL already points to the finished file
    }

    private func cleanup() {
        recorder?.stop()
        timer?.invalidate()
        levelTimer?.invalidate()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    private func formattedTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Preview player
// Self-contained — manages its own AVAudioPlayer directly, no VM needed
private struct AudioPreviewPlayer: View {
    let url: URL

    @State private var avPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var playTimer: Timer?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.pink)
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { seek(to: $0) }
                    ),
                    in: 0...max(1, duration)
                )
                .tint(.pink)

                HStack {
                    Text(formatted(currentTime))
                    Spacer()
                    Text(formatted(duration))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { setup() }
        .onDisappear {
            avPlayer?.stop()
            playTimer?.invalidate()
        }
    }

    private func setup() {
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            avPlayer = p
            duration = p.duration
        } catch {
            print("⚠️ Preview setup error: \(error)")
        }
    }

    private func togglePlayPause() {
        guard let p = avPlayer else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
            playTimer?.invalidate()
        } else {
            p.play()
            isPlaying = true
            playTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    guard let p = avPlayer else { return }
                    currentTime = p.currentTime
                    if !p.isPlaying {
                        isPlaying = false
                        currentTime = 0
                        p.currentTime = 0
                        playTimer?.invalidate()
                    }
                }
            }
        }
    }

    private func seek(to time: Double) {
        avPlayer?.currentTime = time
        currentTime = time
    }

    private func formatted(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
