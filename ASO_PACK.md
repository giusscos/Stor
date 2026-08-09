# Stor — Full ASO Pack (Future)

This document describes the complete App Store Optimization feature set beyond **Competitor Keyword Compare v1**. Use it as the roadmap when expanding Keywords / Discover / Compare / Suggest.

## What v1 already ships

| Capability | Status |
|---|---|
| Track keywords per app/country | Shipped |
| Popularity via Apple Search Ads spotlight | Shipped |
| Your app’s organic rank (iTunes Search top 200) | Shipped |
| Discover: top SERP apps for a keyword | v1 |
| Save competitors per app | v1 |
| Side-by-side rank table (you vs competitors) | v1 |
| Light suggestions (spotlight related + competitor listing keywords) | v1 |
| Shared-keyword hint (both in top 200) | v1 |

See Keywords tab: Discover, Compare, Suggest.

---

## Phase map (v1 → full pack)

```
v1 Discover/Compare/Suggest
        │
        ├─► Opportunity & difficulty scoring
        ├─► Rank trend charts (your history already stored)
        ├─► Reverse-SERP / “keywords they rank for”
        ├─► ASC Analytics Search Terms
        ├─► Listing keyword budget helper (100-char field)
        └─► Auto-refresh / scheduling hooks
```

---

## 1. Opportunity & difficulty scoring

**Goal:** Rank suggested and tracked terms by *worth chasing*, not only raw popularity.

**Inputs (all local / already available APIs):**
- Popularity 0–100 (Search Ads)
- SERP density from `RankingChecker.search` (how many strong apps in top 10)
- Optional: average userRating / ratingCount of top results from iTunes Search
- Your current position (nil / >200 vs top 10)

**Suggested formula (tune later):**

```
competition = clamp(avgTop10Strength, 0…1)   // from ratings / brand apps in SERP
opportunity = popularity * (1 - competition)
```

Surface as a column on Suggest and Compare. Persist nothing new unless caching becomes necessary.

---

## 2. Rank trend charts

**Goal:** Visualize position over time for a selected keyword.

**Data:** `KeywordRanking` on `TrackedKeyword` is already appended on each “Check Rankings”.

**UI:**
- Swift Charts
- X = `checkedAt`, Y = `position` (inverted so #1 is at top)
- Gaps / nil position as dashed “not ranking” segments
- Optional: overlay competitor series from `CompetitorKeywordRanking` once history is dense enough

Also listed in `NEXT_STEPS.md` §4.

---

## 3. Reverse-SERP / “keywords they rank for”

**Goal:** Approximate which terms a competitor ranks for without a third-party keyword DB.

**Approach:**
1. Seed from competitor listing keywords + title/subtitle tokens (Lookup)
2. Expand via Search Ads spotlight suggestions around those seeds
3. For each candidate, run SERP and record whether the competitor appears in top N
4. Store results on `CompetitorKeywordRanking` (or a dedicated inventory table)

**Limits:** Expensive (rate limits), incomplete vs Sensor Tower–class DBs. Batch with delays; prefer user-triggered “Scan competitor” over continuous crawl.

---

## 4. ASC Analytics Search Terms

**Goal:** Official demand signal for *your* installs (terms that led to find/install).

**Source:** App Store Connect Analytics / Reports — Search Terms (not implemented today; no client in repo).

**Use:**
- Import as tracked keywords
- Bias Suggest toward terms with proven conversion for your app
- Combine with popularity for “proven + popular” filter

Requires ASC credentials already in Keychain; new API surface in `ASCAPIClient` (or a sibling analytics client).

---

## 5. Listing keyword budget helper

**Goal:** Help fill the ASC metadata `keywords` field (100-character limit) optimally.

**UI (Listing or Suggest):**
- Live character count with remaining budget
- Suggest swaps: drop low-opportunity tracked terms, add high-opportunity unused ones
- One-click “Apply to draft localization” (PATCH via existing ASC flow)
- Respect comma-separated format; no spaces after commas (Apple convention)

Do **not** auto-push in v1 of this helper — stage into the draft localization only.

---

## 6. Auto-refresh / scheduling

**Goal:** Keep popularity and ranks fresh without manual clicks.

Hooks (see also `NEXT_STEPS.md` §3 Snapshot scheduling):
- On the same daily/weekly cadence: refresh Search Ads popularity for tracked keywords
- Optionally re-check your ranks + saved competitors for the active country
- Persist “last ASO refresh” on `AppRecord`
- Backoff / jitter in `RankingChecker` (tech debt already calls this out)

---

## 7. Polish & data model extensions (when needed)

| Item | Notes |
|---|---|
| `CompetitorApp` metadata cache | Last Lookup pull (keywords string, description) + timestamp |
| Suggestion cache | Avoid re-hitting Search Ads for the same seed/country within N hours |
| Difficulty column on TrackedKeyword | Optional denormalized `difficultyScore` / `opportunityScore` |
| Multi-competitor SERP highlight | In Discover, badge all saved competitors in the top 10 |
| Export | CSV of compare table for sharing with contractors |

---

## Non-goals / constraints

- No third-party ASO SaaS dependency; stay client-side (ASC + Search Ads + iTunes Search/Lookup).
- iTunes Search rate limits are undocumented — batch small, delay between calls.
- Competitor listing keywords from Lookup are **live public** metadata only (not drafts).
- There is no official “rank for keyword” API; SERP scraping remains best-effort.

---

## Implementation order (when picking this up)

1. Rank trend chart (data already stored — quick win)
2. Opportunity score on Suggest rows
3. Listing keyword budget helper
4. ASC Search Terms import
5. Reverse-SERP competitor inventory
6. Scheduled refresh + RankingChecker backoff
