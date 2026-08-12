# Stor — What Was Built

## Overview
Stor is a **macOS-only** native app (macOS 27+) for indie iOS developers to manage App Store Connect metadata with version history, keyword research, and screenshot creation — all running client-side with credentials stored in the macOS Keychain. No backend relay, no third-party servers.

---

## File Structure

```
Stor/Stor/
├── Models/
│   ├── AppRecord.swift            — @Model: connected app (ascAppId, bundleId, name, snapshots, keywords, templates)
│   ├── MetadataSnapshot.swift     — @Model: timestamped metadata pull (localizations, versionString, versionId)
│   ├── LocalizedMetadata.swift    — @Model: per-locale fields + ASC localization IDs for PATCH calls
│   └── TrackedKeyword.swift       — @Model: keyword + KeywordRanking history (position, checkedAt)
│
├── Services/
│   ├── KeychainService.swift      — Save/load/delete ASCCredentials and SearchAdsCredentials in Keychain
│   ├── ASCJWTGenerator.swift      — ES256 JWT signing with CryptoKit P256; signs with .p8 private key
│   ├── ASCAPIClient.swift         — Full ASC API client: fetch apps/versions/localizations, sync, PATCH, screenshot upload
│   ├── SearchAdsAPIClient.swift   — OAuth2 Campaign API + facade for web-session popularity
│   ├── AppleAdsWebClient.swift    — Apple Ads CM popularities / recommendations (session cookies)
│   └── RankingChecker.swift       — Keyword ranking positions via iTunes Search API (unofficial, isolated module)
│
├── Onboarding/
│   ├── OnboardingView.swift       — First-run welcome screen with trust/privacy messaging
│   ├── AddAPIKeyView.swift        — ASC API credentials form (issuerId, keyId, .p8 import) → Keychain
│   └── AddSearchAdsKeyView.swift  — Search Ads credentials form (clientId, teamId, keyId, orgId, .p8) → Keychain
│
├── Shared/
│   ├── AppSidebarView.swift       — NavigationSplitView sidebar: list of AppRecord + Add/Disconnect menu
│   ├── AddAppView.swift           — Sheet: fetch ASC app list via API, select app, insert AppRecord
│   └── AppDetailView.swift        — Segmented toolbar picker switching between Listing / Keywords / Screenshots
│
├── Listing/
│   ├── ListingTabView.swift       — HSplitView: snapshot history list + metadata panel; Sync + Push + Compare toolbar buttons
│   ├── MetadataDetailView.swift   — Locale picker + snapshot date/version header
│   ├── LocalizationDetailView.swift — All metadata fields with inline editing and character counters; FlowLayout keyword chips
│   └── MetadataDiffView.swift     — Side-by-side Before/After diff for all fields between two snapshots
│
├── Keywords/
│   ├── KeywordsTabView.swift      — Keyword table (popularity bar, ranking column); Refresh Popularity + Check Rankings buttons
│   └── AddKeywordView.swift       — Multi-line keyword input (one per line) + country picker
│
├── Screenshots/
│   ├── ScreenshotTemplate.swift   — @Model: device type, background color, JSON-encoded layers; DeviceType enum with canvas sizes; Color hex helpers
│   └── ScreenshotEditorView.swift — Template list + canvas editor (drag to reposition layers) + properties panel + PNG export + ASC upload
│
├── StorApp.swift                  — @main, .modelContainer for all 6 model types, .defaultSize(1200×750)
└── ContentView.swift              — OnboardingView if no credentials, else NavigationSplitView
```

---

## Feature Breakdown

### Tab 1 — Listing Management

| Feature | Status |
|---|---|
| ASC API auth (JWT/ES256 with .p8) | ✅ |
| Keychain credential storage | ✅ |
| Onboarding flow (Issuer ID, Key ID, .p8 import) | ✅ |
| Fetch apps from ASC | ✅ |
| Add app to sidebar | ✅ |
| Sync metadata (versions + localizations) | ✅ |
| Store localization IDs for PATCH | ✅ |
| Local snapshot storage via SwiftData | ✅ |
| Snapshot history sidebar | ✅ |
| Metadata display (all fields, per-locale) | ✅ |
| Inline field editing with character limits | ✅ |
| Keyword chip display (FlowLayout) | ✅ |
| Push metadata changes back to ASC | ✅ |
| Snapshot diff view (field-level Before/After) | ✅ |

### Tab 2 — Keyword Research

| Feature | Status |
|---|---|
| Keyword list with country selector | ✅ |
| Bulk-add keywords (multi-line input) | ✅ |
| Popularity bar (0–100) | ✅ |
| Search Ads credentials setup | ✅ |
| OAuth2 token exchange + 1h cache | ✅ |
| Keyword popularity via Apple Ads web session (CM) | ✅ |
| Batch refresh popularity scores | ✅ |
| Keyword ranking via iTunes Search API | ✅ |
| Ranking history stored in SwiftData | ✅ |
| Ranking column in keyword table | ✅ |

### Tab 3 — Screenshots

| Feature | Status |
|---|---|
| Template list per app | ✅ |
| Device presets (iPhone 6.7"/6.9"/6.5", iPad Pro 13") | ✅ |
| Background color picker | ✅ |
| Text layers (text, font size, bold, color) | ✅ |
| Image layers (import from file) | ✅ |
| Layer properties panel (sliders for position/size) | ✅ |
| **Drag-to-reposition layers on canvas** | ✅ |
| Canvas preview (live, tappable to select layers) | ✅ |
| PNG export at full resolution (NSGraphicsContext) | ✅ |
| Upload screenshot to ASC | ✅ |

---

## Architecture Decisions

### No backend relay
All API calls go directly from the user's Mac to Apple's servers. Credentials live in the macOS Keychain. This is both a technical simplification and a trust/privacy selling point.

### SwiftData for persistence
Metadata snapshots, localizations, keywords, and rankings are stored locally. This enables version diffing and historical trend views without any cloud sync.

### Versioning via snapshots
Every Sync creates a new `MetadataSnapshot` timestamped to the current moment. The diff engine compares any two snapshots field-by-field. Apple provides no changelog feature — this is all custom.

### Ranking module is isolated
The `RankingChecker` uses the public iTunes Search API (no auth required). This module is kept isolated so it can be swapped, rate-limited, or disabled independently. It carries policy/reliability risk by design.

### MainActor default
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means all types are implicitly `@MainActor` — no need to annotate every view. URLSession awaits work correctly since they suspend rather than block.
