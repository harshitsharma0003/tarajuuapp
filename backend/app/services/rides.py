"""Ride fare comparison: live Uber prices via the Uber API, rate-card estimates
for providers without a public API (Rapido, Ola) or when Uber is not configured.
"""
import logging
import time
from urllib.parse import urlencode

import httpx

from ..config import get_settings
from . import geo

log = logging.getLogger(__name__)

RIDE_TYPES = {
    "cab": {"label": "Cab", "emoji": "🚗"},
    "premium": {"label": "Premium", "emoji": "✨"},
    "auto": {"label": "Auto", "emoji": "🛺"},
    "bike": {"label": "Bike", "emoji": "🏍️"},
}

# Indicative Delhi-NCR rate cards: (product name, base ₹, ₹/km, ₹/min, minimum ₹).
# Tune these in one place; they are only used where no live API price exists.
RATE_CARDS = {
    "uber": {
        "cab": ("UberGo", 50, 12.0, 1.5, 90),
        "premium": ("Uber Premier", 80, 17.0, 2.0, 150),
        "auto": ("Uber Auto", 30, 10.0, 1.0, 40),
        "bike": ("Uber Moto", 20, 5.5, 1.0, 30),
    },
    "rapido": {
        "cab": ("Rapido Cab", 45, 10.5, 1.2, 80),
        "premium": ("Rapido Prime", 70, 15.0, 1.8, 130),
        "auto": ("Rapido Auto", 25, 9.0, 0.8, 35),
        "bike": ("Rapido Bike", 15, 4.5, 0.8, 25),
    },
    "ola": {
        "cab": ("Ola Mini", 50, 11.5, 1.5, 85),
        "premium": ("Ola Prime Sedan", 80, 16.0, 2.0, 140),
        "auto": ("Ola Auto", 30, 9.5, 1.0, 40),
        "bike": ("Ola Bike", 18, 5.0, 1.0, 28),
    },
}
PICKUP_ETA_MIN = {"uber": 4, "rapido": 5, "ola": 6}

# Uber product display names → our ride types.
_UBER_TYPE_HINTS = [
    ("bike", ("moto", "bike")),
    ("auto", ("auto",)),
    ("premium", ("premier", "black", "xl", "comfort", "sedan", "prime")),
    ("cab", ("go", "uberx", "mini", "hatch")),
]


def uber_type(display_name: str) -> str | None:
    n = display_name.lower()
    for t, hints in _UBER_TYPE_HINTS:
        if any(h in n for h in hints):
            return t
    return None


def deeplink(provider: str, a: dict, b: dict, product_id: str | None = None) -> str:
    if provider == "uber":
        q = {
            "action": "setPickup",
            "pickup[latitude]": a["lat"], "pickup[longitude]": a["lon"], "pickup[nickname]": a.get("name", ""),
            "dropoff[latitude]": b["lat"], "dropoff[longitude]": b["lon"], "dropoff[nickname]": b.get("name", ""),
        }
        if product_id:
            q["product_id"] = product_id
        return "https://m.uber.com/ul/?" + urlencode(q)
    if provider == "ola":
        return "https://book.olacabs.com/?" + urlencode({
            "serviceType": "p2p", "lat": a["lat"], "lng": a["lon"], "drop_lat": b["lat"], "drop_lng": b["lon"],
        })
    return "https://www.rapido.bike/"


def rate_card_fare(provider: str, ride_type: str, km: float, minutes: int) -> dict:
    name, base, per_km, per_min, minimum = RATE_CARDS[provider][ride_type]
    price = max(minimum, round(base + per_km * km + per_min * minutes))
    return {"product": name, "price": price, "priceLow": price, "priceHigh": price}


# ───────────────────────── Uber API ─────────────────────────

_token: dict = {"value": None, "exp": 0.0}


async def _uber_token(c: httpx.AsyncClient) -> str:
    if _token["value"] and time.time() < _token["exp"] - 60:
        return _token["value"]
    s = get_settings()
    r = await c.post("https://auth.uber.com/oauth/v2/token", data={
        "client_id": s.uber_client_id, "client_secret": s.uber_client_secret,
        "grant_type": "client_credentials", "scope": s.uber_scope,
    })
    r.raise_for_status()
    body = r.json()
    _token.update(value=body["access_token"], exp=time.time() + int(body.get("expires_in", 3600)))
    return _token["value"]


def _parse_riders(body: dict) -> list[dict]:
    """GET /v1.2/estimates/price → prices[]."""
    out = []
    for p in body.get("prices", []):
        low, high = p.get("low_estimate"), p.get("high_estimate")
        if low is None:
            continue
        out.append({"name": p.get("display_name", "Uber"), "product_id": p.get("product_id"),
                    "low": int(low), "high": int(high or low),
                    "duration_min": round(p["duration"] / 60) if p.get("duration") else None})
    return out


def _parse_guests(body: dict) -> list[dict]:
    """POST /v1/guests/trips/estimates → product_estimates[]."""
    out = []
    for e in body.get("product_estimates", []):
        product = e.get("product", {})
        info = e.get("estimate_info", {})
        fare = info.get("fare") or {}
        est = info.get("estimate") or {}
        low = fare.get("value") or est.get("low_estimate")
        if low is None:
            continue
        trip = info.get("trip") or {}
        out.append({"name": product.get("display_name", "Uber"), "product_id": product.get("product_id"),
                    "low": int(float(low)), "high": int(float(est.get("high_estimate") or low)),
                    "duration_min": round(trip["duration_estimate"] / 60) if trip.get("duration_estimate") else None,
                    "pickup_min": info.get("pickup_estimate")})
    return out


async def uber_estimates(a: dict, b: dict) -> list[dict]:
    s = get_settings()
    async with httpx.AsyncClient(timeout=10) as c:
        token = await _uber_token(c)
        headers = {"Authorization": f"Bearer {token}", "Accept-Language": "en_US"}
        if "guests" in s.uber_scope:
            r = await c.post(f"{s.uber_api_base}/v1/guests/trips/estimates", headers=headers, json={
                "pickup": {"latitude": a["lat"], "longitude": a["lon"]},
                "dropoff": {"latitude": b["lat"], "longitude": b["lon"]},
            })
            r.raise_for_status()
            return _parse_guests(r.json())
        r = await c.get(f"{s.uber_api_base}/v1.2/estimates/price", headers=headers, params={
            "start_latitude": a["lat"], "start_longitude": a["lon"],
            "end_latitude": b["lat"], "end_longitude": b["lon"],
        })
        r.raise_for_status()
        return _parse_riders(r.json())


# ───────────────────────── public API ─────────────────────────

async def estimate(a: dict, b: dict, ride_type: str) -> dict:
    rt = await geo.route(a, b)
    km, mins = rt["distanceKm"], rt["durationMin"]

    uber_live: dict | None = None
    uber_status = "disabled"
    if get_settings().uber_enabled:
        try:
            live = [p for p in await uber_estimates(a, b) if uber_type(p["name"]) == ride_type]
            if live:
                cheapest = min(live, key=lambda p: p["low"])
                uber_live = cheapest
                uber_status = "live"
            else:
                uber_status = "no_product"
        except Exception:  # noqa: BLE001
            log.exception("Uber estimate failed")
            uber_status = "error"

    fares = []
    for provider in ("uber", "rapido", "ola"):
        if provider == "uber" and uber_live:
            fare = {"product": uber_live["name"], "price": uber_live["low"],
                    "priceLow": uber_live["low"], "priceHigh": uber_live["high"]}
            duration = uber_live.get("duration_min") or mins
            eta = uber_live.get("pickup_min") or PICKUP_ETA_MIN["uber"]
            estimated = False
            link = deeplink("uber", a, b, uber_live.get("product_id"))
        else:
            fare = rate_card_fare(provider, ride_type, km, mins)
            duration, eta, estimated = mins, PICKUP_ETA_MIN[provider], True
            link = deeplink(provider, a, b)
        fares.append({"provider": provider, **fare, "durationMin": duration, "pickupEtaMin": eta,
                      "distanceKm": km, "estimated": estimated, "deeplink": link})

    fares.sort(key=lambda f: f["price"])
    return {
        "type": ride_type,
        "label": RIDE_TYPES[ride_type]["label"],
        "emoji": RIDE_TYPES[ride_type]["emoji"],
        "distanceKm": km,
        "durationMin": mins,
        "route": rt["geometry"],
        "fares": fares,
        "savings": fares[-1]["price"] - fares[0]["price"],
        "uberStatus": uber_status,
    }
