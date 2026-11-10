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
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var trackTitle = "MusicX"
    private var trackArtist = "本地音乐"

    init() {
        configureAudioSession()
        configureRemoteCommands()

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                let seconds = self.player.currentItem?.duration.seconds ?? 0
                self.duration = seconds.isFinite ? max(0, seconds) : 0
                self.updateNowPlayingInfo()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let item = notification.object as? AVPlayerItem,
                      item === self.player.currentItem else { return }
                self.isPlaying = false
                self.currentTime = self.duration
                self.updateNowPlayingInfo()
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

    func play(url: URL, title: String, artist: String) {
        errorMessage = nil
        trackTitle = title
        trackArtist = artist
        configureAudioSession()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        currentTime = 0
        duration = 0
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func resume() {
        guard player.currentItem != nil else {
            errorMessage = "当前歌曲暂不可播放"
            return
        }
        do { try AVAudioSession.sharedInstance().setActive(true) } catch {
            errorMessage = error.localizedDescription
        }
        player.play()
        isPlaying = true
        errorMessage = nil
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func togglePlayback() { isPlaying ? pause() : resume() }

    func seek(to seconds: TimeInterval) {
        guard duration > 0 else { return }
        let target = min(max(0, seconds), duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: trackTitle,
            MPMediaItemPropertyArtist: trackArtist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        for (command, target) in remoteTargets { command.removeTarget(target) }
    }
}
