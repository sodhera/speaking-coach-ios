# Speaking Coach App Store privacy: analytics selections

This document provides the analytics-related answers for the App Privacy form, based on the app's analytics implementation in this repository. It does not include data collected by other app features or SDKs.

## Data collection

**Does the app collect data?** Yes. The app sends analytics events to Supabase. When a PostHog project token is included in the build, it also sends the configured analytics events to PostHog.

Select these analytics-related data types:

| Data type | Linked to the user? | Purpose | Basis in the app |
| --- | --- | --- | --- |
| Product Interaction | Yes | Analytics | Screen and onboarding-step entry, exit, duration, actions, and fixed-choice onboarding selections. Events include visit or app-install identifiers. |
| User ID | Yes | Analytics | First-party page events can include the signed-in Supabase account UUID. |
| Device ID | Yes | Analytics | First-party page events include a persistent random app-install UUID. PostHog also attaches its SDK identifier when enabled. |
| Coarse Location | Yes | Analytics | PostHog receives the request IP address and can derive general location from it. |

## Tracking

**Does the app use data for tracking as Apple defines it?** No. The app does not use analytics data for targeted advertising, advertising measurement, or sharing with a data broker. The PostHog integration disables automatic screen-view capture, element-interaction capture, application-lifecycle capture, and session replay.

## Data excluded from analytics events

The explicit analytics events do not contain names, free-text onboarding responses, or spoken practice content. This statement applies to analytics events; it does not describe data processed by voice-practice, authentication, subscription, or other app features.

Apple requires App Privacy answers to include the app and relevant third-party SDK collection practices, and to match the app version being distributed. These selections cover the analytics implementation only. Reconcile them with the rest of the app's data flows before submitting the complete App Privacy form.

Apple's definitions and current instructions are in [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) and [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy).
