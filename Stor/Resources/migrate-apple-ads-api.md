# Migrate to Apple Ads Platform API v1

## Context

Apple released the **Apple Ads Platform API v1** on August 14, 2026. It officially provides
search term popularity and recommendations endpoints. The current Campaign Management API v5
**sunsets January 26, 2027**.

## What needs to change

The app currently fetches keyword popularity scores and recommendations through two mechanisms
that both need to be replaced:

1. **`Stor/Stor/Services/AppleAdsWebClient.swift`** — hits the unofficial dashboard API at
   `https://app-ads.apple.com/cm/api/v2/keywords/popularities` and `/recommendation`,
   authenticated with captured web session cookies (XSRF-TOKEN-CM + cookie header).
   This is fragile and unofficial.

2. **`Stor/Stor/Services/SearchAdsAPIClient.swift`** — uses
   `https://api.searchads.apple.com/api/v5` for campaign management.
   The v5 Campaign Management API **sunsets January 26, 2027**.

## Goal

Migrate popularity and recommendations calls to the new official Platform API v1 endpoints,
remove the web session cookie hack, and update the campaign management base URL from `api/v5`
to `v1`. The WebKit login flow in `Stor/Stor/Onboarding/AppleAdsLoginView.swift` and
`Stor/Stor/Onboarding/AddSearchAdsKeyView.swift` can likely be simplified or removed —
popularity now works with just the `.p8` API key.

The new API almost certainly uses the same OAuth2 client-credentials flow with ES256 JWT
(`.p8` key, clientId, teamId, keyId) already stored in `SearchAdsCredentials` via
`Stor/Stor/Services/KeychainService.swift`.

## Before writing any code

1. Read `SearchAdsAPIClient.swift`, `AppleAdsWebClient.swift`, `AppleAdsLoginView.swift`,
   and `KeychainService.swift` to understand the existing credential model and token cache.
2. Look up the actual Platform API v1 endpoint paths and response schema from Apple's
   developer docs — use the `DocumentationSearch` tool or check
   `developer.apple.com/documentation/apple_ads`.

## Expected outcome

- `AppleAdsWebClient.swift` deleted or gutted — no more cookie/session logic
- `AppleAdsLoginView.swift` removed (WebKit web login no longer needed)
- `SearchAdsAPIClient.swift` base URL updated to v1, popularity/recommendations
  routed through proper OAuth calls
- Users only need the `.p8` API key to get popularity scores — no extra sign-in step
