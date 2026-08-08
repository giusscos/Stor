# Stor — Next Steps

## Shipped
- ASC auth, metadata sync/edit/push, snapshot diff
- Keyword popularity (Search Ads), keyword ranking (iTunes Search API)
- Screenshot canvas with drag-to-reposition layers, PNG export, ASC screenshot upload
- Text layer capsule chrome (background fill, padding, corner radius)
- Markdown inline formatting (`**bold**`, `*italic*` only — no per-run color)
- Fit-to-content width/height for text layers

---

## Remaining Features (Prioritized)

### 1. Localization of screenshot text (High priority)
Text layers currently have a single `text` string. To support translated screenshots:
- Add `translations: [String: String]` to `ScreenshotLayer` (locale → text mapping)
- Add a locale selector in the properties panel when a text layer is selected
- Export per-locale: render the canvas once per locale substituting text
- Use the same locale codes already present in `LocalizedMetadata`

### 1b. Rich text (decided)
Stay on **standard Markdown** for locale round-trip. Supported inline: `**bold**`, `*italic*`.
Excluded (not Markdown-native): per-run color, custom fonts per word.
Layer-level color / weight / background remain outside the Markdown body.

### 2. Competitor keyword discovery (Medium priority)
Extend the Keywords tab with a "Discover" mode:
- Fetch the top 10 results for a keyword via iTunes Search API
- Display competitor apps (icon, name, subtitle)
- Tap a competitor to see all keywords you share (intersection of tracked lists)
- This is additive — no new credentials needed, same iTunes Search API as RankingChecker

### 3. Snapshot scheduling / auto-sync (Medium priority)
Let the user set a daily/weekly sync cadence per app:
- Use `BackgroundTasks` framework on macOS (or a simple `Timer` + `NSWorkspace.willSleepNotification`)
- On trigger: call `ASCAPIClient.shared.syncMetadata(appId:)`, insert a new snapshot
- Show a "last synced" badge in the sidebar
- Could also auto-refresh keyword popularity scores on the same schedule

### 4. Keyword position trend chart (Medium priority)
`KeywordRanking` records are already stored — wire them up to a chart:
- Use Swift Charts (iOS/macOS 16+) to show position over time for a selected keyword
- X-axis: date, Y-axis: rank position (inverted — position 1 at top)
- Show "not ranking" gaps as dashes

### 5. App version management (Medium priority)
The app currently always syncs against the latest editable version. Add:
- A version picker in the Listing tab header (fetched from `fetchVersions(appId:)`)
- Allow viewing/editing any in-review or prepare-for-submission version
- Show version state badge (PREPARE_FOR_SUBMISSION, IN_REVIEW, etc.)

### 6. Screenshot set management (Lower priority)
The ASC upload currently creates a new screenshot slot each time. Improve this with:
- Show current ASC screenshot sets per locale/device
- Preview existing screenshots pulled from ASC (via the `imageAsset` URL in screenshot responses)
- Reorder screenshots (ASC supports PATCH on screenshot with a `displayPosition`)
- Delete screenshots

### 7. In-app preview of App Store listing (Lower priority)
Render a read-only mockup of how the app page would look:
- Header: icon (from `iconURL`), name, subtitle, rating placeholder
- Description with "More" truncation
- Screenshot scroll preview
- This is pure local rendering — no API calls needed

### 8. Export metadata as JSON/CSV (Low priority)
Let the user export all snapshots for an app:
- JSON: structured export matching the ASC API response shape
- CSV: one row per locale per snapshot (useful for translation handoff)
- Trigger via File menu or a toolbar item in ListingTabView

### 9. Multi-app batch push (Low priority)
For developers with multiple apps that share the same structure:
- Select N apps in the sidebar
- Push the same "What's New" text to all of them in one click
- Would need to ensure each app has valid localization IDs from a prior Sync

---

## Tech Debt / Polish

| Item | Notes |
|---|---|
| Error handling UX | Currently errors are only logged. Surface them as in-app alerts or inline banners. |
| Screenshot upload progress | Long uploads show no feedback. Add a ProgressView overlay. |
| Ranking rate limiting | iTunes Search API has undocumented rate limits. Add exponential backoff in RankingChecker. |
| JWT expiry handling | ASCAPIClient generates a fresh JWT per request. Cache with a 15-min expiry to reduce overhead. |
| Device frame images | Currently no bundled device frames. Add PNG frames (bezels) to Assets.xcassets for each DeviceType and composite them on export. |
| Keyword deduplication | AddKeywordView silently allows duplicate terms. Add a check before inserting. |
| Search Ads org discovery | SearchAdsCredentials.orgId is optional but required for most orgs. Add a "Fetch Org ID" button that calls the `/v1/me` endpoint. |
| Metadata character limit colors | Yellow warning at 90%, red at 100%. Currently only red at 100%. |
| Offline state | No explicit handling when the Mac has no network. Add a reachability check before API calls. |
| SwiftData iCloud sync | Consider `ModelConfiguration(cloudKitDatabase:)` so data syncs across the user's Macs via CloudKit (no server needed). |
