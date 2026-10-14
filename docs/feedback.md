# AI explanations, flags and sounds (v0.3)

Three features around the answer panel. The code is in `app/lib/ai/`, `app/lib/feedback/`, `app/lib/audio/` (services, pure Dart except the audio and secure-storage plugins) and `app/lib/ui/ai/`, `app/lib/ui/feedback/` (widgets). The pipeline side is `pipeline/pipeline/flags.py`.

## Explain answer with AI

After Check, the feedback panel's actions row shows **Explain answer with AI**, for right and wrong answers. The button exists only when an AI provider is configured (provider, model, URL valid, and a key where the provider needs one). Otherwise `explainerProvider` is `NullExplainer` and nothing AI-related appears anywhere. The older "Why?" slot is replaced by this button; the mistakes list uses the same explainer ("Explain with AI").

### Settings → AI explanations

| Setting | Stored | Notes |
| --- | --- | --- |
| Provider | `ai.provider` (`anthropic`, `openai`, `openai_compatible`; empty = off) | progress DB settings |
| API key | secure storage, key `tosk.ai.api_key` | `flutter_secure_storage`: Keychain, Android Keystore-backed prefs, Windows Credential Manager, libsecret. **On the web** it is the browser's storage, and the settings screen says so. Never in the progress DB, never logged (`AiConfig.toString` hides it) |
| Model | `ai.model` (empty = provider default) | Claude: `claude-haiku-5-5` (small, fast; `claude-sonnet-5-5` and `claude-opus-5-5` also work). OpenAI: `gpt-5-mini` as an editable default; **pick a current small model**, since OpenAI's lineup changes. OpenAI-compatible: required |
| Base URL | `ai.base_url` | OpenAI-compatible only, the API root ending in `/v1` (e.g. a local server). The key is optional there |
| Explanations in | `ai.explain_lang` (empty = `auto`) | `auto` follows the app's source language |

**Test connection** sends a tiny request ("Reply with OK", 8 tokens) and shows "Connected to <model>" or the error.

### Requests

- **Anthropic:** `POST {base}/v1/messages` with `x-api-key`, `anthropic-version: 2023-06-01`, `stream: true`. Text comes from `content_block_delta` / `text_delta` SSE events, and an `error` event fails the stream. In the browser the app adds `anthropic-dangerous-direct-browser-access: true`; the key is the user's own and is entered on that device.
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
  - The pools don't take audio focus, so the learner's music keeps playing. On Android that means no focus and the sonification usage; on iOS the ambient category, which mixes with other audio and respects the silent switch.
  - Every failure is swallowed. Under `flutter test` the default backend is silent, and tests inject `FakeAudioBackend`.
- **Where sounds play:**
  - The player plays select on every tap that selects an option, tile, token, grid cell or match card (typing doesn't tick), with a selection haptic.
  - It plays correct or wrong on Check.
  - At the end of a session it plays complete, or level up if the session gained a level.
  - In non-stop, it plays bonus when a bonus round starts.
- **Settings:** "Sound effects" (`ui.sound_effects`, on by default) controls sounds only. "Reduce motion" now controls animations and haptics only, so black & white mode, which forces reduced motion, keeps sounds.
