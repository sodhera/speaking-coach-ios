# AI consent validation — October 3, 2026

- Simulator Debug build succeeded for Speaking Coach 2.0.1, build 23.
- The actual `AIConsent` enum from the source was compiled and exercised in a standalone Foundation harness. Eight behavior checks passed: signed-out refusal, rejection of legacy permission, holding the action, explicit agreement, authenticated-account matching, account isolation, persistence for the original account, and withdrawal. Analytics was stubbed for this isolated check.
- The native app was installed and launched on an iPhone 17 simulator. `disclosure.png` was captured and inspected: both providers and data descriptions are readable, and Allow and Not now are separate actions. Additional disclosure and the policy link are in the scroll view.
- The public policy source passed checks for the provider names, explicit permission, withdrawal, data categories and provider-protection language, and the obsolete Google Cloud AI entry was removed. The public URL returned the new AI-sharing section after the policy push.
- Added XCTest coverage for all AI transport entry points and UI coverage for disclosure, decline and agreement. These test targets compiled, but the Xcode simulator test runner stalled on repeated attempts; the XCTest suites did not complete and are not claimed as passed. The standalone checks do not replace the transport/UI suites.
- App Store upload/review, App Store Connect privacy answers and AI provider account retention/training configuration were not changed or verified. See `docs/legal/ai-sharing-review.md` before submission.

## Compact screen follow-up

- Shortened the on-screen copy, kept both providers and the shared data categories visible, and changed the heading to “Practice with AI” and the explicit agreement button to “Allow and continue”. Permission behavior and disclosure scope are unchanged.
- Added a native link to the full guide at https://www.orecci.com/ai-data-sharing.html and updated the public policy's button wording. The guide was published and checked live in the browser.
- The Debug simulator build passed. `compact-disclosure.png` shows the entire revised screen, both links and both choices on one iPhone 17 screen.
- Updated existing UI assertions for the new wording. The simulator test suite was not rerun for this copy change.
