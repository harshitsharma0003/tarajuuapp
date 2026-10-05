# Run Tarajuu on your iPhone from a Mac

Everything on the Firebase / backend side is already configured. You only need
Xcode, Flutter and your Apple Developer account (the one used for firstDiner).

## 0. Before you start (on the Windows PC)
The app talks to the backend on the Windows PC through ngrok:
`https://amused-chapter-unbitten.ngrok-free.dev/api`.
Keep that PC on with the backend and ngrok running (`backend\start-local.vbs`).
Check from the Mac's browser: https://amused-chapter-unbitten.ngrok-free.dev/api/health → `"ok": true`.

## 1. Mac setup (one time)
1. **Xcode** from the Mac App Store (open it once, accept the licence, let it install components).
2. **Flutter** (stable): https://docs.flutter.dev/get-started/install/macos — then run
   ```bash
   flutter doctor
   ```
   iOS toolchain must show ✓ (CocoaPods is **not** needed: the project uses Swift Package Manager).
3. Sign in to Xcode with your Apple ID: **Xcode → Settings → Accounts → +**.

## 2. Get the code
```bash
git clone https://github.com/harshitsharma0003/tarajuuapp.git
cd tarajuuapp/app
flutter pub get
```

## 3. Signing (one time)
1. `open ios/Runner.xcworkspace`
2. Select **Runner** (left) → target **Runner** → **Signing & Capabilities**.
3. Tick **Automatically manage signing**, choose your **Team** (your paid developer team).
4. Bundle Identifier must be **`app.tarajuu.tarajuu`** — Xcode registers it in your
   team automatically. **Push Notifications** and **Background Modes → Remote
   notifications** are already in the project (needed for silent phone OTP).
   If Xcode shows a red error, click **Try Again** / **Register Device**.

## 4. Prepare the iPhone (one time)
1. Connect it with a cable → tap **Trust This Computer**.
2. iPhone **Settings → Privacy & Security → Developer Mode → On** → restart.
3. Check the Mac sees it: `flutter devices`

## 5. Run
```bash
flutter run --release
```
(`--release` = fast, and the app keeps working after you unplug. Use plain
`flutter run` only for debugging; debug builds won't relaunch without the Mac.)

## 6. Test
- **Login:** `9999911111` → OTP `123456` (Firebase test number, no SMS, no web check).
- **Real number:** works; until the APNs key below is added you'll see a short web
  check before the OTP screen.
- **Location:** allow when asked → pickup fills in on Rides.
- **Search:** Amazon + Flipkart (scraped by the Windows PC). **Rides:** fares + open Uber.

## Optional: silent OTP on iPhone (no web check) — APNs key
1. developer.apple.com → Certificates, IDs & Profiles → **Keys → +** →
   tick **Apple Push Notifications service (APNs)** → Continue → Register →
   **Download** the `.p8` (only once!) and note the **Key ID**.
   (An existing APNs key — e.g. from firstDiner — can be reused.)
2. Firebase console → **Tarajuumobile** → ⚙ Project settings → **Cloud Messaging** →
   Apple app **tarajuu (ios)** → **APNs Authentication Key → Upload** →
   choose the `.p8`, enter **Key ID** and your **Team ID** (developer.apple.com → Membership).
3. Reinstall the app (`flutter run --release`). Real-number OTP is then silent.

## Troubleshooting
| Problem | Fix |
|---|---|
| "No profiles for app.tarajuu.tarajuu" | Step 3: pick your Team, click Try Again |
| "aps-environment … doesn't match" | Re-select the Team; make sure it's the paid team (free Apple IDs can't use Push) |
| "Untrusted Developer" on iPhone | Settings → General → VPN & Device Management → trust your developer certificate |
| App shows "Can't reach Tarajuu servers" | Windows PC off, or backend/ngrok not running |
| Build error about iOS version | Deployment target is iOS 15 — iPhone must be on iOS 15+ |
