# ElevenLabs voice model

Speaking Coach's live practice voices are configured on the ElevenLabs agents, not in the iOS binary. The app obtains a conversation token and connects with the ElevenLabs Swift SDK. The iOS app names the two agents below for custom situations. The practice server selects the same female or male agent ID from its environment when catalog practice starts.

| Partner | Agent ID | Main-branch model | Version published 2026-09-29 |
| --- | --- | --- | --- |
| Female | `agent_2901kqyrw41rfsmrfxdvsmk1pn6b` | `eleven_v4_turbo` | `agtvrsn_5501m3ppzd8sfgda3qzbs10ne1s6` |
| Male | `agent_8801kqz4fh4sfy2vrxazg3nacksn` | `eleven_v4_turbo` | `agtvrsn_3901m3ppzj3zf479nve1q7zmtv9h` |

Only `conversation_config.tts.model_id` was changed. The agent IDs, voice IDs, prompts, language presets, and app code were retained. The prior main-branch versions used `eleven_v3_conversational`:

- Female: `agtvrsn_1701kr685m61e648997nrf5zgm6s`
- Male: `agtvrsn_8701kr6tgpq0f39vssvhan26eawe`

Verification on 2026-09-29: the authenticated Sodhera workspace listed `eleven_v4_turbo` as available; a short Text to Dialogue request produced audio for each existing voice; each agent accepted the model update; and a live WebSocket conversation with each agent returned an agent reply and audio. The two test conversations were recorded on the new version IDs. These are API-level checks, not a subjective listening test or a physical-device check.

To check or change the model later, use the authenticated ElevenLabs agent API or dashboard. Keep the API key on the server or in local secrets; never add it to this repository or the iOS app. Previous agent versions remain available for rollback through ElevenLabs versioning.

## Expressive delivery check — 2026-09-30

Both live agents still report `eleven_v4_turbo`, `expressive_mode: true`, stability `0.3`, and Scribe Realtime input. Prompt and language overrides are enabled, so the Swift app's per-session `PracticePrompt` replaces the agents' base prompt.

The practice prompt previously prohibited bracketed directions, suppressing explicit audio tags despite the agents' base prompts allowing them. Build 22 allows occasional `[laughs]`, `[sighs]`, `[whispers]`, `[excited]`, and `[slow]` tags with role-appropriate delivery guidance. These controls are removed from coach captions and assessment transcripts, including incomplete tags received while streaming. User transcript text is unchanged.

Both production token endpoints returned HTTP 200 with a token. Synthetic live WebSocket checks using the revised delivery guidance returned metadata, a reply, and 39,416 audio bytes for each partner, with no client error. This confirms working configuration and audio generation; subjective expressiveness still needs a listening check. No remote agent settings were changed. The app prompt/caption changes require the new App Store binary; future agent model/settings changes remain server-side.
