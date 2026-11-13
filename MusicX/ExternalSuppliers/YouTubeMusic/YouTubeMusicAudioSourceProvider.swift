import Foundation

/// Best-effort YouTube Music playback adapter.
///
/// The WEB_REMIX search API returns metadata only. Playback is requested through
/// YouTube's iOS InnerTube player client, which can return direct adaptive audio
/// URLs or an HLS manifest. This is an undocumented interface and may be gated,
/// changed, or unavailable for particular videos/regions.
struct YouTubeMusicAudioSourceProvider: MusicResourceProvider {
    let identifier = "youtube-music-innertube-ios"
    let displayName = "YouTube Music"

    private let session: URLSession
    private let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(song: MusicSong, quality: MusicQuality) async throws -> ResolvedMusicResource? {
        guard song.source == .youtubeMusic || song.source == .youtube else { return nil }
        guard !song.sourceID.isEmpty else { return nil }
        try Task.checkCancellation()

        let clientVersion = "21.03.2"
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "IOS",
                    "clientVersion": clientVersion,
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone",
                    "osName": "iOS",
                    "osVersion": "18.0",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": song.sourceID,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("com.google.ios.youtube/\(clientVersion) (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MusicSourceError.invalidResponse(
                "YouTube player HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            )
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusicSourceError.invalidResponse("YouTube player 响应格式错误")
        }

        let playability = root["playabilityStatus"] as? [String: Any]
        let status = playability?["status"] as? String
        guard status == nil || status == "OK" else {
            let reason = playability?["reason"] as? String ?? status ?? "unavailable"
            MusicSourceDiagnostics.shared.record(
                event: "resolve", source: song.source.rawValue,
                provider: identifier,
                duration: Date().timeIntervalSince(startedAt),
                result: "unplayable", detail: reason
            )
            return nil
        }

        guard let streaming = root["streamingData"] as? [String: Any] else {
            MusicSourceDiagnostics.shared.record(
                event: "resolve", source: song.source.rawValue,
                provider: identifier,
                duration: Date().timeIntervalSince(startedAt),
                result: "no_streaming_data"
            )
            return nil
        }

        if let audioURL = Self.bestDirectAudioURL(in: streaming, quality: quality) {
            MusicSourceDiagnostics.shared.record(
                event: "resolve", source: song.source.rawValue,
                provider: identifier,
                duration: Date().timeIntervalSince(startedAt),
                result: "direct_audio_url"
            )
            return ResolvedMusicResource(
                url: audioURL,
                providerID: identifier,
                providerName: displayName
            )
        }

        if let rawHLS = streaming["hlsManifestUrl"] as? String,
           let hlsURL = URL(string: rawHLS),
           Self.isHTTPURL(hlsURL) {
            MusicSourceDiagnostics.shared.record(
                event: "resolve", source: song.source.rawValue,
                provider: identifier,
                duration: Date().timeIntervalSince(startedAt),
                result: "hls_manifest"
            )
            return ResolvedMusicResource(
                url: hlsURL,
                providerID: identifier,
                providerName: displayName
            )
        }

        // signatureCipher-only formats are deliberately not returned: MusicX
        // does not yet implement YouTube's player-JavaScript signature and n
        // parameter deciphering, so those URLs would be unreliable.
        MusicSourceDiagnostics.shared.record(
            event: "resolve", source: song.source.rawValue,
            provider: identifier,
            duration: Date().timeIntervalSince(startedAt),
            result: "no_direct_stream",
            detail: "Only ciphered formats were available"
        )
        return nil
    }

    private static func bestDirectAudioURL(in streaming: [String: Any], quality: MusicQuality) -> URL? {
        let formats = (streaming["adaptiveFormats"] as? [[String: Any]] ?? [])
            + (streaming["formats"] as? [[String: Any]] ?? [])

        let candidates: [(URL, Int)] = formats.compactMap { format in
            guard let mimeType = format["mimeType"] as? String,
                  mimeType.lowercased().hasPrefix("audio/"),
                  let rawURL = format["url"] as? String,
                  let url = URL(string: rawURL),
                  isHTTPURL(url) else { return nil }

            let bitrate = (format["averageBitrate"] as? Int)
                ?? (format["bitrate"] as? Int)
                ?? 0
            return (url, bitrate)
        }

        guard !candidates.isEmpty else { return nil }

        let target: Int
        switch quality {
        case .standard: target = 160_000
        case .high: target = 320_000
        case .lossless, .hires: target = Int.max
        }

        if target == Int.max {
            return candidates.max(by: { $0.1 < $1.1 })?.0
        }

        let underTarget = candidates.filter { $0.1 <= target }
        if let selected = underTarget.max(by: { $0.1 < $1.1 }) {
            return selected.0
        }
        return candidates.min(by: { $0.1 < $1.1 })?.0
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              !url.absoluteString.contains(where: { $0.isWhitespace }) else {
            return false
        }
        return true
    }
}
