# AI explanations, flags, AI conversation and sounds (v0.3, v0.4)

Three features around the answer panel, and (v0.4) AI conversation practice on the same client. The code is in `app/lib/ai/`, `app/lib/feedback/`, `app/lib/audio/` (services, pure Dart except the audio and secure-storage plugins) and `app/lib/ui/ai/`, `app/lib/ui/feedback/` (widgets). The pipeline side is `pipeline/pipeline/flags.py`.

## Explain answer with AI

After Check, the feedback panel's actions row shows **Explain answer with AI**, for right and wrong answers. The button exists only when an AI provider is configured (provider, model, URL valid, and a key where the provider needs one). Otherwise `explainerProvider` is `NullExplainer` and nothing AI-related appears anywhere. The older "Why?" slot is replaced by this button; the mistakes list uses the same explainer ("Explain with AI").

### Settings → AI explanations

| Setting | Stored | Notes |
| --- | --- | --- |
| Provider | `ai.provider` (`anthropic`, `openai`, `openai_compatible`; empty = off) | progress DB settings |
| API key | secure storage, key `tosk.ai.api_key` | `flutter_secure_storage`: Keychain, Android Keystore-backed prefs, Windows Credential Manager, libsecret. On Windows the implementation is the local pure-Dart `app/packages/secure_storage_windows_dart/` (FFI, no ATL; see `docs/release.md`): a generic credential `tosk/flutter_secure_storage/<key>` per key (named after the exe), per user and machine, value as UTF-8 (max 2560 bytes). **On the web** it is the browser's storage, and the settings screen says so. Never in the progress DB, never logged (`AiConfig.toString` hides it) |
| Model | `ai.model` (empty = provider default) | Claude: `claude-haiku-5-5` (small, fast; `claude-sonnet-5-5` and `claude-opus-5-5` also work). OpenAI: `gpt-5-mini` as an editable default; **pick a current small model**, since OpenAI's lineup changes. OpenAI-compatible: required |
| Base URL | `ai.base_url` | OpenAI-compatible only, the API root ending in `/v1` (e.g. a local server). The key is optional there |
| Explanations in | `ai.explain_lang` (empty = `auto`) | `auto` follows the app's source language |

**Test connection** sends a tiny request ("Reply with OK", 8 tokens) and shows "Connected to <model>" or the error.

### Requests

- **Anthropic:** `POST {base}/v1/messages` with `x-api-key`, `anthropic-version: 2023-06-01`, `stream: true`. Text comes from `content_block_delta` / `text_delta` SSE events (thinking blocks, which current models may stream first, are skipped), and an `error` event fails the stream, as does a `message_delta` with `stop_reason: "refusal"` (an `other` error: "The model declined to answer this").
- **Messages:** `ChatPrompt` is a system prompt plus one user message, or (v0.4, conversations) `turns`: alternating user and assistant messages, sent as the `messages` array to both providers (OpenAI gets the system prompt as the first message); consecutive messages of one role are joined, and a conversation always starts with a user message. In the browser the app adds `anthropic-dangerous-direct-browser-access: true`; the key is the user's own and is entered on that device.
- **OpenAI and compatible servers:** `POST {base}/chat/completions` with `Authorization: Bearer` (omitted when the key is empty), `stream: true`, reading `choices[0].delta.content` until `[DONE]`. OpenAI gets `max_completion_tokens`; compatible servers get `max_tokens`.
- **Timeouts:** 25 s for the response headers, 30 s of silence while streaming.
- **Errors** are `AiException`s:

  | Kind | Cause | What the sheet does |
  | --- | --- | --- |
  | `network` | Offline, DNS failure, timeout | Shows the bundled grammar note instead (per spec) and offers "Try again" |
  | `auth` | 401 or 403 | Says to check the API key in Settings |
  | `model` | 404 | Says to check the model name |
  | `rateLimit` | 429 or 529 | Asks to try again |
  | `server` | 5xx | Asks to try again |
  | `other` | Anything else | Shows the provider's message |

### Prompt (`ai/prompts.dart`)

- **System:** a friendly, precise tutor; at most 150 words in the reply language; name the grammar rule (using the grammar note when it applies); forms in **bold**; short paragraphs or bullets; no headings, tables or greeting; say so if the exercise itself looks wrong.
- **User:** the course and languages, the exercise type, the instruction and prompt, the choices shown, the expected answer, other accepted answers, the learner's answer and whether it was accepted, and the skill's grammar note (markdown, clipped to 2,500 characters).

The reply is rendered with the app's own markdown renderer (`ui/common/markdown.dart`) as it streams in.

### Context and cache

- `ExplainContext` (core, `hooks.dart`) generalizes `MistakeContext`, which now extends it with `correct: false`.
  - It holds: type, prompt, choices, the given answer, the expected and accepted answers, whether the answer was correct, the grammar note, the target, source and reply languages, and the sentence id.
  - The player builds it with `buildExplainContext` (`feedback/answer_context.dart`). It uses the engine's mistake context when there is one.
- `ExplainContext.fingerprint` is `stableHash(facetId | type | prompt | expected)`: two 32-bit FNV-1a passes, the same on web and native. It doesn't depend on the session, so mistake review computes the same fingerprint from a stored `MistakeRecord`.
- `CachingExplainer` stores complete replies in the progress DB table `ai_explanations`, keyed by (fingerprint, given answer, reply language). Failed or partial replies aren't stored. A cached reply is served without a request, so it works offline. The mistakes list shows cached explanations ("Explanation") even without a key.

## AI conversation practice (v0.4)

A chat with Tosk, an AI tutor who writes only in the target language, limited to what the learner knows. The code is `app/lib/ai/tutor.dart` (prompt, reply format, conversation model and store; pure Dart) and `app/lib/ui/chat/` (providers, the Practice tab, the chat screen).

- **Availability:** the same rule as "Explain answer with AI": only when an AI provider is configured (provider, model, URL, and a key where needed; `chatAvailableProvider` = `llmExplainerProvider` is set). Without it there is no Chat tab, and a stored conversation link says AI needs a provider (Settings → AI explanations). The model is the configured one (Claude: `claude-haiku-5-5` by default; `claude-sonnet-5-5` and `claude-opus-5-5` also work).
- **What the tutor may use** (`tutorContextFor`, from the progress store's reviewed facets): the words of every started skill (most frequent first, with their glosses, at most 400) and the grammar gating allows: the base features plus those introduced by started skills and their prerequisites (tenses named with their English label and the pack's key, e.g. `present perfect (passato_prossimo)`), the tenses of started grammar skills for packs without gating data, and the titles of started grammar skills. A learner who started nothing gets the first skill's words and a "beginner" note.
- **System prompt** (`tutorSystemPrompt`): a friendly, patient conversation partner; replies in the target language only, at most 3 short sentences (under 40 words) and one simple question; only the unlocked grammar; the known words wherever possible and at most one other, very common word; an optional first line `CORRECTION: <the learner's sentence, corrected> — <a short, kind explanation in the source language>` for the most important mistake only (none when the message is fine or in the source language); a last line `TRANSLATION: <the reply in the source language>`; help briefly in the source language when asked; plain text, no markdown or emojis; and the topic. A new conversation is opened by a user turn asking the tutor to greet the learner and start on the topic (`tutorKickoff`). Each request sends the latest 24 messages (`kTutorHistory`) with `max_tokens` 1,200 (room for models that think first).
- **Topics:** free conversation, introduce yourself, food and drink, your day, family and friends, shopping, travel and places (`kTutorTopics`).
- **Reply format** (`TutorReply.parse`): lenient about case, bold markers, a marker written at the end of a line, and a translation spanning lines; while streaming, a half-written marker line is held back, so `CORREC…` never flashes in the reply.
- **Storage:** conversations are local settings `chat.conversations.{course}` (JSON; at most 12 per course and 120 messages each; `ConversationStore`). `chat.*` keys are never exported to or imported from a backup.
- **Errors** are the client's `AiException`s: offline (`network`) says AI conversation needs an internet connection and offers Try again (the learner's messages are kept; reopening a conversation whose last reply failed asks again); a rejected key or unknown model points to Settings without a retry; other errors offer Try again.
- **Tests** use a `MockClient`; no real key is ever used (`test/ai/tutor_test.dart`: the prompt, turns for both providers, refusal, offline, parsing, the store, the tutor context, glossing; `test/ui/v04_extras_test.dart`, `test/ui/v04_bw_test.dart`).

## Flags (Report)

The feedback panel always has a **Report** button (flag icon). It opens `FlagSheet`:

- **Reason chips** (one or more): The answer is wrong · Multiple answers are possible · Unclear / confusing · Translation is wrong · Other. There is also a free-text comment (up to 1,000 characters).
- **Submit** saves the flag on the device. The button then reads "Reported".
- **Confer with AI** (only when AI is configured) sends the exercise, both answers, the reasons, the comment and the full exercise snapshot.
  - The model must start with `VERDICT: exercise_wrong | ambiguous | exercise_correct`, followed by at most 120 words of reasoning. `parseVerdict` tolerates bold, case and spacing.
  - The verdict is shown with an icon and a label, never color alone, and stored with the flag. The learner can still Submit or Discard.

Flags live in the progress DB table `flags`, schema v2: id, created_at, course_id, skill_id, facet_id, exercise_type, exercise_json, given, expected, correct (the result), reason (comma-separated ids), comment, ai_verdict, ai_reasoning, app_version, pack_version, source_lang.

### Export (Settings → Feedback & flags)

The settings tile opens `/flags`: a list of flags (delete with confirmation) and **Export N flags**. Export writes `tosk-flags-YYYYMMDD.jsonl` (local date) through `file_picker`'s `saveFile` with the bytes:

| Platform | Export flow |
| --- | --- |
| Desktop | A save dialog |
| Android | The system document picker (Storage Access Framework), so Downloads, Drive and so on |
| iOS | The Files picker |
| Web | A browser download |

No share plugin is needed.

### JSON Lines format (`tosk-flag/1`)

One object per line, oldest first, UTF-8, ending with a newline:

```json
{"format":"tosk-flag/1","id":"<uuid>","created_at":"2026-10-14T09:30:00.000Z",
 "course_id":"it","skill_id":"present_are","facet_id":"it:mangiare#form:presente",
 "exercise_type":"cloze","sentence_id":"s:456",
 "exercise":{"type":"cloze","id":"…","facet_id":"…","skill_id":"…","instruction":"…",
             "before":"Noi ","after":" il pane.","expected":"mangiamo","accepted":["mangiamo"],
             "options":["mangiamo","mangiate"],"correct_index":0,"hint":"…","translation":"…",
             "sentence_id":"s:456","facet_ids":["it:mangiare#form:presente"]},
 "given":"mangiate","expected":"mangiamo","correct":false,
 "reasons":["multiple_answers","other"],"comment":"Both should work?",
 "ai_verdict":"exercise_correct","ai_reasoning":"…","app_version":"0.2.0+2",
 "pack_version":"1.2.0","source_lang":"en"}
```

(Wrapped here for reading; in the file each flag is one line.)

- **`exercise`** is a full snapshot of the core `Exercise` (`feedback/exercise_snapshot.dart`): every field of every type in snake_case, plus `facet_ids`.
  - `exerciseFromJson` rebuilds the exact exercise, and a test round-trips all nine types.
  - Item ids are in `facet_id`, `facet_ids` and `pair_facet_ids` (match pairs).
- **`reasons`** ids: `answer_wrong`, `multiple_answers`, `unclear`, `translation_wrong`, `other`.
- **`ai_verdict`:** `exercise_wrong`, `ambiguous`, `exercise_correct`, or null.
- **Versioning:** a breaking change bumps the `format` tag.

### Triage

```bash
cd pipeline
python -m pipeline flags summarize ~/Downloads/tosk-flags-20261014.jsonl [more.jsonl] \
    [--course it] [--verdict exercise_wrong|ambiguous|exercise_correct|none] [--json]
```

- It prints the counts (verdicts, reasons, app versions), then groups the flags by course (with pack versions), skill and exercise type.
- Each flag shows its reasons, comment, answers, the AI verdict and reasoning, and the exercise rendered readably, with the correct option marked `*` and the error token in `[brackets]`.
- `--json` adds the raw snapshot.
- Duplicate ids across files are read once.
- `pipeline/tests/fixtures/flags/sample.jsonl` is written by the app's own export test (`UPDATE_FLAG_FIXTURE=1 flutter test test/feedback/feedback_test.dart`), so the app and the summarizer can't drift apart.

## Sounds

- **Generator:** `app/tool/make_sounds.py` is pure Python (`wave`, `math`). It synthesizes six 16-bit mono 22.05 kHz WAVs into `app/assets/sounds/`: additive sine partials with soft raised-cosine attacks, exponential decays, DC removal and peak normalization (no clipping). The output is deterministic. WAV plays everywhere; OGG doesn't on iOS or Safari.

  | Sound | Notes | Peak | Size |
  | --- | --- | --- | --- |
  | `correct` | E5 → G#5 (a major third), bell timbre | -3 dBFS | 18 KB |
  | `wrong` | E4 → C4, soft odd partials, low-passed | -7 dBFS | 17 KB |
  | `complete` | C5 E5 G5 → C6 arpeggio that rings out | -3 dBFS | 43 KB |
  | `level_up` | G5 C6 E6 → G6, faster and brighter | -3.5 dBFS | 37 KB |
  | `bonus` | C6 D6 G6 rising shimmer (bonus round starts) | -5 dBFS | 24 KB |
  | `select` | A 35 ms low-passed click | -18 dBFS | 1.6 KB |

- **`SoundService`** (`audio/sound_service.dart`):
  - It plays through `AudioBackend`. The real `AudioplayersBackend` uses one `AudioPool` per sound, preloaded when a session starts (`warmUp`).
  - The pools play on the **media** stream (the media volume, like YouTube) and don't take audio focus, so the learner's music keeps playing: on Android `USAGE_MEDIA` with the sonification content type and no focus (`kSfxAudioContext`; before v0.6.x it was `USAGE_ASSISTANCE_SONIFICATION`, the system stream, muted on silent); on iOS the playback category with `mixWithOthers`, the same session settings as speech.
  - Every failure is swallowed. Under `flutter test` the default backend is silent, and tests inject `FakeAudioBackend`.
- **Where sounds play:**
  - The player plays select on every tap that selects an option, tile, token, grid cell or match card (typing doesn't tick), with a selection haptic.
  - It plays correct or wrong on Check.
  - At the end of a session it plays complete, or level up if the session gained a level.
  - In non-stop, it plays bonus when a bonus round starts.
- **Settings:** "Sound effects" (`ui.sound_effects`, on by default) controls sounds only. "Reduce motion" now controls animations and haptics only, so black & white mode, which forces reduced motion, keeps sounds.
