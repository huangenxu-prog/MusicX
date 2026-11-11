# MusicX Home Visual Assets

The homepage currently uses a single 4×6 vector artwork sheet as a guaranteed fallback:

- `MusicX/Assets.xcassets/HomeArtworkSheet.imageset/`
- `MusicX/Features/Home/HomeArtwork.swift`

`HomeArtwork(name:)` now prefers a matching individual asset-catalog image set (for example, `home_hero.imageset`) whenever one is present, and falls back to the vector sheet when it is absent. This lets the photographic pack replace the vector art without further view-code changes.

The 24-image photographic pack is supplied separately as `MusicX_Home_Assets_Xcode.zip`. Its 24 image sets have been checked: each `Contents.json` points to an existing JPG. The pack has **not yet been copied into this repository's asset catalog**, so the current app still renders the vector fallback.

To complete the photographic pass, merge the 24 `.imageset` folders from that ZIP into `MusicX/Assets.xcassets/`. Do not replace the existing `HomeArtworkSheet.imageset`; it remains the fallback.

No build, IPA, release, or main-branch update is performed by these changes.
