# MusicX Home Visual Assets

The current homepage branch uses one vector artwork sheet and a small SwiftUI crop view:

- `MusicX/Assets.xcassets/HomeArtworkSheet.imageset/`
- `MusicX/Features/Home/HomeArtwork.swift`

The sheet contains 24 distinct artwork tiles. `HomeArtwork(name:)` crops the correct tile for the homepage card's aspect ratio. The asset names are listed in `HomeArtwork.swift`.

A separate high-resolution photographic pack is available as `MusicX_Home_Assets_Xcode.zip`. It contains individual JPG image sets for replacing the vector artwork when the photographic art direction is ready to be wired into the app. Do not copy it over the existing asset catalog; merge only the selected image sets.

No build, IPA, release, or main-branch update is performed by these changes.
