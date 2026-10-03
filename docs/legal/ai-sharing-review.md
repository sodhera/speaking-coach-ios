# AI sharing review and release verification

The iOS app discloses and requests permission before sharing data with ElevenLabs or OpenAI. Consent disclosure version 2 covers live audio, recorded practice and answer audio, transcripts, custom situations, CV/job-post/interview-note text, and presentation text and context. Earlier version 1 permission is deliberately not migrated. Permission is stored per signed-in account and device, and can be withdrawn in Settings → AI data sharing.

Transport checks reject practice, custom-situation, transcription, presentation feedback/questions, PowerPoint conversion and live voice calls without permission. The screen gates hold the action until explicit agreement. Declining or dismissing does not start the pending action. The PowerPoint import gate also covers its non-AI backend upload. Microphone permission is separate.

## App Review notes for the next submitted build

Speaking Coach uses ElevenLabs for live voice conversations and audio transcription, and OpenAI for custom-situation evaluation, practice feedback and presentation questions/answer feedback. Before the first transfer, the app shows “Allow AI data sharing?” with the providers, data categories and uses, a working Privacy Policy link, “Allow AI data sharing” and “Not now”. Only an explicit Allow unlocks the feature. Existing users must accept the expanded disclosure again. Review or withdraw permission in Settings → AI data sharing. Withdrawing blocks subsequent transfers. CV and job-post text are disclosed in interview setup as well. The public policy describes the data flows, provider protections and deletion requests.

## Before submitting

- Build and submit a new binary containing this change. A source push does not update an installed App Store build.
- Check the live policy at https://www.orecci.com/privacy-policy.html for the October 3, 2026 AI-sharing section.
- Verify App Store Connect privacy answers cover audio data, user content (including documents and transcripts), account information, purchases and product analytics as applicable to the current implementation. Copy the review notes above into App Review Information.
- Verify the company ElevenLabs/OpenAI accounts' applicable processing agreements, actual retention and training settings, and the live ElevenLabs agents' subprocessors. Public terms alone do not prove an account's configuration. Do not claim zero retention or no provider training without this evidence. Changes to account settings require the user's explicit authorization.
- Repeat consent tests after adding a provider, new shared data category or new AI route. Update both the in-app disclosure and public policy, and increment `AIConsent.version` when the scope changes.

## Regression coverage

`AIConsentTests` checks old-consent rejection, account isolation, signed-out behavior, held actions, withdrawal and transport refusal before networking. `AIConsentUITests` checks the provider disclosure, policy link, decline and explicit allow with the production gate and inert review content.

These checks do not guarantee Apple's approval or verify provider account settings, App Store Connect metadata, or a production release.
