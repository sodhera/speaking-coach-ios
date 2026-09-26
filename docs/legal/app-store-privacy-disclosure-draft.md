# App Store privacy disclosure: analytics draft

**Status:** Preparation notes only. Nothing has been changed in App Store Connect.

This is a proposed starting point for the App Privacy form based on the current Speaking Coach source. Apple requires disclosures to include the app and its third-party SDKs, and the answers apply across the app's platforms. Recheck against the exact release binary and all SDKs before submitting.

## Analytics data to review in App Store Connect

| Apple data type | Why it appears relevant | Draft use and linkage |
| --- | --- | --- |
| Product Interaction | The app explicitly records screen/step entry, exit, duration, primary actions, and fixed-choice onboarding responses. | App Functionality and Analytics. Linked to the app-install/visit identifiers; first-party event records can also carry the signed-in account UUID. |
| User ID | First-party page events include the signed-in Supabase account UUID when the user is authenticated. | App Functionality and Analytics. Linked to the user's account. |
| Device ID | First-party events use a persistent random app-install UUID; PostHog also uses its SDK distinct identifier when enabled. | Analytics. Treat as linked to the app instance/user for disclosure purposes. |
| Coarse Location | The PostHog SDK request includes an IP address, which can be used to estimate general location. | Analytics. Confirm exact PostHog IP and geolocation settings before selecting this type. |

## Tracking

The source config disables PostHog screen-view capture, element-interaction capture, application-lifecycle capture, and session replay. The app does not use analytics for cross-company advertising or advertising measurement. The source reviewed here does not indicate App Tracking Transparency tracking; confirm this against the release binary and every included SDK before answering the tracking question.

## Scope and exclusions

- PostHog is configured only when a project token is supplied to the build. The checked-in configuration leaves the token blank by default and includes an ignored local secrets file when present.
- The explicitly captured analytics events exclude names, free-text answers, and spoken practice content.
- Do not mark crash data, performance data, contact details, or audio as collected by analytics based on this code alone. Review the complete release binary and SDK behavior separately.
- Apple's form requires the developer to decide whether each data type is linked to the user and to select every applicable purpose. This draft deliberately flags identity linkage wherever the code supplies stable or account identifiers.

Apple's current workflow and disclosure requirements are documented in [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy) and [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).
