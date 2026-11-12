# MusicX Home Visual Assets

## Current asset-catalog state

The 24 individual homepage image sets are already present in
`MusicX/Assets.xcassets/`. Each expected image set contains its
`Contents.json` and matching JPG file.

`MusicX/Features/Home/HomeArtwork.swift` implements the display priority:

1. Load the matching individual asset-catalog image set when available.
2. Fall back to `HomeArtworkSheet.imageset` when the individual image is
   unavailable.

The 24 individual asset names are:

- `home_hero`, `daily_recommend`, `featured_playlist`
- `chart_hot`, `chart_rising`, `chart_new`
- `album_01` through `album_05`
- `playlist_relax`, `playlist_night`, `playlist_drive`
- `song_01` through `song_06`
- `guess_01` through `guess_03`
- `player_cover`

The vector fallback is retained at
`MusicX/Assets.xcassets/HomeArtworkSheet.imageset/`. Do not re-import the
24-image pack or remove the fallback unless the asset set is intentionally
being replaced.

## Validation

The repository script `scripts/validate-home-assets.py` checks the expected
24 image-set directories, their JPG files, and the corresponding
`Contents.json` references.

Asset-file presence does not by itself verify that the images visually match
the design references or that they render correctly on a device. Those still
require visual/device validation.

No build, IPA, release, or main-branch update is performed by this documentation update.
