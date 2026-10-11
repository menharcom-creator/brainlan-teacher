# BrainLAN Teacher (iPhone app, teachers only)

- The app has **only Teacher mode**, behind a 4-digit PIN (asked on first launch, again after 1 min in background).
- The iPhone **hosts the classroom**. Students join with the **BrainLAN Student app (Android APK)**: type the address shown
  on the teacher screen (e.g. `172.20.10.1:8080` on your Personal Hotspot) + the room code. No internet needed.
  Opening that address in a phone browser still works as a fallback.
- **Same game everywhere:** all apps are built from `src/BrainLAN.html` (9 subjects: Math, English, Filipino, Science, GMRC,
  EPP, ICT, MAPEH, ARPAN + Custom). `tools/verify.js` stops the build if any app differs from the HTML.
- When a quiz ends, each student's result is sent to **Zapier** (queued offline, retried when internet returns).
- **GitHub** builds the IPA for you (no Mac needed).

## 1. GitHub -> IPA
1. Create a new GitHub repo and upload everything in this folder (keep `.github/` and its structure).
2. Open **Actions -> Build BrainLAN Teacher IPA -> Run workflow** (also runs on every push to `main`).
3. After ~10 min, download `BrainLAN-Teacher.ipa` from **Releases -> latest** (or the run's Artifacts).
4. The IPA is **unsigned**. Install it with Sideloadly or AltStore using your Apple ID (free ID = renew every 7 days;
   paid Developer account = 1 year). TestFlight/App Store needs signing certificates (not included).

To update the game: replace `src/BrainLAN.html` and commit - a new IPA builds automatically.

## 1b. Android student APK
Run **Actions -> Build BrainLAN Student APK**, then download `BrainLAN-Student.apk` from **Releases -> student-apk-latest**.
On the phone: open the file, allow "install unknown apps" for your browser/files app, install. (Debug-signed APK; fine for classroom use.
Google Play would need a signed release build.) iPhone students can use the browser fallback.

## 2. Zapier
1. Zapier -> **Create Zap** -> Trigger: **Webhooks by Zapier -> Catch Hook** -> copy the URL.
2. In the app tap **⚙️ -> paste URL -> Save -> Send test**, then finish the Zap
   (Action example: **Google Sheets -> Create Spreadsheet Row**, or **GitHub -> Create File**).
3. Fields sent, one request per student: `quiz_title, quiz_no, subject, total_questions, rank, name, score, correct, incorrect, percent, date`.

## Notes
- Keep the app open while hosting (screen stays on automatically). Allow **Local Network** when iOS asks.
- Forgot PIN: tap ⚙️ is behind the lock, so delete and reinstall the app (this also clears saved class records).
- Not tested on a real device yet: please run one trial with 2 phones before using it in class.
