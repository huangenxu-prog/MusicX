# MusicX

A native iOS music player with a source-agnostic playback core.

## Product principles

- Native SwiftUI interface; no account or sign-in requirement.
- Three primary destinations: Home, Search, and Library.
- AVPlayer-based playback core, independent from music providers.
- Pluggable music-source adapters. The initial adapter will be based on the SimpMusic source implementation; additional providers such as LX Music may be evaluated later, subject to their licensing terms.
- Favorites and listening history are stored locally and remain independent of the selected source.

## Planned structure

- `MusicXApp/` — app entry point and app lifecycle
- `DesignSystem/` — colors, typography, reusable components
- `Features/Home/` — recommendations, new releases, albums, charts
- `Features/Search/` — music search
- `Features/Library/` — favorites, recent plays, source selection
- `PlayerCore/` — AVPlayer and playback state
- `MusicSources/` — provider protocol and source adapters
- `LocalStorage/` — local persistence

## Development

All product development takes place on feature branches. The `main` branch is kept stable.

The initial UI target is iOS 17 or later, using Swift and SwiftUI.
