# Privacy policy update: product analytics

**Status:** Draft for the Speaking Coach privacy policy. This copy is kept in this repository; it has not been published to orecci.com.

**Suggested effective date:** 26 September 2026

## Add under “What information do we collect?”

### Product analytics

Speaking Coach records product-usage events so we can understand how people move through the app and improve the experience. These events may include the screen or onboarding step opened, whether you continued or left it, time spent on a screen, and selections from fixed-choice onboarding questions. Fixed-choice values may include your selected language, speaking category and situation, timing, readiness rating (0–10), ratings of predefined speaking challenges, selected costs, and desired outcomes.

First-party analytics records sent to our backend may include a randomly generated app-install identifier, a visit identifier, the event time, the relevant screen or step number, and, if you are signed in, your account identifier. When PostHog analytics is enabled in the app build, PostHog receives page and onboarding-choice events, a visit identifier, its SDK's anonymous identifier, and standard app and device information such as app version, device type, and operating-system version. PostHog also receives the network request's IP address; it may use that address to estimate general location.

Analytics events do not include your name, free-text onboarding responses, or the words you speak during a practice session. We do not use these analytics events for advertising or to track you across other companies' apps and websites.

## Add under “How do we use your information?”

We use product-usage information to measure onboarding and feature engagement, understand where people stop or continue, and improve Speaking Coach. We use fixed-choice onboarding responses to understand which practice needs and goals the app should support.

## Add under “When and with whom do we share your personal information?”

We use Supabase to receive and store first-party app page, action, timing, and step events, and PostHog as an analytics service provider when PostHog is enabled in the app build. These providers process the event data and related identifiers on our behalf to operate the analytics service and help us understand product usage. The PostHog endpoint configured for the app is its US-hosted service. We do not send names, free-text responses, or practice speech to these analytics providers as analytics event properties.

## Before publishing this copy

- Confirm the PostHog SDK's standard properties and IP/geolocation behavior against the exact SDK version and production configuration.
- Confirm the PostHog project retention setting and the backend event retention/deletion behavior, then align the existing retention section if needed.
- Keep the App Store privacy answers aligned with the app binary and every included SDK. Those answers are drafted separately in `app-store-privacy-disclosure-draft.md` and have not been submitted.
