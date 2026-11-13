# MusicX Editorial Content Aggregation

## Product requirement

MusicX does not operate or manually curate its own music catalog. The five domestic platform sources are responsible for editorial programming and content updates; MusicX aggregates, normalizes, presents, and plays that content.

Primary sources:
- NetEase Cloud Music (`netease`)
- QQ Music (`qq`)
- Kugou Music (`kugou`)
- Kuwo Music (`kuwo`)
- Migu Music (`migu`)

YouTube Music is an optional overseas fallback source only. It is not part of the default mainland-China editorial catalog.

## Homepage content slots

| Homepage slot | Preferred upstream content | MusicX responsibility |
|---|---|---|
| Charts | Platform charts | Aggregate chart metadata and tracks |
| Daily recommendations | Platform daily/recommended feeds | Refresh and normalize daily content |
| Featured playlists | Platform editorial / official topic collections | Aggregate roughly 24 high-quality collections as an initial target |
| Featured songs | Platform editorial song picks | Merge duplicates without losing source provenance |
| Albums | Platform album catalog / official recommendations | Normalize album metadata and load real album tracks |

The target of 24 featured collections is a display target, not a hard-coded catalog limit. The actual number depends on valid, available, non-duplicate upstream editorial content.

## Editorial provenance rules

Do not equate playlist search results or user-created playlists with official editorial collections.

Every collection must retain:
- source platform and source-specific collection ID;
- source collection title, description, artwork, creator/editor label, and track count when provided;
- upstream collection type (official editorial, platform recommendation, category feed, or unverified search result);
- source URL when available;
- last successful refresh time and cache freshness.

Only items whose upstream endpoint or metadata provides defensible platform/editorial provenance may be labeled as official editorial. Platform recommendation feeds and category feeds must keep their own distinct provenance labels. Search results must never be silently promoted to official editorial content.

## Playback and cross-source fallback

A collection's source is the source of its editorial metadata, not a restriction on playback.

When a user opens a collection:
1. Load the original collection's actual track list and preserve its order.
2. Keep the original track metadata and collection provenance.
3. Resolve a playable resource using the resource engine.
4. If the original source is unavailable, search the other domestic sources.
5. Match conservatively using normalized title, artist, duration, album, and version markers.
6. Do not substitute live, remix, cover, karaoke, instrumental, or other materially different versions unless the user explicitly selected that version.
7. Re-resolve expired URLs and retry other providers on transient failures.
8. If no sufficiently confident match exists, mark that track unavailable rather than playing a wrong recording.

Playback success is never guaranteed solely because a track appears in an official collection. Copyright, account entitlement, region, network, and URL expiry can still prevent playback.

## Architecture

- Catalog discovery: source-specific clients fetch official recommendations, editorial collections, categories, and chart metadata.
- Normalized catalog model: common collection/song structures retain source IDs and provenance.
- Catalog cache: cache metadata and collection track lists independently, with different refresh windows.
- Resource engine: resolves playable resources independently from catalog origin, with conservative cross-source matching and provider fallback.
- UI: homepage and collection detail pages consume normalized models; no UI source picker is exposed.

## Current implementation gap (baseline branch: architecture/three-layer-resource-engine)

- Playlist search currently merges QQ and NetEase search results only.
- Existing featured-playlist page uses six fixed keyword buckets and fuzzy name matching. It can select ordinary search results and is not a true five-platform official editorial feed.
- Source-aware collection-track loading currently supports QQ and NetEase only.
- Kugou, Kuwo, and Migu do not yet have integrated editorial discovery and collection-detail loading in MusicX.
- Existing homepage visual design is out of scope for this data-layer change and must remain unchanged.

## Implementation sequence

1. Replace keyword-bucket featured playlist discovery with a source-aware editorial collection catalog.
2. Add native discovery/detail adapters for the five domestic platforms, using platform endpoints and preserving provenance. Do not rely on a third-party server; the app remains direct-to-source.
3. Select and rank approximately 24 valid collections from the real feeds, deduplicate by source ID and normalized content identity, and avoid duplicate cards.
4. Add source-aware collection detail loading for all five platforms.
5. Route collection tracks through the existing Resource Engine for automatic cross-source playback fallback.
6. Add cache freshness, partial-source failure handling, and diagnostics.
7. Keep the existing homepage UI unchanged; only replace the data source and route behavior.
8. Validate each source's live endpoint and real playback before producing the single final IPA.

## Dependency and compliance notes

Unofficial endpoints can change or impose access limits. Keep each source adapter isolated, use timeouts and caching, and degrade gracefully when a provider fails. Respect upstream terms, rights, regional restrictions, and any attribution requirements. Do not describe an unofficial endpoint as an official API.
