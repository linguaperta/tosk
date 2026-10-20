# Device testing (v0.5)

Everything below runs only on real hardware: ML Kit, text-to-speech voices, the Onyx pen SDK and the e-ink controller are faked in the automated tests (`app/test/ui/fakes/v05_fakes.dart`). Install the release APK (`docs/release.md`, "Installing on a device") on the **Android phone** and on the **Boox**, then go through the list. Note the device model and Android version with any problem.

Tip: `adb logcat -s tosk tosk-onyx flutter` shows the app's own native log lines (the Onyx bridge logs every SDK failure with the tag `tosk-onyx`).

## 1. Handwriting (phone and Boox)

Settings → Challenge → Answer input → **Write**.

- [ ] "Write" appears next to Tap and Type (it is hidden on Windows and the web).
- [ ] Below it: "Handwriting model: Italian · Not downloaded yet: about 20 MB …" with **Download**.
- [ ] Download on Wi-Fi: the row changes to "Downloading…", then "Downloaded: works offline". Rough time: ____ s.
- [ ] Switch the course to Dutch: the row says "Handwriting model: Dutch"; download it too.
- [ ] Airplane mode on, then do the exercises below: recognition still works (models are offline).
- [ ] Delete the Italian model in Settings, start an Italian lesson with airplane mode on: the pad shows the download panel; "Download" fails with "couldn't be loaded … Try again"; with the network back, "Try again" works.
- [ ] Download from the pad itself (not Settings) works the same way.

Exercises (use the **Lab** with one type at a time; a lesson works too):

- [ ] **Cloze**: the pad is at the bottom, about a quarter of the screen; "Read as: …" shows the reading about half a second after lifting the pen/finger; the gap in the sentence shows it too. Check accepts a right answer.
- [ ] Write a word sloppily so the first reading is wrong but the right one is plausible: is it still accepted (the second and third candidates count)? Write a clearly wrong word: rejected.
- [ ] Accents: write `è`, `perché`, `città` (Italian) and `één`, `ruïne` (Dutch). Does the recognizer produce the accent? With lenient accents a missing accent gives "Watch the accent".
- [ ] **Conjugation pick**: write only the ending (`-iamo`): accepted. Write the whole form (`mangiamo`): accepted. Dutch "no ending" cells: write `-`.
- [ ] **Conjugation grid**: the first empty cell is selected; write, tap **Next cell**, repeat; the last button says **Done** and checks. Tap a written cell to rewrite it. The cells show what was read.
- [ ] **Sentence builder / transform**: write a word or two, **Next word**, continue; "Read as" shows the whole sentence. Also try writing the whole sentence at once on one line.
- [ ] **Undo stroke** removes the last stroke and re-reads; **Clear** empties the pad (Check is disabled again).
- [ ] **Type instead** shows a text field with the accent bar; **Write instead** goes back.
- [ ] Writing on the pad never scrolls the exercise, even in a long grid on a small phone.
- [ ] Palm rejection (stylus devices): write with the stylus while the palm rests on the pad: no stray palm strokes.
- [ ] The keyboard never pops up while writing.
- [ ] Handwriting accuracy, rough impression per course (good / usable / poor): Italian ____, Dutch ____.
- [ ] Sarnami (local pack): the model row says "Dutch … without ṯ ḏ ṟ ã õ". Writing `toe`, `hamlog`, `kháná` gives sensible readings; answers needing `ṯ`/`ã` count as accent slips (lenient accents).

## 2. Onyx pen (Boox only)

Display: Black & white. Settings shows an **E-reader** section with "Full refresh after lessons" (on) and "Fast pen drawing" (on).

- [ ] Strokes with the stylus appear **instantly** on the pad (no lag trail), like in the Boox notes app.
- [ ] Strokes stay inside the pad: writing starting outside the pad does not draw.
- [ ] "Read as" updates after each stroke; the recognized answer is right.
- [ ] **Undo stroke** and **Clear**: the e-ink overlay is cleared (no leftover ghost strokes); the remaining strokes are still visible.
- [ ] The stylus **eraser** end (or the side button, if the pen has one) removes the strokes it touches.
- [ ] Fingers can still write on the pad (drawn by Flutter, slower) and still tap buttons.
- [ ] Tap the close button (Quit dialog) or a word for its translation while the pad is shown: the stylus does **not** draw over the dialog/popover; after closing it, the pen draws again.
- [ ] After **Check**, the pad collapses and the stylus no longer draws anywhere.
- [ ] Scroll a long grid: the pen still draws exactly where the pad is now.
- [ ] Switch apps and come back: the pen still works on the pad.
- [ ] Rotate the device (if supported): the pad still draws in the right place.
- [ ] Settings → "Fast pen drawing" off: the pad draws with Flutter (slower but works). Turn it back on.
- [ ] If anything fails, check `adb logcat -s tosk-onyx` and note the message; the pad should then still draw with Flutter.

## 3. E-ink full refresh (Boox only)

- [ ] Finish a lesson: about a third of a second after the summary appears, the whole screen flashes once (a full GC refresh) and the ghosting is gone.
- [ ] Leave the player (Done on the summary, or quit a lesson): another full refresh after the map is drawn.
- [ ] Settings → "Full refresh after lessons" off: no flash after lessons.
- [ ] Color display mode (on a color Boox): off by default; on when switched on.
- [ ] On the phone there is no E-reader section and nothing flashes.

## 4. Listening and pronunciation (phone and Boox)

The phone needs a text-to-speech engine with Italian and Dutch voices (Settings → System → Languages → Text-to-speech; install the voice data). The Boox may have no TTS engine at all; then everything below is simply absent there.

- [ ] Settings → Challenge shows **Listening exercises** (on) when the course language has a voice; it is absent for Sarnami.
- [ ] Lab → exercise types includes **Listen and pick**; a session plays the sentence by itself when it appears.
- [ ] The big play button replays it; **Slower** plays it noticeably slower.
- [ ] The voice is the right language (Italian for Italian, Dutch for Dutch), not English.
- [ ] Options are distinguishable by ear: note any pair that sounds the same (e.g. `ha`/`a`): ____.
- [ ] After Check: the translation appears; the words of the right sentence can be tapped for their meaning.
- [ ] Vocabulary lessons now and then include listening; grammar lessons never do.
- [ ] Listening exercises off in Settings: no more listening exercises; the lab hides the type.
- [ ] 🔊 **pronounce** buttons: on a word popover (tap a word in a sentence), on a flashcard (the Italian/Dutch side; when producing, after revealing), and in the word page's app bar (with the article: "il pane"). Each speaks the word.
- [ ] Phone on silent / media volume 0: no crash, just no sound.
- [ ] Without any voice for the language (e.g. remove the voice data): no listening exercises and no 🔊 buttons appear, a snack bar says "No sound? Install an Italian voice in Android text-to-speech settings." **once** (its **Settings** button opens the text-to-speech settings), and Settings → Challenge shows "No Italian voice" with **Open**. Install the voice, restart the app: listening and 🔊 are back.

### Diagnosing silent speech

- `adb logcat -s flutter TTS` while opening the app and pressing 🔊. Each language checked logs one line, e.g. `[tts] it: ready, it-it-x-itb-local (it-IT); engine voices: …` (the status, the chosen voice, and the engine's voices for that language with `network` / `not installed`). `notInstalled` means the voice data has to be downloaded; `unavailable` means the engine didn't answer (no engine, or it was still starting: it is asked again later). The plugin logs under `TTS`: `Utterance … failed: error -9` is "not installed yet", `-6`/`-7` network (a network-only voice offline), `Reconnecting to the TTS engine` when the engine connection was lost.
- `adb shell dumpsys package queries | findstr /i tts` (or `grep -i tts`) should list the TTS engine as visible to the app (the manifest's `<queries>` `TTS_SERVICE` entry).
- `adb shell settings get secure tts_default_synth` names the default engine (e.g. `com.google.android.tts`).

### All audio on the media stream (phone)

All app audio (speech, correct/wrong/complete/level-up/bonus and the select tick) plays on the media stream, like YouTube.

- [ ] With the ringer on **silent** or vibrate and the media volume up: sound effects and speech are audible.
- [ ] With the media volume at 0 (ringer up): the app is silent.
- [ ] In the app, the volume keys show the **media** volume slider, even when nothing is playing.
- [ ] Music from another app keeps playing (mixed, not paused) while the app ticks and speaks.
- [ ] `adb shell dumpsys audio` while a 🔊 word plays: under "players" (`playback activity` / `PlaybackActivityMonitor`), the app's players (its uid: `adb shell dumpsys package org.linguaperta.tosk | findstr userId`; the speech player belongs to the TTS engine's uid, e.g. Google's) show `usage=USAGE_MEDIA` with `content=CONTENT_TYPE_SPEECH` for speech and `CONTENT_TYPE_SONIFICATION` for the sounds; none shows `USAGE_ASSISTANCE_SONIFICATION`. Note the device and result: ____.

## 5. Regressions to glance at

- [ ] Tap and Type modes behave as before (no pad anywhere).
- [ ] Sounds, haptics and black & white mode unchanged.
- [ ] Starting the first lesson isn't noticeably slower (the app checks for a voice first, at most 3 s).
- [ ] The APK installs over the previous version (same signing key).
