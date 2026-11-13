# Third-party notices

## Kumone

- Project: [missuo/kumone](https://github.com/missuo/kumone)
- Referenced revision: `dee91a1da699b2ad8dffd2276c80b37b43a72ff2`
- License: GNU Lesser General Public License v3.0 only (LGPL-3.0-only)
- Applicable adapted components:
  - `MusicX/ExternalSuppliers/Kumone/KumoneKugouAudioSourceProvider.swift`
  - `MusicX/ExternalSuppliers/Kumone/KumoneKuwoAudioSourceProvider.swift`
  - `MusicX/ResourceEngine/Matching/AudioSourceTrackMatcher.swift`

The provider request flow and cross-source track-matching approach are adapted from the corresponding Kumone Swift providers. MusicX's resource-engine contracts, catalog integration, diagnostics, provider scheduling, and fallback behavior are maintained independently.

The applicable license text is included at `LICENSES/Kumone-LGPL-3.0.txt`. This notice does not imply endorsement or affiliation with the upstream project.
