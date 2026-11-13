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
        // Cross-source identity is intentionally based only on normalized title
        // and artist. Duration, album, and release/version metadata are not
        // reliable across catalog providers and must not reject a valid match.
        let expectedTitle = normalized(original.title)
        let actualTitle = normalized(candidateTitle)
        guard !expectedTitle.isEmpty, expectedTitle == actualTitle else { return false }

        let expectedArtists = Set(artistParts(original.artist))
        let actualArtists = Set(artistParts(candidateArtist))
        return !expectedArtists.isDisjoint(with: actualArtists)
    }

    static func durationDifference(original: MusicSong, candidateDuration: TimeInterval?) -> TimeInterval {
        guard let expected = original.duration, let actual = candidateDuration else {
            return .greatestFiniteMagnitude
        }
        return abs(expected - actual)
    }

    private static func artistParts(_ value: String) -> [String] {
        let withoutFeaturedCredits = value.replacingOccurrences(
            of: #"(?i)\s+(?:feat\.?|ft\.?|featuring|with)\s+"#,
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

        // English version labels must be complete tokens. Substring matching
        // incorrectly classifies ordinary titles such as "Believe" as "Live"
        // and "Discover" as "Cover".
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

        // Chinese labels do not have whitespace-delimited word boundaries,
        // so retain substring matching for these explicit version terms.
        let chineseMarkers = [
            "伴奏", "纯音乐", "现场", "演唱会", "翻唱", "不插电",
            "示范", "合唱", "重制", "加速", "降速"
        ]
        markers.formUnion(chineseMarkers.filter { text.contains($0) })
        return markers
    }
}
