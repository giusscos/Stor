# Stor — Project Brief

## What it is
A **macOS-only** native app for indie/solo iOS developers to manage App Store Connect (ASC) metadata with **version history/diffing** (like git for your app listing), plus **ASO keyword research and ranking tracking**, similar to tryastro.app.

## Platform & stack
- **macOS only** for v1 (no iOS/web)
- **SwiftUI** recommended — native feel, good fit for a metadata-editing/dashboard UI
- Local persistent storage: **SwiftData** or **CoreData** for snapshot/version history
- API keys and credentials stored in **macOS Keychain**, never sent to a third-party server
- All requests made **client-side, directly from the user's device** — no backend relay (this is both simpler and a trust/privacy selling point, matches what competitor ASO.dev does)

---

## Tab 1 — Listing Management & Versioning

### Purpose
Read, edit, and track the history of an app's App Store Connect metadata (description, keywords field, promotional text, screenshots, localizations, etc.) with a changelog/diff view showing what changed between versions.

### Data source: App Store Connect API
- **Official, sanctioned API** — fully capable of reading and writing metadata
- Requires an **API key** generated in App Store Connect → Users and Access → Keys:
  - Issuer ID
  - Key ID
  - `.p8` private key file
- Auth is JWT-based (sign requests using the private key)
- Supports: app info, localized metadata, screenshot/video uploads, app versions, localizations

### What Apple does NOT give you
- No built-in "version history" or diff/changelog feature — ASC only shows current + pending state
- **You must build the versioning yourself**: on every pull/sync, save a timestamped snapshot (JSON blob) of the metadata locally, then diff each new snapshot against the previous one to generate a changelog view

### Core features to build
- Connect app via ASC API key (stored in Keychain)
- Pull current + draft metadata for each localization
- Local snapshot on every sync → SQLite/CoreData/SwiftData table of timestamped metadata blobs
- Diff engine: compare snapshots, highlight field-level changes (like a git diff)
- Edit metadata locally, push changes back via ASC API
- Rollback capability (revert to a prior snapshot, or at least view/copy old values)
- **Screenshot management:**
  - Upload/manage screenshot sets via ASC API (this part is supported)
  - **Screenshot creation/generation is NOT provided by Apple** — build this yourself: device frame compositing, text overlays, localized templates (Core Graphics / Core Image, or a template system)
- Bulk editing across localizations (nice-to-have, seen in competitor ASO.dev)

---

## Tab 2 — Keyword Research & Ranking

### Two distinct data needs — handled very differently

**1. Keyword popularity/demand — OFFICIAL, sanctioned**
- Use the **Apple Search Ads API**
- Returns a **popularity score (0–100)** per keyword/locale
- This is *demand*, not your ranking — clean, stable, well-documented, no scraping needed
- "Difficulty" score is typically a derived/custom metric (e.g., combine popularity with strength/number of competing apps) — this is your own logic, not something Apple provides directly

**2. Actual keyword ranking position — UNOFFICIAL, no API exists**
- **There is no Apple API that returns "your app ranks #4 for keyword X."**
- The entire ASO industry (Astro, AppFigures, Sensor Tower, etc.) gets this by **programmatically running searches against the App Store's search endpoint** for each keyword/country and detecting your app's position in the results — i.e., scraping
- This is **not officially sanctioned** by Apple's terms and carries real risks:
  - Can break without notice if Apple changes the search backend
  - Risk of rate-limiting/IP blocks at scale
  - Ongoing maintenance burden, not a one-time integration
- Evidence this is exactly how Astro operates: batch/scheduled update windows (not real-time), and release notes referencing device date/time correctness "required for authentication" — consistent with a custom, semi-authenticated request pipeline built by them
- **Decision point for you:** build a scraping layer yourself (more powerful, fragile, higher maintenance) vs. start with Apple's own limited analytics and defer full rank tracking

### Legitimate supplementary data source
- **App Store Connect Analytics — "Search Terms" report**: shows terms people used before finding/installing your app, bucketed by popularity (not exact numbers, not your rank, but official and stable)

### Other useful public source
- **iTunes Lookup API** (public, no auth): `https://itunes.apple.com/lookup?id=...` — pulls any public app's *current live* metadata (yours or competitors'). Good for competitor metadata comparison, but only current public data, no drafts/history.

### Core features to build
- Keyword list management per app (add/import, tag, filter)
- Popularity score via Apple Search Ads API
- Custom difficulty score (your own formula)
- Ranking check per keyword/country (via your own search-scraping pipeline — the main engineering investment)
- Historical ranking trend (store daily/periodic snapshots locally)
- Competitor keyword discovery (find which keywords a competitor app ranks for)
- Country/locale switching

---

## Referencing apps — two mechanisms

| Need | Use | Auth | Gives you |
|---|---|---|---|
| Your own app (edit/read drafts, push changes, full history) | **App Store Connect API** | API key (Issuer ID, Key ID, `.p8`) | Full read/write, all localizations, drafts + live |
| Any public app (competitor lookup, current metadata only) | **iTunes Lookup API** | None | Live public metadata only, no drafts/history |

---

## Known limitations / risks to design around
1. **No official ranking-position API** — this is the single biggest technical risk in the product. Everything else (metadata CRUD, popularity scores) is clean and API-based.
2. **Versioning/diffing is entirely custom** — Apple gives you no changelog feature; it's local snapshotting + your own diff logic.
3. **Screenshot generation is entirely custom** — Apple only handles upload/storage, not creation.
4. A scraping-based ranking pipeline needs ongoing maintenance and carries policy/reliability risk — treat it as a distinct, isolated module so it can be swapped out or hardened independently of the core app.

---

## Suggested build order
1. ASC API auth + Keychain storage
2. Pull/display current metadata (read-only) for a connected app
3. Local snapshot storage + diff/changelog UI (Tab 1 core loop)
4. Metadata editing + push back to ASC
5. Apple Search Ads API integration → keyword popularity (Tab 2, safe part)
6. Screenshot upload via ASC API
7. Screenshot *creation* tooling (templates, device frames)
8. Ranking-position tracking module (scraping pipeline) — build last, isolate it, expect iteration
9. Competitor keyword discovery via iTunes Lookup + ranking module
