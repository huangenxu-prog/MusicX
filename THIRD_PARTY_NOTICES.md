# Third-party notices

## Kumone

- Project: [missuo/kumone](https://github.com/missuo/kumone)
- Referenced revision: `dee91a1da699b2ad8dffd2276c80b37b43a72ff2`
- License: GNU Lesser General Public License v3.0 only (LGPL-3.0-only)
- Applicable adapted components:
  - `MusicX/ExternalSuppliers/Kumone/KumoneKugouAudioSourceProvider.swift`
  - `MusicX/ExternalSuppliers/Kumone/KumoneAudioSourceProviders.swift` (pyncmd and Kuwo adapters)
  - `MusicX/ResourceEngine/Matching/AudioSourceTrackMatcher.swift`

The provider request flow and cross-source track-matching approach are adapted from the corresponding Kumone Swift providers. MusicX's resource-engine contracts, catalog integration, diagnostics, provider scheduling, and fallback behavior are maintained independently. The pyncmd adapter is limited to NetEase-native track IDs, matching Kumone's upstream source identifier (`netease`).

The applicable LGPL-3.0-only text is included at `LICENSES/Kumone-LGPL-3.0.txt`; the accompanying GPL-3.0 text distributed by upstream is included at `LICENSES/Kumone-GPL-3.0.txt`. This notice does not imply endorsement or affiliation with the upstream project.
