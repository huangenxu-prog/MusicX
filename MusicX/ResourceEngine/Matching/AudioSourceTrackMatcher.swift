import Foundation

/// Kumone-inspired matching rules shared by independent supplier providers.
enum AudioSourceTrackMatcher {
    static func matches(
        original: MusicSong,
        candidateTitle: String,
        candidateArtist: String,
        candidateDuration: TimeInterval? = nil,
        candidateAlbum: String? = nil,
        requireDuration: Bool = false
    ) -> Bool {
        let expectedTitle = normalized(original.title)
        let actualTitle = normalized(candidateTitle)
        guard !expectedTitle.isEmpty, expectedTitle == actualTitle else { return false }

        // Prevent studio/live/remix/instrumental editions from being mixed.
        guard versionMarkers(in: original.title) == versionMarkers(in: candidateTitle) else {
            return false
        }

        let expectedArtists = Set(artistParts(original.artist))
        let actualArtists = Set(artistParts(candidateArtist))
        guard !expectedArtists.isDisjoint(with: actualArtists) else { return false }

        // Duration is a useful identity signal when both catalogs provide it.
        // Catalogs can differ slightly due to silence/encoding, so allow a small
        // tolerance instead of requiring byte-for-byte metadata equality.
        let expectedDuration = original.duration.flatMap { $0 > 0 ? $0 : nil }
        let actualDuration = candidateDuration.flatMap { $0 > 0 ? $0 : nil }

        if requireDuration && (expectedDuration == nil || actualDuration == nil) {
            return false
        }

        if let expectedDuration, let actualDuration {
            let tolerance = min(10, max(5, expectedDuration * 0.03))
            guard abs(expectedDuration - actualDuration) <= tolerance else {
                return false
            }
        }

        return true
    }

    static func durationDifference(original: MusicSong, candidateDuration: TimeInterval?) -> TimeInterval {
        guard let expected = original.duration, let actual = candidateDuration,
              expected > 0, actual > 0 else {
            return .greatestFiniteMagnitude
        }
        return abs(expected - actual)
    }

    private static func artistParts(_ value: String) -> [String] {
        let withoutFeaturedCredits = value.replacingOccurrences(
            of: #"(?i)\\s+(?:feat\\.?|ft\\.?|featuring|with)\\s+"#,
            with: ";",
            options: .regularExpression
        )
        return withoutFeaturedCredits
            .split(whereSeparator: { "/&＆、,，;；".contains($0) })
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .unicodeScalars
        .filter(CharacterSet.alphanumerics.contains)
        .map(String.init)
        .joined()
    }

    private static func versionMarkers(in value: String) -> Set<String> {
        let text = value.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let tokenSet = Set(tokens)
        var markers = Set<String>()

        let englishMarkers = [
            "live", "remix", "instrumental", "cover", "acoustic", "demo",
            "remaster", "slowed", "dj", "karaoke"
        ]
        markers.formUnion(englishMarkers.filter { tokenSet.contains($0) })

        if tokens.count >= 2 {
            for index in 0..<(tokens.count - 1) {
                let phrase = tokens[index] + " " + tokens[index + 1]
                if phrase == "sped up" { markers.insert("sped up") }
            }
        }

        let chineseMarkers = [
            "伴奏", "纯音乐", "现场", "演唱会", "翻唱", "不插电",
            "示范", "合唱", "重制", "加速", "降速"
        ]
        markers.formUnion(chineseMarkers.filter { text.contains($0) })
        return markers
    }
}
