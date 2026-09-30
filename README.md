# Tarajuu (तराजू) — Compare Smarter

Price comparison for India: products (Amazon.in vs Flipkart) and rides (Uber vs
Rapido vs Ola). The Flutter app is a screen-by-screen build of the
`Tarajuu_v1.html` prototype (same colours, fonts, layout and flows), backed by a
FastAPI + PostgreSQL server that runs on a single GCP VM.

```
app/        Flutter app (Android + iOS)          ─┐
backend/    FastAPI API + scrapers + Uber client   ├─ one repo
deploy/     Docker Compose (Postgres + API + Caddy HTTPS) + VM setup script ─┘
```

```
 Flutter app ──HTTPS──▶ Caddy ──▶ FastAPI ──▶ PostgreSQL        (all on the VM)
   │  Firebase Auth                  ├─▶ amazon.in  (plain HTML scrape, background job)
   │  (phone OTP, Google)            ├─▶ Flipkart Affiliate API (when keys are set)
   └─ ID token ─▶ /api/auth/firebase ├─▶ Uber API  (live fares when keys are set)
                                     └─▶ Photon (places) · OSRM (route distance)
```

## How it works

**Search (PLP).** `GET /api/products/search?q=` returns immediately. If the cache
is fresh (60 min) you get `status: "done"` with results. Otherwise the server starts
a background scrape and answers `status: "pending"` (with any stale results); the
app shows the prototype's "Searching Amazon.in… / Comparing prices…" loader and
polls every 1.5 s until `done`. Amazon and Flipkart listings of the same item are
paired by `services/matcher.py` and stored as one `products` row, with every price
change written to `price_history`.

**Product detail (PDP).** `GET /api/products/{id}` refreshes the product pages
(every 6 h): full-size image gallery, current price, MRP, rating, delivery date.

**Rides.** `POST /api/rides/estimate` routes the trip with OSRM, asks the Uber API
for live fares, and prices Rapido/Ola (which have no public API) from rate cards
in `services/rides.py` — those fares are labelled **est.** in the app. "Confirm
Ride" opens the provider's app via deep link with pickup and drop pre-filled; the
booking itself happens there.

**Auth.** Firebase Auth in the app (phone OTP, Google). The app sends the
Firebase ID token to `POST /api/auth/firebase`; the server verifies it against
Google's public keys and returns a Tarajuu JWT.

## API

| Method | Path | Notes |
|---|---|---|
| POST | `/api/auth/firebase` | `{idToken, name?, email?, acceptedTerms?}` → `{token, user}` |
| GET/PATCH | `/api/me` | profile + `savedTotal` (the "₹ saved" badge) |
| GET | `/api/me/recent` | recent searches + favourites |
| PUT/DELETE | `/api/me/favourites/{id}` | |
| POST | `/api/me/buy-click` | records a Buy/Book tap and the amount saved |
| GET | `/api/products/search?q=&record=` | background search; poll until `status=done` |
| GET | `/api/products/home?cat=fan` | Home "Compare prices" strip |
| GET | `/api/products/{id}` | PDP: gallery, sellers, price history |
| GET | `/api/places/autocomplete?q=` · `/api/places/reverse?lat=&lon=` | |
| POST | `/api/rides/estimate` | `{pickup, dropoff, type: cab\|premium\|auto\|bike}` |
| GET | `/api/health` | shows which integrations are configured |

## Run locally

```bash
# backend (needs a local Postgres; set DATABASE_URL in backend/.env)
cd backend
python -m venv .venv && .venv/Scripts/pip install -r requirements.txt   # Windows
cp .env.example .env
.venv/Scripts/uvicorn app.main:app --reload --port 8000
.venv/Scripts/python -m pytest tests -q

# app (Android emulator reaches the host at 10.0.2.2)
cd app
flutter pub get
flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api
```

## Deploy to the GCP VM

```bash
# on the VM (Ubuntu 22.04/24.04, ports 80 + 443 open)
git clone https://github.com/helloharshit123-tech/Tarajuuapp.git && cd Tarajuuapp
bash deploy/setup-vm.sh      # installs Docker, writes deploy/.env with secrets, starts everything
```

The API is served at `https://<vm-ip-with-dashes>.sslip.io/api` with a real
Let's Encrypt certificate (no domain purchase needed; swap `DOMAIN` in
`deploy/.env` for your own domain later). Postgres runs in the same Compose
project with a persistent volume and is not exposed to the internet.

Build the app against it:

```bash
flutter build apk --release --dart-define=API_BASE=https://<vm-ip-with-dashes>.sslip.io/api
```

## Firebase setup (phone OTP + Google)

1. Create/choose a Firebase project → Authentication → enable **Phone** and **Google**.
2. `dart pub global activate flutterfire_cli` then, in `app/`: `flutterfire configure`
   (replaces the placeholder `lib/firebase_options.dart`, adds `google-services.json`).
3. Add your debug + release **SHA-1 and SHA-256** to the Android app in Firebase
   (needed for phone auth and Google sign-in).
4. Set `FIREBASE_PROJECT_ID` in `deploy/.env` and restart: `docker compose up -d`.

## Integrations and their keys (`deploy/.env`)

| Integration | Keys | Without keys |
|---|---|---|
| Amazon.in | none (plain scraping) | — |
| Flipkart | `FLIPKART_AFFILIATE_ID`, `FLIPKART_AFFILIATE_TOKEN` | Amazon-only prices; app says "Flipkart prices unavailable" |
| Uber | `UBER_CLIENT_ID`, `UBER_CLIENT_SECRET`, `UBER_SCOPE` | Uber priced from rate card (est.) |
| Firebase | `FIREBASE_PROJECT_ID` | sign-in returns 503 |

Notes:
- The Amazon scraper is deliberately plain (one ordinary browser header set, no
  proxies/rotation/CAPTCHA solving). Cloud IPs are often challenged; when that
  happens the source reports `blocked`, cached data is served, and the app says so.
- Uber's estimate APIs are privileged: your Uber developer app must be approved
  for the scope you set (`guests.trips` for Guest Rides, or
  `ride_request.estimate` for the Riders API).
- `DEMO_TRACKING=true` (`--dart-define`) re-enables the prototype's simulated live-
  tracking screen after Confirm Ride, for demos only.
