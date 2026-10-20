# Turning on accounts and sync (Firebase), the web app and CI

Everything here is free: Firebase's Spark plan (no billing account, so nothing can ever be charged), GitHub Pages and GitHub Actions. Until you do these steps the app works exactly as before: no account UI, fully offline. Nothing about your Firebase project is committed to git; the app gets it at build time from a small JSON file (locally) or a secret (CI).

How it works (details in `docs/data-layer.md`, "Cloud sync"):

- **Sign-in:** Google, through Firebase Authentication. The app talks to Firebase over its REST API (no native Firebase SDKs), so builds don't need `google-services.json` and Windows keeps building. Sign-in works on **Android**, the **web app** (also on iPhone/iPad as a home-screen app) and **iOS** (when an iOS client id is set). Windows has no sign-in yet, so it shows no sync UI.
- **Data:** Cloud Firestore, one private tree per user: `users/{uid}/batches/*` (answers, up to 400 per document) and `users/{uid}/settings/*`. The security rules (`firebase/firestore.rules`) let a user read and write only their own tree.
- **Web app:** GitHub Pages at `https://<owner>.github.io/<repo>/`, with the course packs mirrored (gzipped) at `.../packs/`.

Values you will collect (keep them in a note while you go):

| Value | Where it ends up |
| --- | --- |
| Project id (e.g. `tosk-4f2a1`) | `TOSK_FIREBASE_PROJECT_ID` |
| Web API key (`AIza...`) | `TOSK_FIREBASE_API_KEY` |
| Web client id (`1234-abc.apps.googleusercontent.com`) | `TOSK_GOOGLE_WEB_CLIENT_ID` |
| iOS client id (optional) | `TOSK_GOOGLE_IOS_CLIENT_ID` |

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

## 3. Google sign-in

1. **Build → Authentication → Get started**.
2. Tab **Sign-in method → Add new provider → Google**. Switch **Enable** on, pick your **Project support email**, click **Save**.
3. Click the **Google** row again and expand **Web SDK configuration**: copy the **Web client ID**. That is `TOSK_GOOGLE_WEB_CLIENT_ID`.
4. Tab **Settings → Authorized domains → Add domain**: add `<owner>.github.io` (e.g. `timoverlaan.github.io`). `localhost` is there already.
5. Get the **Web API key**: click the gear icon (top left) → **Project settings → General**. Copy **Web API key**. That is `TOSK_FIREBASE_API_KEY`. (It identifies the project; it is not a secret. Access is controlled by the security rules.)

### Allow the web app's address (Google Cloud console)

Google's sign-in button only works on origins you list:

1. Open <https://console.cloud.google.com/apis/credentials> and select the same project (top bar).
2. Under **OAuth 2.0 Client IDs**, click **Web client (auto created by Google Service)**.
3. Under **Authorized JavaScript origins**, click **Add URI** and add `https://<owner>.github.io`. For local testing also add `http://localhost:8080` (and run `flutter run -d chrome --web-port 8080 --dart-define-from-file=firebase-config.json`).
4. Click **Save**. It can take a few minutes to apply.

Optional hardening: on the same page, under **API keys**, open the **Browser key** and set **API restrictions → Restrict key** to *Identity Toolkit API*, *Token Service API* and *Cloud Firestore API*. Don't add an *application* restriction (HTTP referrers), because the Android app uses the same key.

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
4. Package name: **`io.github.timoverlaan.tosk`** (exactly). Nickname: `tosk Android`. Paste the upload key's **SHA-1** in *Debug signing certificate SHA-1* (the field accepts any certificate). Click **Register app**.
5. You may skip downloading `google-services.json` (the app doesn't use it; never commit it). Click **Next** through the remaining steps.
6. Back on **Project settings → Your apps → tosk Android**, click **Add fingerprint** and add the debug key's SHA-1 too.

## 5. iOS (optional)

On an iPhone or iPad the recommended path is the **web app** (step 8): open it in Safari, tap **Share → Add to Home Screen**; it runs full screen, works offline and syncs.

Native sign-in in the unsigned IPA (AltStore/SideStore) is possible but fragile: those tools usually change the bundle id when they re-sign, and Google's iOS client is bound to the bundle id. If you still want it:

1. Firebase console → **Add app → iOS**, bundle id `io.github.timoverlaan.tosk`, **Register app**, download `GoogleService-Info.plist` (don't commit it).
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
  "TOSK_GOOGLE_IOS_CLIENT_ID": ""
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

## Free-tier budget

Spark gives 50k document reads, 20k writes and 20k deletes per day, and 1 GiB storage. tosk writes one document per batch of up to 400 answers; a sync runs a minute after the last answer and when the app is paused or resumed, so a 200-answer day is about 10 writes (`test/sync/sync_engine_test.dart`, "free-tier budget"). Pulls read only documents written since the last sync. A year of daily practice is a few MB.

## Turning it off again

Delete `app/firebase-config.json` and the `FIREBASE_CONFIG_JSON` secret: new builds have no sync. Users can remove their data any time with **Settings → Account & sync → Delete my cloud data**; you can delete the whole project in the Firebase console (**Project settings → General → Delete project**).
