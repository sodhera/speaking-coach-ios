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

`MorningStage(depth:)` is a five-stop paper-to-apricot sky (deliberately low-chroma, so coral fills keep their edge) with a sunrise glowing up from below the bottom edge, slow sound ripples rising off it, and a fine paper grain. `depth` (0 → 1) raises and warms the sun as the user moves through onboarding. Ripples freeze under Reduce Motion.

## The bloom

`BloomMark` is the icon's six petals drawn live, with geometry measured off the 1024pt icon. At rest, large blooms breathe in a gentle wave that travels around the flower. Small ones (under 60pt, like the one in the onboarding header) breathe as one: every petal together, a 9% swell over 4.2s. A travelling wave deep enough to see at 30pt looked like wobbling, not breathing. In the voice room, `level` opens the petals with the audio, each petal by its own flickering amount, so the brand mark and the "this is live" signal are one object.

## Liquid Glass

This lives in `Glass.swift`. On iOS 26+ it is native `glassEffect`. On iOS 17–25 it is a white-washed `.ultraThinMaterial` with a hairline border.

- The glass owns its chrome. Never paint fills or borders over it. Add a stroke only when it carries meaning (the selection ring).
- Buttons react through custom `ButtonStyle`s that own `isPressed` and read `isEnabled` themselves.
- Every button knocks `Haptics.heavy()`, wired into the components.

## Onboarding arc

The goal is conversion. It makes the user aware of real pain, then shows how practice fixes it:

welcome → **practice language** → name → **category** → the situation → when → readiness baseline → "does this sound like you?" deck → **support** (care and a useful next step) → the cost → **the reframe** ("a practice problem, not a talent problem") → the outcome → **the promise** → **the demo** (a tap-through example) → your plan → hold to commit → account → paywall (personalized, hard)

### Categories

The four categories are how the app is marketed, and they're the first real question: **Work** (interviews, meetings, raises, hard conversations), **Presentations** (talks, pitches, speeches), **IELTS Speaking**, and **Everyday conversations** (meeting people, speaking with ease). The boundary between the two work categories: Presentations is speaking to a room, Work is one-to-one or a meeting. A category with one situation (Presentations, IELTS) skips the situation question. IELTS appears only when the practice language is English.

**IELTS is a built-in scene.** The server's catalog has no IELTS rehearsals yet, so `CustomSituation.ieltsSpeaking` (a Part 1 examiner) runs on the custom-situation endpoints. Its debrief is the general one, not a band score. Its briefing looks like any rehearsal's, and `RootView` routes it down the custom path. In the first plan, a second run of the scene counts as the retry. When IELTS content lands in the server catalog, point `SpeakingMoment.ielts` at it and delete the built-in scene.

### Language

The practice language is asked first, because the partner, the scenes and IELTS all depend on it. The device's language leads a short list and is already selected, and each option is written in its own language ("Deutsch", "Español"). The app's own language is never asked: iOS already shows the app in the phone's language, and the user can change it per app in Settings. No location is asked for either; nothing uses it.

### The promise and the demo

- **The promise** is a typewriter page in the user's own words: "Sulav, here's our promise. / Practise it with us first, / and you'll walk into your interview calm and clear." It is strong on purpose, but it never names a result we can't measure (no band scores, no "you'll get the job").
- **The demo** says it is an example and that the user does not need to speak yet. One clear tap shows a first answer, the card explains one useful change, and a second tap shows a clearer answer. The sample never presents its words as the user's own.

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
- **Clear actions.** Every step moves forward with the same primary button, including single-select answers (no auto-advance). The demo has two labeled taps to show its example. The fingerprint hold is reserved for commitment.
- **Buttons.** Question steps keep their button on screen but dimmed through the 900ms settle, which only applies going forward. Reveal steps keep theirs absent until the reveal lands.
- **Support without a label.** The response is tailored privately from the deck (`SpeakingPattern.from`) and gives care plus a concrete way practice can help. It does not name a type of person or repeat the answers back to them.
- **No pain, no cost question.** If every statement in the deck gets "Not me", the cost step is skipped and "Nothing yet" is recorded. If they go back and report pain, it's cleared so they answer it themselves.
- **Outcomes fit the situation.** IELTS and everyday conversations offer "I keep going, without freezing". Work and presentations offer "I get what I asked for".
- **The sun peaks on the commitment.** Stage depth is the step position divided by the commit step's position.
- **Drafts resume.** Answers and the current step persist on every change. A relaunch lands on the same step, except that commit and account resume on the plan, so the user re-reads what they're committing to. The draft is cleared only once the answers are saved to an account.
- **Analytics:** each step is page `ob_<step>` in `product_page_events`, with its index, enter/leave/action and duration. Answers, names and free text are never sent.

## Accounts

**Apple or Google, nothing else.** There's no email or password path: nothing to create, forget or reset, no confirmation emails, and no second flow to maintain. Both providers hand back a verified identity in one sheet. The two buttons are matching 58pt white pills with the official marks, labelled "Sign up with …" in the flow and "Sign in with …" on "Welcome back".

Apple uses the native sheet with a nonce, then `signInWithIdToken`. Google uses Supabase OAuth in `ASWebAuthenticationSession` with the existing app redirect `dating-coach://auth/callback`. The profile lives in `user_metadata.coach_profile_v1`, is mirrored to the `profiles` row (name, language, goals), and is cached per user on the device. Accounts from the old app, which have a `profiles` row but no metadata, are treated as already set up.

> Accounts the old app created with an email and password can't sign in here. That's a deliberate product call.

## The gate chain

onboarding → account → (existing account?) → **paywall** → "How did you hear about us?" → microphone primer → reminders primer → "You're all set!" (the plan) → Home and Profile tabs.

- **Attribution after the paywall.** "How did you hear about us?" is asked once per account, after they've paid, and saved to the profile (`heardFrom`). Old-app accounts are never asked.

- **Fade chain.** `RootView` renders a lagged `displayedScreen`. The outgoing screen fades out fully before the next one mounts, so no two screens ever overlap. The splash holds for 1.5s so the bloom is actually seen breathing.
- **Existing accounts.** "Get started" can land on an Apple or Google identity that already has an account, because those sign-ins find the existing account or create a new one. When that happens, the account's plan is kept rather than overwritten, and `ExistingAccountView` says so.
- **Primers.** Each shows a `MockPermissionDialog`, a stand-in for the real system sheet, with an arrow pointing at Allow.

- **Hard paywall.** A signed-in user without access sees the paywall, with no ✕, and nothing past it. The practice server enforces the same rule (`402` from `/api/practice/start`), so the app's gate is the experience and the server's is the lock.
- **Never gate on a guess.** The splash holds while access is `.unknown`. The paywall renders only on a resolved "not entitled".
- **Access** is RevenueCat's `pro` entitlement, keyed to the Supabase user id (the id the server checks), or a comped account (`app_metadata.admin_subscription_override`, or the server's paid-email allowlist via `/api/subscription-overrides`).
- The hard paywall keeps **Restore, Terms, Privacy and Sign out** in its footer. A walled user is never trapped.

## Paywall

Built on JournalBlock's paywall. The headline repeats the user's own outcome ("Walk into your interview calm and clear."), left-aligned under a small bloom and a tracked wordmark. Three benefits each have a bold lead and one line: *Practise it* (their moment), *Hear it back*, and *Retry the moment* (their pattern's fix). Under "Select a plan that fits you", the two plans sit side by side, so the yearly price is read against the monthly one. "Change plans or cancel anytime." sits under the cards.

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
- `-review-onboarding-step=<step>`: lands on any step (`language`, `name`, `category`, … `account`) with every earlier step answered and the reviewed step left unanswered
- `-fresh-start`: clears the onboarding draft (UI tests use it)
- `-review-screen=<welcome|signin|existing|paywall|attribution|microphone|reminders|setup|home|profile|library|briefing|settings|checkin>`: post-sign-in screens against a fixture profile. Add `-review-plans` for placeholder plans (layout only; real prices always come from the App Store).

Review runs and UI tests never send analytics.

## The first plan

The plan the user holds their thumb on before paying (rehearse it out loud → retry the moment that trips you up → walk in *their outcome*) is kept after the paywall.

- **The hand-off is the plan.** "You're all set, {name}." shows the same card with its progress. "Start my first session" goes to Home with the first briefing already open on top, so Back lands on Home. "I'll look around first" goes to Home, where the plan waits. Old-app accounts never saw a plan and get the settings hand-off instead.
- **Home is the plan until it's done.** The plan's current step fills Home's Up next card: three marks count the step, and tapping the card takes that step.
- **Progress is read, never guessed.** Step 1 is a rehearsal of the plan's own practice in `reports`. Step 2 is a retry of it. Step 3 is the check-in. A second phone shows the same progress. The card waits for history to load, so a step is never drawn undone and then ticked.
- **Step 2 reopens the debrief**, not a bare retry, because "Try one change" and the quoted moment are what make the retry mean anything. A report with no moment to go back to gets the whole scene again.
- **Step 3 is the readiness question again.** The app can't walk in with the user, so the honest close is their own number read against their onboarding baseline (`planReadiness`, `planCompletedAt` on the profile). The result states only what the two numbers say.

Review routes: `-review-screen=home|setup|checkin` with `-review-plan-step=retry|finish|done`.

## Main app

**Custom situation** mirrors the briefing: a centred cover (the ✎ from its tile), title and one short line, then both questions in one card and the two choices. **A primary button that can't be tapped yet is neutral**, a grey glass pill with muted words that turns coral once it can go. A faded coral read as broken. This lives in `PrimaryButton`, so every screen gets it.

**Pushed pages hide the tab bar.** The briefing, Custom situation, presentations, a deck, a presentation review and the preparation plan end in their own action at the bottom, so the tab bar steps aside rather than stacking under it.

**Ground.** Everything after onboarding stands on warm paper lit faintly from above (`AppGround.warmLight`, #FAF6F2 at the top to #F3ECE5 at the bottom), with no grain or ripples. `MorningStage` draws it when the environment's `stageStyle` is `.flat`, which is set on the tab shell and the session cover. The sunrise stays for onboarding, the paywall and the setup gates, where it tells the story of committing. Behind real content it went muddy tan at the bottom, and its grain and ripples added noise. A flat grey (#EFEBE7) was tried in between: it was clean but read cold and dull next to the coral.

**Wording.** Everything the user reads says *session* for one go at a scene and *practise* for the verb ("Start my first session", "Practise with my slides", "Your next session is ready"). "Rehearsal" read oddly in headings and counts. Code names (`RehearsalView`, `rehearsals.json`), analytics events and the content file's `format: "rehearsal"` keep the old word, because none of them reach the screen.

Two tabs: Practice and Profile. Progress and Profile were separate tabs, each too thin to earn one, and both were about the user rather than what to do next, so they merged.

- **Practice: a shelf of rehearsals.** Laid out like a music library (Spotify's home was the reference), because that is what it is. Earlier versions tried a near-wordless hero, a full catalog of pills and lists, and a three-card stack with a bottom button. Each one either hid the choices or crowded them. Top to bottom:
  1. **Situation and streak.** The situation is a dropdown at the top left ("Work ⌄"), a popover rather than a system menu, because iOS 26 morphs a menu back into its label and clipped the new name. It opens on the user's last pick (`practice.selectedCategory`), or their own kind of moment on first run. The menu also holds the 30-second prompt and the preparation plan. The streak chip sits top right: zero wears a hollow flame and never celebrates nothing.
  2. **The situation's rehearsals** as compact two-column text tiles. The title gets the width, and a mark on the right appears only where it means something: a coral tick once a rehearsal is done, or the glyph of a tile that isn't a rehearsal. A repeated situation icon said nothing and cut titles short. "Practise with my slides" joins Presentations, and "Custom situation" always closes the grid.
  3. **Up next.** One large card, the whole card a button with a chevron: a coral cover panel, a label only when it adds something ("Your plan · step 1 of 3" with three step marks, "Your event · 2 of 5 done", or a situation other than the chosen one), the title, and partner · length. Order: the first plan, then a preparation plan in progress, then the first rehearsal not yet done in the chosen situation, then anywhere.
  4. **Recently practised.** A horizontal row of the last ten sessions and retries, as compact glass cards in the style of the tiles above: the title, the day under it, and a small situation symbol (or the retry arrow) in the corner. Cover-art squares were tried and dropped. Coral ones drowned Up next, the one coral block on the screen, and glass ones with a lone big icon looked empty. Done ticks on the tiles are sage so they don't add red. Each reopens its feedback.

  There is no bottom action button. Weekly days live on Profile.
- **Profile: you, and what you've done.** The user's name is the title, with the gear beside it. Under it:
  1. **This week.** A disc per day under "This week · N sessions": ticked coral discs for days with a session, today ringed, the rest faint. It replaced a five-week calendar, which was more history than a glance needs. The streak's number stays on Practice, where it asks for today. With nothing practised yet, one line says what the card is for.
  2. **History.** Every session, newest first. Each row has a situation icon, the title and a relative date, and reopens that session's feedback. Retries sit under the session they went back to, and eight rows show before "Show more".

  Removed on purpose: a Skills card and a "How ready you feel" track, which were accurate but hard to read at a glance; an identity card (the email lives in Settings); and "A good next step", which repeated Up next.
- **Settings** is a sheet from the gear: a hero title with a 44pt ✕, then grouped glass rows under quiet sentence-case labels (Account, Subscription, Practice, Help and legal). Practice holds the practice routine (its row's value says what it's set to: "8:00 AM · Unlock", or "Off"), language and the daily reminder. Sign out and Delete account close the list as rows of their own, not loose buttons. The Practice routine page uses section titles.

Review route: `-review-screen=progress` brings four weeks of fixture practice.

## After Practice: briefing to feedback

The screens after a tap on Practice use its language, so the flow reads as one app: sentence-case labels instead of tracked uppercase kickers, section titles above plain glass cards (as "Up next" sits over its card), and `Corner.lg` cards.

- **Briefing** is laid out like an album page, centred: the session cover (112pt) (the coral gradient with the situation's symbol, shared with the Up next card as `SessionCover`) sits above the centred title and goal. A left-aligned hero left the right half empty over a full-width card. The setup follows as a short list (Partner, Length, Pressure, and the user's situation once written), and its last row is "Adjust session". "Start speaking" is the one button. The Adjust sheet holds the situation as one card with its question inside, then Pressure, Pace and Partner's voice. "Done" is ink.
- **Choices** (`Segmented`, used on the Adjust sheet, Custom situation, the presentation deck and the routine) are Apple's own segmented control, so on iOS 26 the choice is the system's Liquid Glass thumb: you can hold it and drag it across, and it stretches and ticks as it goes. We restyle only its words: DM Sans, with the chosen word in coral (the control's one accent) and the rest dim. The thumb stays the system's own white. Custom look-alikes were tried and dropped: solid coral pills were a wall of red, a coral-tinted glass capsule read as pink, and none of them could be dragged. Free-text questions sit together in one card, each asked small and grey inside it (the audience card, Custom situation, the Adjust sheet).
- **Live session.** Status lines ("Your partner is speaking") are small sentence-case labels.
- **Feedback.** A quiet label names the session. The verdict is the headline, then sections: How you did, Keep this, Try one change, Take it into real life (on a retry, What changed comes right after the verdict). There is no "Done": the ✕ closes, so the bottom holds one action at most (Retry this moment, or Practise again). Each section is a title over one card, with no icon chip in a card header.

## The rehearsal room

Built like SleepBlock's sleep mode. **The bloom is the state**: it opens with whoever is speaking, driven by the real audio levels of the mic and the partner's track (fast attack, slow release), and greys out while paused. **The partner's line is the instrument**, shown as a caption. The user's own words are never captioned back to them, because they just said them.

- **Control grammar.** Consequential exits take a deliberate confirmation, and harmless ones are taps. "Hold to finish & get feedback" is a 1.2s coral hold. "I need a moment" and "Help me" are taps. Help pauses the scene and shows the rehearsal's sentence scaffold. The ✕ leaves at once if nothing has been said yet. Otherwise it asks, and offers feedback on what was said.
- **Pause is real.** The mic is muted, the partner's audio drops to zero, and activity pings keep the partner from filling the silence. Resuming asks the partner to repeat its last question.
- **The partner waits for a signal.** The prompt override tells it to stay silent until `[[PRACTICE_BEGIN]]`, then open with the rehearsal's exact first line. Control signals are filtered out of every transcript. (ElevenLabs' `firstMessage` override would be cleaner, but it needs that override allowed in the agent's security settings. The signal approach works with the agents as they are configured today.)
- **Natural close.** After the last allowed answer, or when time is up (the partner is asked to wrap up), the scene ends once both sides have been quiet for 3s. It never ends mid-sentence.
- **Nothing spoken is lost.** Every transcript change is written atomically to one encrypted file per account (`PracticeDrafts`, complete file protection). A dropped call with words goes straight to feedback. Backgrounding the app ends the scene, because the mic never stays live in the background. A crash or kill is offered back the next time Home appears ("Your last session was cut short").
- **Honest feedback.** The debrief quotes only lines the user actually said (the server rejects assessments that cite anything else) and never rates accent or personality.

Review routes: `-review-screen=room|assessing|debrief|recovery`.

## General improvement

Not everyone has an event coming up. The first question ("What's coming up?", subtitle "Pick the one that matters most.") ends with **Speaking better, day to day** (`SpeakingMoment.everyday`). That answer skips the date question (it records "no date" itself and clears it if the user switches back to a specific moment), and it gets its own copy all the way through. Nothing in its path promises "walking into" an event.

| Screen | Copy for the general answer |
| --- | --- |
| Readiness | "How confident do you feel speaking day to day?" |
| Outcome | "Picture yourself speaking at your best. What's different?" |
| Demo | A friend asks "What do you think?" (say your view, then one reason) |
| Promise | "and you'll speak calmly and clearly, every day." |
| Plan | "Your plan is ready.", with the first rehearsal *Introduce yourself* and the final step "Speak calmly, every day" |
| Commit | "Ready to start speaking better, every day?" |
| Paywall | "Speak calmly and clearly, every day." (the user's outcomes as adverbs), with "Practise it: Everyday conversations, out loud…" |

Review with `-review-moment=everyday` alongside `-review-onboarding-step=…` or `-review-screen=paywall`.

## The debrief

Two views of the same rehearsal, switched by a **Feedback | Conversation** capsule pinned beside the ✕. The transcript used to wait behind a link below the fold, so people didn't know it existed.

- **Feedback reads as one argument.** The summary comes first. Under it, **How you did** lists every criterion with one plain word on a soft pill: Clearly (sage), Partly (coral), Not yet (grey). The dashed and half-filled marks it replaced needed a legend, and the rows' *Keep this* / *Your focus* tags repeated the sections below, so both went. Summaries often say "the three parts we're checking", so those parts now appear on screen. Tapping a row shows its note and quote. *Try one change* gets the faint coral tint and shows the moment to retry as the partner's own bubble.
- **Quotes look like speech.** The user's words sit in right-hand coral bubbles and the partner's in left-hand paper ones, in the cards and in the conversation. A quote cut from a longer line gets an ellipsis at each cut end.
- **The conversation is marked, not annotated.** Only the lines the cards quote carry a tag (*Keep this*, *Your focus*, *The moment to retry*). Inside a marked line, the quoted words stay in ink and the rest dims. A background tint read as mud on the coral bubble.
- **Quotes link to the conversation.** Tapping a quote opens the Conversation view, scrolls to that line and outlines it for a moment. Both views stay mounted, so each keeps its scroll position.

## Retry this moment

The fastest path from "try one change" to having actually tried it. After a rehearsal, the debrief names the moment under *Try one change* ("The moment to retry: 'What drew you to this role?'"), and **Retry this moment · 90 sec** leads the actions.

- **The moment** is the partner's question just before the answer the feedback targeted, with up to eight lines of what came before it (`RetryCheckpoint.make`). This mirrors the server's `retryFromReport`, so the app only offers retries the server will accept.
- **The retry** restores that scene, opens on that exact question, allows two answers and runs about 90 seconds. It has a fresh voice connection and the same original setup. The server keeps the setup and doesn't re-check the plan for retries.
- **What changed** leads the retry's debrief. It covers the one criterion targeted, before → now as level dots plus the user's own quote from each attempt, and a sage "Clearer this time." when the level rose. It's always captioned: "One session compared with one retry — a direction, not proof of lasting change." A comparison is shown only when the rubric is the same.
- **One retry per rehearsal**, as the server enforces (`retry_used`). History tracks retried rehearsals (`retriedIDs`), so a used retry isn't offered again. A retry of a retry is never offered. After a retry, the secondary action is "Practise the whole scene again".

## Past rehearsals

History rows on Profile open the full saved report (the same debrief, retry included when it's still available). Retries sit under the rehearsal they retried. Bare scores are gone from the rows, because a number with no scale explained nothing. The rubric's marks replace them, since each one has a word behind it. Old-app reports without a practice assessment show their summary and "What to work on".

Review routes: `-review-screen=debrief|retry`.

## Your own material

Library opens with a **Your own** group: Custom situation, Preparation plan, Practice routine, Presentations. The catalog follows.

### Presentations

Your slides, rehearsed out loud, then the audience's questions.

- **Decks stay on the phone** (Application Support, complete file protection). Only the transcript, slide text and a spoken answer leave it, for coaching. PDF is the path. A `.pptx` goes through the server's converter, and when that can't run, the message says to export a PDF instead.
- **Rehearsing** is full screen. The slide is the instrument: you swipe it like a clicker, and each change is logged with its time. A small bloom by the timer shows the mic is hearing you. Finishing is a hold. The recording is AAC mono at 32 kbps and capped at 40 minutes, which keeps it inside the transcription limit. A talk is saved before the questions are fetched, so a network failure never loses it.
- **Afterwards, questions come first.** Q&A is the part people dread and never practise. You answer each question out loud, and each answer gets one specific note. Then comes the replay, with slides following the recording, then the transcript. Pace is shown as words a minute.

Review routes: `presentations`, `deck`, `presentationreview`, `rehearsalready`.

### Preparation plan

Five rehearsals in the order that builds, from four programs (interview, work, boundaries, everyday). The program suggested first is the one that fits the onboarding answer. An optional event name and date come with one 9 am reminder the day before, and the reminder never names the event. Progress is read from history (first rehearsals since the plan began, not retries) and is never ticked by hand. A reflection is asked for once the day arrives. The plan is stored in `user_metadata.preparation_plan_v1`, so it follows the account and needs no table. While it's in progress, Home's Up next card is the plan's next rehearsal, and the plan's row shows "2 of 5 done".

Review routes: `plan`, `planprogress`.

### Practice routine

- **Daily prompt:** a thirty-second speaking prompt on chosen days, as a notification that opens it. Prompts rotate daily and come in three kinds: say a line, answer a question, describe a scene. The check is kind. It asks only that you really spoke, and never judges accent or grammar. Non-English users get the open questions.
- **Speak to unlock:** chosen apps are shielded during a window until you speak (15 minutes by default). This is SleepBlock's Screen Time architecture with three extensions: a monitor puts the shield up and down, the shield itself carries the bloom on cream, and "Open Speaking Coach" on the shield posts a notification that opens the prompt. `Shared/RoutineShared.swift` is the single rule all four processes read.
- **Nobody can be locked out:**
  - Turning it off clears the shield.
  - Signing out turns it off.
  - The app reconciles the shield every time it comes forward.
  - The prompt opens for any signed-in user, even one whose plan has lapsed.
  - **Skip** always exists. It's a slow door (ask, wait 10 s, then 5 minutes open). The wait is the mechanism.
- **Signing:** the simulator build leaves Family Controls out, as SleepBlock does. Device builds carry it. Shipping it needs Apple's Family Controls *distribution* entitlement for `com.sodhera.speakingcoach` and its three extensions (`.block-monitor`, `.shield-config`, `.shield-action`).

Review routes: `routine`, `prompt`.

### Send feedback

Settings → Help → Send feedback. It takes a few words and one optional screenshot, shrunk to 1600 pt. It lands where the old app's feedback did: a `feedback` row in `reports`, plus the `feedback_screenshots` bucket. App version and device model are included, and nothing else.
