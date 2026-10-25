# Turning on accounts and sync (Firebase), the web app and CI

Everything here is free: Firebase's Spark plan (no billing account, so nothing can ever be charged), GitHub Pages and GitHub Actions. Until you do these steps the app works exactly as before: no account UI, fully offline. The project id, Web API key and web client id are not committed to git; the app gets them at build time from a small JSON file (locally) or a secret (CI). One value is committed: the reversed **iOS OAuth client id** in `app/ios/Runner/Info.plist` (the `com.googleusercontent.apps.…` URL scheme, step 5), which also reveals the Google Cloud project number. OAuth client ids are public by design (they ship in every app build), so this is not a secret, but a fork that sets up its own project must replace it. Everything compiled into a build (API key, client ids, project id) can be read from the APK or the web app; access is controlled by the security rules and the key restrictions below.

How it works (details in `docs/data-layer.md`, "Cloud sync"):

- **Sign-in:** Google, through Firebase Authentication. The app talks to Firebase over its REST API (no native Firebase SDKs), so builds don't need `google-services.json` and Windows keeps building. Sign-in works on **Android**, the **web app** (also on iPhone/iPad as a home-screen app) and **iOS** (when an iOS client id is set). Windows has no sign-in yet, so it shows no sync UI.
- **Data:** Cloud Firestore, one private tree per user: `users/{uid}/batches/*` (answers, up to 400 per document) and `users/{uid}/settings/*`. The security rules (`firebase/firestore.rules`) let a user read and write only their own tree, signed in with Google, with fixed shapes and size caps.
- **Reports for you** (after v0.7.6): flags, feedback and crash reports a signed-in learner sends land in `users/{uid}/feedback/*` and `users/{uid}/crashes/*`. Only the sender can read or delete them (so "Delete my cloud data" covers them) and nobody can change them. You read everyone's with admin credentials (step 10), which bypass the rules, so no user id of yours has to go into the rules.
- **Web app:** GitHub Pages at `https://<owner>.github.io/<repo>/`, with the course packs mirrored (gzipped) at `.../packs/`.

Values you will collect (keep them in a note while you go):

| Value | Where it ends up |
| --- | --- |
| Project id (e.g. `tosk-4f2a1`) | `TOSK_FIREBASE_PROJECT_ID` |
| Web API key (`AIza...`) | `TOSK_FIREBASE_API_KEY` |
| Web client id (`1234-abc.apps.googleusercontent.com`) | `TOSK_GOOGLE_WEB_CLIENT_ID` |
| iOS client id (optional) | `TOSK_GOOGLE_IOS_CLIENT_ID` |
| An address for feedback emails (optional) | `TOSK_FEEDBACK_EMAIL` (empty hides "Write an email" for learners who aren't signed in) |

## 1. Create the Firebase project

1. Open <https://console.firebase.google.com> and sign in with the Google account that should own the project.
2. Click **Create a project** (or **Add project**).
3. Name it, e.g. `tosk`. Note the **project id** shown under the name (you can edit it here; it is permanent). Click **Continue**.
4. Turn **Google Analytics off** (not needed). Click **Create project**, then **Continue**.
5. The project starts on the **Spark** (free) plan. Leave it there.

## 2. Firestore

1. In the left menu: **Build → Firestore Database → Create database**.
2. Edition: **Standard**. Database ID: leave `(default)`.
3. Location: a region near you, e.g. **`eur3 (europe-west)`**. It can't be changed later.
4. Choose **Start in production mode** and click **Create**.
5. Open the **Rules** tab, replace everything with the contents of `firebase/firestore.rules` from this repo, and click **Publish**.

   (Alternatively, from the `firebase/` folder: `npx firebase-tools login`, then `npx firebase-tools deploy --only firestore:rules --project <project id>`.)

   Publish them again whenever `firebase/firestore.rules` changes (step 9).

## 3. Google sign-in

1. **Build → Authentication → Get started**.
2. Tab **Sign-in method → Add new provider → Google**. Switch **Enable** on, pick your **Project support email**, click **Save**.
3. Click the **Google** row again and expand **Web SDK configuration**: copy the **Web client ID**. That is `TOSK_GOOGLE_WEB_CLIENT_ID`.
4. Tab **Settings → Authorized domains → Add domain**: add `<owner>.github.io` (e.g. `linguaperta.github.io`). `localhost` is there already.
5. Get the **Web API key**: click the gear icon (top left) → **Project settings → General**. Copy **Web API key**. That is `TOSK_FIREBASE_API_KEY`. (It identifies the project; it is not a secret. Access is controlled by the security rules, and what the key can call by its restrictions: restricting it is a required step, below.)

### Allow the web app's address (Google Cloud console)

Google's sign-in button only works on origins you list:

1. Open <https://console.cloud.google.com/apis/credentials> and select the same project (top bar).
2. Under **OAuth 2.0 Client IDs**, click **Web client (auto created by Google Service)**.
3. Under **Authorized JavaScript origins**, click **Add URI** and add `https://<owner>.github.io`. For local testing also add `http://localhost:8080` (and run `flutter run -d chrome --web-port 8080 --dart-define-from-file=firebase-config.json`).
4. Click **Save**. It can take a few minutes to apply.

### Restrict the API key (required)

The Web API key ships in every build, so anyone can use it. Restrict it to the APIs tosk calls, so that an API enabled on the project later (for example the Gemini / Generative Language API) can never be used with it, on your quota or bill:

1. <https://console.cloud.google.com/apis/credentials>, same project. Under **API keys**, click the key whose value is your `TOSK_FIREBASE_API_KEY` (usually **Browser key (auto created by Firebase)**).
2. **API restrictions → Restrict key**, then tick exactly these three and nothing else:
   - **Identity Toolkit API** (sign-in, account deletion),
   - **Token Service API** (refreshing the sign-in),
   - **Cloud Firestore API** (sync).
3. **Application restrictions**: the app calls Firebase over plain REST, and an Android-app restriction only accepts requests that carry the `X-Android-Package` / `X-Android-Cert` headers, which the app does not send yet. So:
   - **Android (and iOS) builds:** leave this key at **None** for now (the API restriction above is what protects it).
   - **Web app:** create a second key for the web build only: **Create credentials → API key**, then **Application restrictions → Websites** with `https://<owner>.github.io/<repo>/*` (e.g. `https://linguaperta.github.io/tosk/*`) and, for local testing, `http://localhost:8080/*`; **API restrictions** as in step 2. Put a copy of `firebase-config.json` with this key as `TOSK_FIREBASE_API_KEY` in the secret `FIREBASE_WEB_CONFIG_JSON` (step 7); the Pages workflow prefers it over `FIREBASE_CONFIG_JSON`, which keeps the first key for the APK builds.
4. Click **Save**. Then open **APIs & Services → Enabled APIs & services** and check that nothing else key-callable is enabled that you don't use (in particular no *Generative Language API*).

Requests from a build with a restricted key keep working; a request to any other API with the key now fails with `API_KEY_SERVICE_BLOCKED`.

## 4. Android app (needed for sign-in on the phone)

Google's Credential Manager only hands an ID token to an app whose package name and signing certificate are registered.

1. Get the SHA-1 of the upload key (release builds are signed with it; see `docs/release.md`, "Android signing"). In PowerShell:

   ```powershell
   & "C:\Users\timo\dev\jdk-17.0.20.1+1\bin\keytool.exe" -list -v -keystore C:\Users\timo\dev\keys\tosk-upload.jks
   ```

   It asks for the store password (in `app/android/key.properties`). Copy the `SHA1:` line.
2. Also get the debug key's SHA-1 (debug builds, and CI builds without the signing secrets):

   ```powershell
   & "C:\Users\timo\dev\jdk-17.0.20.1+1\bin\keytool.exe" -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android
   ```
3. Firebase console → **Project settings → General → Your apps → Add app → Android**.
4. Package name: **`org.linguaperta.tosk`** (exactly). Nickname: `tosk Android`. Paste the upload key's **SHA-1** in *Debug signing certificate SHA-1* (the field accepts any certificate). Click **Register app**.
5. You may skip downloading `google-services.json` (the app doesn't use it; never commit it). Click **Next** through the remaining steps.
6. Back on **Project settings → Your apps → tosk Android**, click **Add fingerprint** and add the debug key's SHA-1 too.

## 5. iOS (optional)

On an iPhone or iPad the recommended path is the **web app** (step 8): open it in Safari, tap **Share → Add to Home Screen**; it runs full screen, works offline and syncs.

Native sign-in in the unsigned IPA (AltStore/SideStore) is possible but fragile: those tools usually change the bundle id when they re-sign, and Google's iOS client is bound to the bundle id. If you still want it:

1. Firebase console → **Add app → iOS**, bundle id `org.linguaperta.tosk`, **Register app**, download `GoogleService-Info.plist` (don't commit it).
2. From the plist, copy `CLIENT_ID` (that is `TOSK_GOOGLE_IOS_CLIENT_ID`) and `REVERSED_CLIENT_ID`.
3. Add the reversed client id as a URL scheme in `app/ios/Runner/Info.plist` (it is not a secret):

   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array><string>com.googleusercontent.apps.1234-abc</string></array>
     </dict>
   </array>
   ```

## 6. The build configuration file

Create `app/firebase-config.json` (git-ignored; template `app/firebase-config.example.json`):

```json
{
  "TOSK_FIREBASE_PROJECT_ID": "tosk-4f2a1",
  "TOSK_FIREBASE_API_KEY": "AIza...",
  "TOSK_GOOGLE_WEB_CLIENT_ID": "1234-abc.apps.googleusercontent.com",
  "TOSK_GOOGLE_IOS_CLIENT_ID": "",
  "TOSK_FEEDBACK_EMAIL": ""
}
```

Then build with `--dart-define-from-file=firebase-config.json` (from `app/`):

```powershell
flutter build apk --release --dart-define-from-file=firebase-config.json
flutter run -d chrome --web-port 8080 --dart-define-from-file=firebase-config.json
```

A build without the flag has no sync, as before. Check: **Settings → Account & sync** appears, **Sign in with Google** works, and the Firestore console shows `users/<uid>/batches/...` after the first sync.

## 7. GitHub secrets (CI builds with sync and signing)

Repository → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
| --- | --- |
| `FIREBASE_CONFIG_JSON` | the whole contents of `app/firebase-config.json` |
| `FIREBASE_WEB_CONFIG_JSON` (optional) | the same, with the website-restricted web key (step 3, "Restrict the API key"); used by the Pages workflow instead of `FIREBASE_CONFIG_JSON` |
| `ANDROID_KEYSTORE_BASE64` | the upload keystore as base64: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Users\timo\dev\keys\tosk-upload.jks")) \| Set-Clipboard` |
| `ANDROID_STORE_PASSWORD` | `storePassword` from `app/android/key.properties` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` from `app/android/key.properties` |
| `ANDROID_KEY_ALIAS` | `keyAlias` from `app/android/key.properties` |

Every workflow works without them: no `FIREBASE_CONFIG_JSON` means builds without sync; no `ANDROID_*` means APKs signed with the debug key (they can't update an installed release build).

## 8. GitHub Pages (the web app)

1. Repository → **Settings → Pages → Build and deployment → Source: GitHub Actions**. (Pages on a *private* repository needs a paid GitHub plan; on a public one it is free.)
2. Run the workflow **Actions → Web (GitHub Pages) → Run workflow** (it also runs on every push to `main` and daily, to pick up new course packs). Until Pages is enabled it skips with a notice.
3. The app is at `https://<owner>.github.io/<repo>/`. After a repository rename (e.g. to `tosk`) the address follows; to pin it, set the repository **variable** `PAGES_BASE_HREF` (Settings → Secrets and variables → Actions → Variables), e.g. `/tosk/`.
4. Make sure `https://<owner>.github.io` is in the Firebase authorized domains (step 3.4) and the OAuth client's JavaScript origins (step 3, "Allow the web app's address").

## 9. Updating the rules (after v0.7.6)

The rules changed: reports (`users/{uid}/feedback`, `users/{uid}/crashes`), size caps on every document, and a Google sign-in for every write. Until they are published, reports are refused (HTTP 403); the app keeps them and retries with a backoff of at most an hour, and sync itself works as before. Publish before shipping an app build from after v0.7.6, because the new app splits large answer batches into documents named `<batch>-2`, … (allowed by both the old and the new rules):

1. Firebase console → **Build → Firestore Database → Rules**.
2. Select everything in the editor and replace it with the whole of `firebase/firestore.rules` from `main`.
3. Optional: **Rules Playground** (button above the editor): a *get* of `/users/someone/feedback/abcdefgh12` as another signed-in user should be denied.
4. Click **Publish**. It applies within a minute.

Or from a terminal, in the repository's `firebase/` folder:

```powershell
npx firebase-tools login
npx firebase-tools deploy --only firestore:rules --project <project id>
```

CI checks the same rules on the emulator (`cd firebase && npm install && npm test`, needs Java).

## 10. Reading feedback (owner)

`python -m pipeline feedback pull` (docs/feedback.md, "Reading them") reads every user's reports with credentials that have access to the project. They never go into the repository or the app. Pick one:

**A. Your own Google account (nothing to store).** Install the Google Cloud CLI (<https://cloud.google.com/sdk/docs/install>), then once:

```powershell
gcloud auth login            # the Google account that owns the Firebase project
gcloud config set project <project id>
```

and each time, from `pipeline/`:

```powershell
python -m pipeline feedback pull --project <project id> --access-token (gcloud auth print-access-token)
```

**B. A service account (no gcloud).**

1. Open <https://console.cloud.google.com/iam-admin/serviceaccounts> and select the project.
2. **Create service account**: name `tosk-feedback-reader`, **Create and continue**.
3. Role: **Cloud Datastore User** (Firestore data only; the write access is for `--mark-seen` and `feedback delete`). **Continue → Done**.
4. Open the new account → **Keys → Add key → Create new key → JSON → Create**. Save the file outside the repository, e.g. `C:\Users\timo\dev\keys\tosk-feedback-reader.json`.
5. Point the pipeline at it (per shell, or as a user environment variable):

   ```powershell
   $env:TOSK_FIREBASE_SERVICE_ACCOUNT = "C:\Users\timo\dev\keys\tosk-feedback-reader.json"
   python -m pipeline feedback pull
   ```

   If the key ever leaks, delete it on the same **Keys** tab and make a new one.

Why there is no owner id in the rules: admin credentials bypass the security rules, so the rules never grant anyone else a read. There is no custom claim or hard-coded user id to maintain, and no app account, yours included, can read other people's reports.

The first `pull` may answer with a link to create an index if Firestore wants one for the collection-group query; open it, click **Create**, wait a minute and pull again.

## 11. OAuth consent screen (before outside testers sign in)

Google shows this at sign-in; outside testers need it filled in and the app published.

1. Open <https://console.cloud.google.com/auth/branding> (Google Auth Platform → **Branding**; older consoles: APIs & Services → **OAuth consent screen**) and select the project.
2. **App name** `tosk`, **User support email** your address. **App logo**: optional (a logo can require Google's brand verification; without one it is quick).
3. **App domain**: Application home page `https://linguaperta.github.io/tosk/`, **Application privacy policy link** `https://linguaperta.github.io/tosk/privacy.html` (the page is `app/web/privacy.html`, deployed with the web app), Terms of service: empty.
4. **Authorized domains**: add `linguaperta.github.io`. **Developer contact information**: your email. **Save**.
5. **Audience**: user type **External**; under **Publishing status** click **Publish app** (to *In production*). tosk asks only for the basic `openid`, `email` and `profile` scopes, which need no verification. (While it stays in *Testing*, only the accounts under **Test users**, at most 100, can sign in, and their sign-ins expire after 7 days.)
6. **Data access** (scopes): nothing to add.
7. Check the privacy page's facts against your project: it says Firestore is in the EU multi-region **eur3** (step 2's suggestion). If you picked another location, change that sentence in `app/web/privacy.html`.

## Free-tier budget

Spark gives 50k document reads, 20k writes and 20k deletes per day, and 1 GiB storage. tosk writes one document per batch of up to 400 answers; a sync runs a minute after the last answer and when the app is paused or resumed, so a 200-answer day is about 10 writes (`test/sync/sync_engine_test.dart`, "free-tier budget"). Pulls read only documents written since the last sync. A year of daily practice is a few MB. Each report is one write (several go in one request); `feedback pull` reads every report document once per pull, so mark them seen and delete old ones now and then once there are thousands.

## Turning it off again

Delete `app/firebase-config.json` and the `FIREBASE_CONFIG_JSON` secret: new builds have no sync. Users can remove their data any time with **Settings → Account & sync → Delete my cloud data**; you can delete the whole project in the Firebase console (**Project settings → General → Delete project**).
