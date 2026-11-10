import AVFoundation
import Combine
import MediaPlayer
import Foundation

@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var trackTitle = "MusicX"
    private var trackArtist = "本地音乐"
    private var wantsPlayback = false
    private var hasPublishedDuration = false
    private var publishesNowPlayingInfo = true

    init() {
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        configureAudioSession()
        configureRemoteCommands()

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                let seconds = self.player.currentItem?.duration.seconds ?? 0
                self.duration = seconds.isFinite ? max(0, seconds) : 0

                // Publish duration once it becomes available. Do not continuously
                // overwrite elapsed time; iOS advances the lock-screen timeline itself.
                if self.duration > 0 && !self.hasPublishedDuration {
                    self.hasPublishedDuration = true
                    self.updateNowPlayingInfo()
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let item = notification.object as? AVPlayerItem,
                      item === self.player.currentItem else { return }
                self.wantsPlayback = false
                self.isPlaying = false
                self.currentTime = self.duration
                self.updateNowPlayingInfo()
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(notification)
            }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            errorMessage = "音频会话初始化失败：\(error.localizedDescription)"
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            // Keep the intent separate from AVPlayer's transient state.
            isPlaying = false
            updateNowPlayingInfo()
        case .ended:
            let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if wantsPlayback && options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        let play = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
            return .success
        }
        remoteTargets.append((center.playCommand, play))

        let pause = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        remoteTargets.append((center.pauseCommand, pause))

        let toggle = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayback() }
            return .success
        }
        remoteTargets.append((center.togglePlayPauseCommand, toggle))

        let position = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: event.positionTime) }
            return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, position))

        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    func setNowPlayingPublishing(_ enabled: Bool) {
        publishesNowPlayingInfo = enabled
        if enabled { updateNowPlayingInfo() }
        else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    func play(url: URL, title: String, artist: String) {
        errorMessage = nil
        trackTitle = title
        trackArtist = artist
        wantsPlayback = true
        hasPublishedDuration = false
        configureAudioSession()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        currentTime = 0
        duration = 0
        isPlaying = true
        player.play()
        updateNowPlayingInfo()
    }

    func resume() {
        guard player.currentItem != nil else {
            errorMessage = "当前歌曲暂不可播放"
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "无法恢复音频会话：\(error.localizedDescription)"
            return
        }
        wantsPlayback = true
        player.play()
        isPlaying = true
        errorMessage = nil
        updateNowPlayingInfo()
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        isPlaying = false
        currentTime = max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : currentTime)
        updateNowPlayingInfo()
    }

    func togglePlayback() { isPlaying ? pause() : resume() }

    func seek(to seconds: TimeInterval) {
        guard duration > 0 else { return }
        let target = min(max(0, seconds), duration)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = target
                self.updateNowPlayingInfo()
            }
        }
    }

    func stop() {
        wantsPlayback = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = 0
        duration = 0
        hasPublishedDuration = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateNowPlayingInfo() {
        guard publishesNowPlayingInfo else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: trackTitle,
            MPMediaItemPropertyArtist: trackArtist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        for (command, target) in remoteTargets { command.removeTarget(target) }
    }
}
