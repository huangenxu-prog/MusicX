# MusicX Home Visual Assets

The generated Xcode asset pack is provided separately as `MusicX_Home_Assets_Xcode.zip`.

Extract the archive and copy each `*.imageset` directory into the existing `MusicX/Assets.xcassets/` directory. Do not replace the existing asset catalog; merge the image-set folders into it.

The SwiftUI home screen references these asset names:

- `home_hero`
- `daily_recommend`, `featured_playlist`
- `chart_hot`, `chart_rising`, `chart_new`
- `album_01` through `album_05`
- `playlist_relax`, `playlist_night`, `playlist_drive`
- `song_01` through `song_06`
- `guess_01` through `guess_03`
- `player_cover`

No build or IPA release is triggered by this documentation change.
