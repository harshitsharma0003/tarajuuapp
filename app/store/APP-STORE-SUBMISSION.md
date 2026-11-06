# Tarajuu: App Store Connect submission sheet

Everything to paste into App Store Connect, field by field. The screenshots are in
`app/store/ios-screenshots/6.9-inch_1320x2868/` (upload to the 6.9" iPhone slot; Apple scales them for
smaller iPhones). If App Store Connect asks for the 6.5" size instead, use `6.5-inch_1284x2778/`. The app is iPhone-only and portrait-only, so no iPad screenshots are needed.

---

## 0. Before you press Submit

1. **Turn on GitHub Pages** (one time). Without it, the Privacy Policy and Support URLs below give a 404.
   GitHub → harshitsharma0003/tarajuuapp → **Settings → Pages** → Source: *Deploy from a branch* →
   Branch **main**, folder **/docs** → Save. After about a minute, check that
   https://harshitsharma0003.github.io/tarajuuapp/privacy.html opens.
2. **Upload a new build** that contains this commit (it adds Delete account, Skip for now, and the iPhone-only setting).
   On the Mac: `cd app && flutter build ipa --release`, then upload with Transporter or Xcode → Organizer.
   Or, if the App Store secrets are set on GitHub, the CI `ios` job uploads it to TestFlight automatically.
3. **Keep the backend online for the whole review** (1–3 days). The app talks to the server on the PC
   through ngrok. If the PC is off or asleep, the reviewer sees "servers are offline" and rejects the app
   (Guideline 2.1). Run `backend/start-local.vbs` and keep the PC awake and online, or point the app
   at an always-on server before building.
4. In Firebase (tarajuumobile) → Authentication → Phone → **test numbers**, confirm that
   `+91 99999 11111` → `123456` is still listed.

---

## 1. App Information

| Field | Value |
|---|---|
| Name | `Tarajuu: Price & Ride Compare` |
| Subtitle | `Compare prices & ride fares` |
| Bundle ID | `app.tarajuu.tarajuu` |
| SKU | `tarajuu-ios-001` |
| Primary language | English (India) (or English (U.S.)) |
| Primary category | **Shopping** |
| Secondary category | **Travel** |
| Content rights | **Yes, it contains, shows, or accesses third-party content**, and tick that you have the necessary rights. The app shows public product listings (titles, prices, images) from stores and links back to them. |
| Age rating | Answer **None / No** to every question → **4+** (no unrestricted web browsing: store links open in Safari or the store's app) |

## 2. Pricing and Availability

| Field | Value |
|---|---|
| Price | Free |
| Availability | **India only** (the app compares Indian stores and rides, and sign-in uses +91 numbers) |

## 3. Version 1.0: Store listing

**Promotional text** (170 max)
```
Search once, see both prices. Tarajuu shows the same product's price on Amazon and Flipkart side by side, and compares cab, auto and bike fares for your route.
```

**Description**
```
Tarajuu (तराजू, "weighing scale") helps you pay less, every time.

SHOP SMARTER
• Search any product: phones, TVs, laptops, audio, fans and more.
• See the same item's price on Amazon and Flipkart on one card, matched by model, storage, size and photo, so you compare like with like.
• Product page with both prices, MRP and discount, and one tap to buy on the store you choose.
• Save products with ♡ and get back to your recent searches.

RIDE SMARTER
• Enter pickup and drop. Your current location fills pickup automatically.
• Compare estimated fares for cab, premium, auto and bike side by side.
• The cheapest option is highlighted with how much you save. Tap Book to continue in the provider's app.

PRIVATE BY DESIGN
• No ads, no tracking, and your data is never sold.
• Use it without an account, or sign in with your mobile number to keep your searches and favourites.
• Delete your account any time from the menu.

Tarajuu is an independent price comparison app. It is not affiliated with Amazon, Flipkart, Uber, Rapido or Ola. Prices and fares are fetched from public sources and may change. The final price is always shown by the store or ride provider.
```

**Keywords** (100 max; no brand names, since Apple rejects other companies' trademarks in keywords)
```
price,compare,comparison,deals,shopping,cab,taxi,fare,auto,bike,ride,cheapest,savings,offers,india
```

| Field | Value |
|---|---|
| Support URL | `https://harshitsharma0003.github.io/tarajuuapp/support.html` |
| Marketing URL | `https://harshitsharma0003.github.io/tarajuuapp/` (optional) |
| Privacy Policy URL | `https://harshitsharma0003.github.io/tarajuuapp/privacy.html` |
| Version | `1.0.0` |
| Copyright | `2026 <your legal name or company, as on your Apple Developer account>` |

**Screenshots**: iPhone 6.9" Display, upload in this order:
1. `1-splash.png` 2. `2-home.png` 3. `3-shop-results.png` 4. `4-price-compare.png` 5. `5-ride-compare.png` 6. `6-menu-account.png`

**Build**: select the build uploaded in step 0.2.

## 4. App Review Information

| Field | Value |
|---|---|
| Sign-in required | ✅ Yes (tick it, and fill in the details below) |
| User name | `9999911111` |
| Password | `123456` |
| Contact | your name, phone and email |

**Notes** (paste as-is):
```
Thank you for reviewing Tarajuu.

SIGN-IN (demo account)
1. On the sign-in screen enter mobile number 9999911111 (the +91 country code is already filled in) and tap "Send OTP".
2. Enter the OTP 123456. This is a test number configured in Firebase Authentication, so no SMS is sent and it works from any country.
Sign-in is optional: "Skip for now" on the sign-in screen opens the app without an account.

WHAT TO TRY
• Shop: tap a category (e.g. Audio) or search a product such as "boat headphones". Cards with both AMZ and FLK tags show the same product's price on both stores. Tap a card to see both prices and the Buy buttons, which open the store's page.
• Rides: Home → Rides, allow location (or type a pickup), choose a destination from the suggestions, tap "Check Prices". Fares are estimates. "Book" opens the provider's own app or website. No booking or payment happens inside Tarajuu.
• Account deletion: Menu (☰, top-left on Home) → "Delete account" → Delete. This permanently removes the account and its data from our servers.

LOCATION
Location is used only on the Rides screen to fill the pickup point. The app works fully if permission is denied.

NOTES
• A new search can take 10–30 seconds the first time because prices are fetched live. Results then appear on the same screen.
• Tarajuu has no in-app purchases, ads, or payments.
• Tarajuu is an independent comparison service and is not affiliated with the stores or ride providers it lists.
```

## 5. App Privacy ("nutrition label")

**Do you or your third-party partners collect data from this app?** → **Yes**

| Data type | Collected | Used for | Linked to the user | Used to track |
|---|---|---|---|---|
| Contact Info → **Phone Number** | Yes | App Functionality | Yes | No |
| Contact Info → **Name** | Yes (optional) | App Functionality | Yes | No |
| Contact Info → **Email Address** | Yes (optional) | App Functionality | Yes | No |
| Location → **Precise Location** | Yes | App Functionality | **No** | No |
| Search History → **Search History** | Yes | App Functionality | Yes | No |
| Identifiers → **User ID** | Yes | App Functionality | Yes | No |
| Usage Data → **Product Interaction** | Yes (store/ride taps for "₹ saved") | App Functionality | Yes | No |

Everything else: **Not collected**. Tracking: **No** (the app doesn't use App Tracking Transparency, ad SDKs or data brokers).

## 6. Export compliance and other questions

| Question | Answer |
|---|---|
| Uses encryption? | Already answered in the build (`ITSAppUsesNonExemptEncryption = NO`): only standard HTTPS, so it's exempt. Nothing to upload. |
| Content rights | See §1 |
| Advertising identifier (IDFA) | **No** |
| Government / financial / medical regulated? | No |
| Made for Kids? | No |

---

## What was changed in the app for review (this commit)

| Apple guideline | Issue | Fix |
|---|---|---|
| 5.1.1(v) Account deletion | No way to delete an account | Menu → **Delete account** (with confirmation) → `DELETE /api/me` removes the user and all their data (cascade), then deletes the Firebase login |
| 5.1.1(v) Forced sign-in | Login screen blocked browsing | **Skip for now** on the login screen; shopping and ride comparison work without an account |
| 2.1 / 2.3.1 Incomplete features | "Continue with Google" only showed "coming soon" (it would also need Sign in with Apple under 4.8) | Google button hidden until Google sign-in is enabled |
| 2.3.1 Misleading claims | Product page showed "Buyer Protection 100% safe", "Verified sellers", "Money Back Guarantee"; home banner showed "LIMITED TIME · Get upto 18% off" | Replaced with accurate copy ("Compared · Live prices · Buy direct", "Amazon vs Flipkart · Compare now") |
| 5.1.1(i) Privacy policy | No public policy URL; the in-app link opened a placeholder | `docs/privacy.html` and `docs/support.html` (GitHub Pages), linked from sign-up and About |
| 2.4.1 / screenshots | iPad declared, which requires iPad screenshots and an iPad-ready layout | iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), portrait-only |

## Risks still worth knowing

* **Backend availability** (step 0.3) is the most likely reason for a rejection.
* **Amazon blocking**: when Amazon blocks the PC, results show Flipkart only. The app says so ("Amazon is busy right now"), so this isn't a crash, but a reviewer may see fewer comparisons.
* **Third-party names and logos**: the app shows "AMZ / FLK / UBER / RPD" labels and product photos. This is normal for comparison apps, but if Apple asks under 5.2, reply that the app only shows public listings, links to the stores, and is unaffiliated (the description already says this).
