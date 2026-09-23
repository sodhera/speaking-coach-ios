# Speaking Coach Design System: Morning Stage

Speaking Coach is the daytime sibling of SleepBlock. SleepBlock is a quiet night that deepens toward sleep. Speaking Coach is a warm morning whose light **gathers** as the user commits, so the brightest moment on screen is the moment they decide to practice.

## Principles

- **One accent.** The icon's coral (`#FF5A5F`) is the only brand color. On paper it is a fill. Text and glyphs that need contrast use `coralDeep`.
- **Warm ink, never black. Paper, never white.** White has no temperature, and glass over flat white is invisible.
- **DM Sans everywhere**, as in SleepBlock: hero (600), title (500), body (400) and label (500), with optical size mapped to point size. No serif.
- **One primary action per screen.** It stays inert for 900ms after a step arrives (`Motion.settle`).
- **Steps fade, they don't slide.** Out fast, in slower, and two steps are never on screen at once.
- **Light on text.** A kicker, one big thing, and one line. Visuals and the user's own answers carry the argument, not paragraphs.
- **Nothing invented.** No made-up stats, testimonials or projections. Every figure is something the user told us or a cited fact.

## The stage

`MorningStage(depth:)` is a five-stop paper-to-peach sky with a sunrise glowing up from below the bottom edge, slow sound ripples rising off it, and a fine paper grain. `depth` (0 → 1) raises and warms the sun as the user moves through onboarding. Ripples freeze under Reduce Motion.

## The bloom

`BloomMark` is the icon's six petals drawn live, with geometry measured off the 1024pt icon. At rest, large blooms breathe in a gentle wave that travels around the flower. Small ones (under 60pt, like the one in the onboarding header) breathe as one: every petal together, a 9% swell over 4.2s. A travelling wave deep enough to see at 30pt looked like wobbling, not breathing. In the voice room, `level` opens the petals with the audio, each petal by its own flickering amount, so the brand mark and the "this is live" signal are one object.

## Liquid Glass

This lives in `Glass.swift`. On iOS 26+ it is native `glassEffect`. On iOS 17–25 it is a white-washed `.ultraThinMaterial` with a hairline border.

- The glass owns its chrome. Never paint fills or borders over it. Add a stroke only when it carries meaning (the selection ring).
- Buttons react through custom `ButtonStyle`s that own `isPressed` and read `isEnabled` themselves.
- Every button knocks `Haptics.heavy()`, wired into the components.

## Onboarding arc

The goal is conversion. It makes the user aware of real pain, then shows how practice fixes it:

welcome → name → the moment → when → readiness baseline → "does this sound like you?" deck → **the mirror** (their pattern) → the cost → **the reframe** ("a practice problem, not a talent problem") → the outcome → how it helps (mapped to their pattern) → try it (micro-demo) → your plan → hold to commit → account → paywall (personalized, hard)

### Onboarding rules

- **SleepBlock's questionnaire, component for component.** Onboarding mirrors it:
  - `QuestionLayout`: a centred title, with the control centred between the title and the button.
  - The header: a 44pt glass chevron, a 3pt gradient progress bar, and the chevron's hidden twin carrying a small bloom.
  - Capsule `OptionRow`s whose selection is painted as an overlay, so tapping doesn't lag.
  - `CoachSlider`: a rolling number and a tick on each step.
  - An underline name field.
  - `NarrativePage`: a typewriter with a haptic on each word, where earlier lines step back.
  - A fingerprint `CommitmentHoldButton`.
  - Left-edge swipe-back and a two-stage keyboard prewarm.
- **One button, one gesture.** Every step moves forward with the same primary button, including single-select answers (no auto-advance). The fingerprint hold is the only gesture.
- **Buttons.** Question steps keep their button on screen but dimmed through the 900ms settle, which only applies going forward. Reveal steps keep theirs absent until the reveal lands.
- **The mirror quotes the user.** Its pattern is computed only from the deck (`SpeakingPattern.from`). No "that's me" anywhere means *The Steady One*, never a problem the user didn't report.
- **The sun peaks on the commitment.** Stage depth is the step position divided by the commit step's position.
- **Drafts resume.** Answers and the current step persist on every change. A relaunch lands on the same step, except that commit and account resume on the plan, so the user re-reads what they're committing to. The draft is cleared only once the answers are saved to an account.
- **Analytics:** each step is page `ob_<step>` in `product_page_events`, with its index, enter/leave/action and duration. Answers, names and free text are never sent.

## Accounts

**Apple or Google, nothing else.** There's no email or password path: nothing to create, forget or reset, no confirmation emails, and no second flow to maintain. Both providers hand back a verified identity in one sheet. The two buttons are matching 58pt white pills with the official marks, labelled "Sign up with …" in the flow and "Sign in with …" on "Welcome back".

Apple uses the native sheet with a nonce, then `signInWithIdToken`. Google uses Supabase OAuth in `ASWebAuthenticationSession` with the redirect `com.sodhera.speakingcoach://auth-callback`. The profile lives in `user_metadata.coach_profile_v1`, is mirrored to the `profiles` row (name, language, goals), and is cached per user on the device. Accounts from the old app, which have a `profiles` row but no metadata, are treated as already set up.

> Accounts the old app created with an email and password can't sign in here. That's a deliberate product call.

## The gate chain

onboarding → account → (existing account?) → **paywall** → microphone primer → reminders primer → "You're all set!" → Home and Profile tabs.

- **Fade chain.** `RootView` renders a lagged `displayedScreen`. The outgoing screen fades out fully before the next one mounts, so no two screens ever overlap. The splash holds for 1.5s so the bloom is actually seen breathing.
- **Existing accounts.** "Get started" can land on an Apple or Google identity that already has an account, because those sign-ins find the existing account or create a new one. When that happens, the account's plan is kept rather than overwritten, and `ExistingAccountView` says so.
- **Primers.** Each shows a `MockPermissionDialog`, a stand-in for the real system sheet, with an arrow pointing at Allow.

- **Hard paywall.** A signed-in user without access sees the paywall, with no ✕, and nothing past it. The practice server enforces the same rule (`402` from `/api/practice/start`), so the app's gate is the experience and the server's is the lock.
- **Never gate on a guess.** The splash holds while access is `.unknown`. The paywall renders only on a resolved "not entitled".
- **Access** is RevenueCat's `pro` entitlement, keyed to the Supabase user id (the id the server checks), or a comped account (`app_metadata.admin_subscription_override`, or the server's paid-email allowlist via `/api/subscription-overrides`).
- The hard paywall keeps **Restore, Terms, Privacy and Sign out** in its footer. A walled user is never trapped.

## Paywall

Built on JournalBlock's paywall. The headline repeats the user's own outcome ("Walk into your interview calm and clear."), left-aligned under a small bloom and a tracked wordmark. Three benefits each have a bold lead and one line: *Rehearse it* (their moment), *Hear it back*, and *Retry the moment* (their pattern's fix). Under "Select a plan that fits you", the two plans sit side by side, so the yearly price is read against the monthly one. "Change plans or cancel anytime." sits under the cards.

- **The billed amount leads (3.1.2(c)).** Each card's large number is the real charge for its own period. The struck-through anchor (twelve months of the monthly plan, formatted by the product's own price formatter) and the "Billed yearly." note are smaller and below it. The sticker overhanging the yearly card reads "3 DAYS FREE" when there's a trial, otherwise "SAVE 33%", computed from the fetched prices.
- **The CTA names the tap.** It reads "Start 3-Day Free Trial →" when the selected plan has a trial, otherwise "Continue with Yearly →" or "Continue with Monthly →".
- **Nothing hides under the footer.** The cards take their natural height, then match each other, so a two-line footnote never squeezes a price. The pinned footer fades the scroll above it, and the content clears that fade. At accessibility text sizes the footer scrolls with the content instead.
- **The selection mark is solid.** A filled coral disc with a white check (`SelectionCheck`), shared by the plan cards and every answer row.
- The hard paywall keeps Restore, Terms, Privacy and Sign out in its footer.

## Status bar

`statusBarScrim()` puts a soft fade in the stage's crown colour behind the status bar, so scrolling content dissolves under the clock and icons instead of running through them. It sits on the root, on every `SceneScreen` sheet, and on the rehearsal cover.

## A glass lesson

Inside a `GlassEffectContainer` on iOS 26, overlays on child glass shapes get absorbed by the container: a coral ring painted *over* an answer row showed as a faint tint. Selection is therefore drawn inside the row's own content, which the glass leaves crisp. The glass tint itself never changes on tap.

## Debug review routes

Pass these as launch arguments (Debug builds only):

- `-review-gallery`: every component on one screen
- `-review-voice-level=0.8`: the gallery's bloom at a fixed voice level
- `-review-onboarding-step=<step>`: lands on any step (`name`, `moment`, … `account`) with every earlier step answered and the reviewed step left unanswered
- `-fresh-start`: clears the onboarding draft (UI tests use it)
- `-review-screen=<welcome|signin|existing|paywall|microphone|reminders|setup|home|profile|library|briefing|settings>`: post-sign-in screens against a fixture profile. Add `-review-plans` for placeholder plans (layout only; real prices always come from the App Store).

Review runs and UI tests never send analytics.

## Main app

Two tabs, mirroring SleepBlock:

- **Home: go rehearse.** It never scrolls. A small-caps greeting sits over the name, the bloom breathes at the centre, and one glass capsule names the next rehearsal. "Start rehearsal" sits where the thumb rests, with a "Last rehearsal …" line only when it's recent. The streak chip sits top-left: it shows zero as a hollow flame and never celebrates nothing. The full library sits top-right.
- **Profile.** A hero title with the gear, a summary band with one numeral (rehearsals in the last 7 days) and the starting readiness, the user's pattern, and recent rehearsals from `reports`. Settings is a sheet of grouped glass rows.

## The rehearsal room

Built like SleepBlock's sleep mode. **The bloom is the state**: it opens with whoever is speaking, driven by the real audio levels of the mic and the partner's track (fast attack, slow release), and greys out while paused. **The partner's line is the instrument**, shown as a caption. The user's own words are never captioned back to them, because they just said them.

- **Control grammar.** Consequential exits take a deliberate confirmation, and harmless ones are taps. "Hold to finish & get feedback" is a 1.2s coral hold. "I need a moment" and "Help me" are taps. Help pauses the scene and shows the rehearsal's sentence scaffold. The ✕ leaves at once if nothing has been said yet. Otherwise it asks, and offers feedback on what was said.
- **Pause is real.** The mic is muted, the partner's audio drops to zero, and activity pings keep the partner from filling the silence. Resuming asks the partner to repeat its last question.
- **The partner waits for a signal.** The prompt override tells it to stay silent until `[[PRACTICE_BEGIN]]`, then open with the rehearsal's exact first line. Control signals are filtered out of every transcript. (ElevenLabs' `firstMessage` override would be cleaner, but it needs that override allowed in the agent's security settings. The signal approach works with the agents as they are configured today.)
- **Natural close.** After the last allowed answer, or when time is up (the partner is asked to wrap up), the scene ends once both sides have been quiet for 3s. It never ends mid-sentence.
- **Nothing spoken is lost.** Every transcript change is written atomically to one encrypted file per account (`PracticeDrafts`, complete file protection). A dropped call with words goes straight to feedback. Backgrounding the app ends the scene, because the mic never stays live in the background. A crash or kill is offered back the next time Home appears ("Your last rehearsal was cut short").
- **Honest feedback.** The debrief quotes only lines the user actually said (the server rejects assessments that cite anything else) and never rates accent or personality.

Review routes: `-review-screen=room|assessing|debrief|recovery`.

## General improvement

Not everyone has an event coming up. The first question ("What's coming up?", subtitle "Pick the one that matters most.") ends with **Speaking better, day to day** (`SpeakingMoment.everyday`). That answer skips the date question (it records "no date" itself and clears it if the user switches back to a specific moment), and it gets its own copy all the way through. Nothing in its path promises "walking into" an event.

| Screen | Copy for the general answer |
| --- | --- |
| Readiness | "How confident do you feel speaking day to day?" |
| Outcome | "Picture yourself speaking at your best. What's different?" |
| Quiz | "What do you think?" (say your view, then one reason) |
| Plan | "Your plan is ready.", with the first rehearsal *Introduce yourself* and the final step "Speak calmly, every day" |
| Commit | "Ready to start speaking better, every day?" |
| Paywall | "Speak calmly and clearly, every day." (the user's outcomes as adverbs), with "Rehearse it: Everyday conversations, out loud…" |

Review with `-review-moment=everyday` alongside `-review-onboarding-step=…` or `-review-screen=paywall`.

## Retry this moment

The fastest path from "try one change" to having actually tried it. After a rehearsal, the debrief names the moment under *Try one change* ("The moment to retry: 'What drew you to this role?'"), and **Retry this moment · 90 sec** leads the actions.

- **The moment** is the partner's question just before the answer the feedback targeted, with up to eight lines of what came before it (`RetryCheckpoint.make`). This mirrors the server's `retryFromReport`, so the app only offers retries the server will accept.
- **The retry** restores that scene, opens on that exact question, allows two answers and runs about 90 seconds. It has a fresh voice connection and the same original setup. The server keeps the setup and doesn't re-check the plan for retries.
- **What changed** leads the retry's debrief. It covers the one criterion targeted, before → now as level dots plus the user's own quote from each attempt, and a sage "Clearer this time." when the level rose. It's always captioned: "One rehearsal compared with one retry — a direction, not proof of lasting change." A comparison is shown only when the rubric is the same.
- **One retry per rehearsal**, as the server enforces (`retry_used`). History tracks retried rehearsals (`retriedIDs`), so a used retry isn't offered again. A retry of a retry is never offered. After a retry, the secondary action is "Rehearse the whole scene again".

## Past rehearsals

Profile's rows open the full saved report (the same debrief, retry included when it's still available). Retries carry a small RETRY tag. Bare scores are gone from the rows, because a number with no scale explained nothing. Old-app reports without a practice assessment show their summary and "What to work on".

Review routes: `-review-screen=debrief|retry`.
