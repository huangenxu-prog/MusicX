import AVFoundation
import Combine
import MediaPlayer
import Foundation
import UIKit

extension Notification.Name {
    static let musicXRemoteNextTrack = Notification.Name("MusicXRemoteNextTrack")
    static let musicXRemotePreviousTrack = Notification.Name("MusicXRemotePreviousTrack")
    static let musicXPlaybackDidFinish = Notification.Name("MusicXPlaybackDidFinish")
}

@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var playbackDiagnostics = "等待播放"

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
    private var trackAlbum: String?
    private var artworkImage: UIImage?
    private var artworkTask: Task<Void, Never>?
    private var artworkRequestID = UUID()
    private var playerStatusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var lifecycleObservers: [NSObjectProtocol] = []

    var diagnosticFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicX-Playback-Diagnostics.txt")
    }

    private func recordDiagnostic(_ event: String) {
        let session = AVAudioSession.sharedInstance()
        let itemStatus = player.currentItem?.status.rawValue ?? -1
        let timeStatus = player.timeControlStatus.rawValue
        let seconds = player.currentTime().seconds
        let route = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(event) | player=\(timeStatus) item=\(itemStatus) time=\(seconds.isFinite ? String(format: "%.1f", seconds) : "n/a") wants=\(wantsPlayback) session=\(session.category.rawValue)/\(session.mode.rawValue) otherAudio=\(session.isOtherAudioPlaying) route=\(route)\n"
        playbackDiagnostics = "\(event) · player \(timeStatus) / item \(itemStatus)"
        if !FileManager.default.fileExists(atPath: diagnosticFileURL.path) {
            FileManager.default.createFile(atPath: diagnosticFileURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: diagnosticFileURL) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        }
    }

    private func observeCurrentItem(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                let error = item.error?.localizedDescription ?? "no-error"
                guard let self, item === self.player.currentItem else { return }
                self.recordDiagnostic("item-status=\(item.status.rawValue) \(error)")
                if item.status == .failed {
                    self.wantsPlayback = false
                    self.player.pause()
                    self.isPlaying = false
                    self.isBuffering = false
                    self.errorMessage = item.error?.localizedDescription ?? "歌曲加载失败，请尝试重新播放"
                    self.updateNowPlayingInfo()
                }
            }
        }
    }

    init() {
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        UIApplication.shared.beginReceivingRemoteControlEvents()
        configureAudioSession()
        configureRemoteCommands()
        playerStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordDiagnostic("player-time-control=\(player.timeControlStatus.rawValue)")
                let shouldBePlaying = self.wantsPlayback && player.timeControlStatus == .playing
                let shouldBeBuffering = self.wantsPlayback && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.isBuffering = shouldBeBuffering
                if self.isPlaying != shouldBePlaying {
                    self.isPlaying = shouldBePlaying
                    if shouldBePlaying { self.errorMessage = nil }
                    self.updateNowPlayingInfo()
                }
            }
        }
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordDiagnostic("app-did-enter-background") }
        })
        lifecycleObservers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordDiagnostic("app-will-enter-foreground") }
        })
        lifecycleObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map(String.init) ?? "unknown"
            Task { @MainActor [weak self] in self?.recordDiagnostic("audio-route-change=\(reason)") }
        })
        lifecycleObservers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordDiagnostic("media-services-reset")
                self.configureAudioSession()
                if self.wantsPlayback { self.resume() }
            }
        })

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
                NotificationCenter.default.post(name: .musicXPlaybackDidFinish, object: nil)
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
            errorMessage = nil
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
            recordDiagnostic("audio-interruption-began")
            // Keep the intent separate from AVPlayer's transient state.
            isPlaying = false
            updateNowPlayingInfo()
        case .ended:
            recordDiagnostic("audio-interruption-ended")
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

        let next = center.nextTrackCommand.addTarget { _ in
            NotificationCenter.default.post(name: .musicXRemoteNextTrack, object: nil)
            return .success
        }
        remoteTargets.append((center.nextTrackCommand, next))

        let previous = center.previousTrackCommand.addTarget { _ in
            NotificationCenter.default.post(name: .musicXRemotePreviousTrack, object: nil)
            return .success
        }
        remoteTargets.append((center.previousTrackCommand, previous))

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    func setNowPlayingPublishing(_ enabled: Bool) {
        publishesNowPlayingInfo = enabled
        if enabled { updateNowPlayingInfo() }
        else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    func play(url: URL, title: String, artist: String, album: String? = nil, artworkURL: URL? = nil) {
        errorMessage = nil
        trackTitle = title
        trackArtist = artist
        trackAlbum = album
        artworkImage = nil
        artworkTask?.cancel()
        artworkRequestID = UUID()
        let requestID = artworkRequestID
        if let artworkURL {
            artworkTask = Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                      !Task.isCancelled,
                      let image = UIImage(data: data) else { return }
                guard let self, self.artworkRequestID == requestID else { return }
                self.artworkImage = image
                self.updateNowPlayingInfo()
            }
        }
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = true
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = true
        wantsPlayback = true
        hasPublishedDuration = false
        configureAudioSession()
        let item = AVPlayerItem(url: url)
        observeCurrentItem(item)
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = 0
        isPlaying = false
        isBuffering = true
        recordDiagnostic("play-request")
        player.playImmediately(atRate: 1.0)
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
        recordDiagnostic("resume-request")
        player.playImmediately(atRate: 1.0)
        isPlaying = false
        isBuffering = true
        errorMessage = nil
        updateNowPlayingInfo()
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        isPlaying = false
        isBuffering = false
        currentTime = max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : currentTime)
        updateNowPlayingInfo()
    }

    func togglePlayback() { wantsPlayback ? pause() : resume() }

    /// Restart the current item after natural completion. Wait for the seek
    /// completion before issuing play so repeat-one does not race AVPlayer's end state.
    func replayCurrentTrack() {
        guard let item = player.currentItem, duration > 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "无法恢复音频会话：\(error.localizedDescription)"
            return
        }
        wantsPlayback = true
        isPlaying = false
        isBuffering = true
        errorMessage = nil
        item.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, finished, self.player.currentItem === item, self.wantsPlayback else { return }
                self.player.playImmediately(atRate: 1.0)
                self.currentTime = 0
                self.updateNowPlayingInfo()
            }
        }
    }

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
        let oldItem = player.currentItem
        player.replaceCurrentItem(with: nil)
        oldItem?.cancelPendingSeeks()
        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = 0
        hasPublishedDuration = false
        artworkTask?.cancel()
        artworkImage = nil
        trackAlbum = nil
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
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
        if let trackAlbum, !trackAlbum.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = trackAlbum
        }
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    deinit {
        artworkTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        for (command, target) in remoteTargets { command.removeTarget(target) }
        playerStatusObservation = nil
        itemStatusObservation = nil
        for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
    }
}
