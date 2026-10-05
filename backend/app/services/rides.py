"""Ride fare comparison: live Uber prices via the Uber API, rate-card estimates
for providers without a public API (Rapido, Ola) or when Uber is not configured.
"""
import logging
from urllib.parse import urlencode

from ..config import get_settings
from . import geo, uber

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


# ───────────────────────── public API ─────────────────────────

async def estimate(a: dict, b: dict, ride_type: str) -> dict:
    rt = await geo.route(a, b)
    km, mins = rt["distanceKm"], rt["durationMin"]

    uber_live: dict | None = None
    uber_status = "disabled"
    if get_settings().uber_enabled:
        try:
            products = await uber.estimates(a, b)
            live = [p for p in products if uber_type(p["name"]) == ride_type]
            if live:
                uber_live = min(live, key=lambda p: p["low"])
                uber_status = "live"
            else:
                # Uber answered but has no car of this type here (or doesn't serve this pickup).
                uber_status = "not_serviced" if not products else "no_product"
        except Exception:  # noqa: BLE001
            log.exception("Uber estimate failed")
            uber_status = "error"

    fares = []
    providers = [p.strip() for p in get_settings().ride_providers.split(",") if p.strip() in RATE_CARDS] or ["uber"]
    for provider in providers:
        if provider == "uber" and uber_live:
            fare = {"product": uber_live["name"], "price": uber_live["low"],
                    "priceLow": uber_live["low"], "priceHigh": uber_live["high"]}
            duration = uber_live.get("duration_min") or mins
            eta = uber_live.get("pickup_min") or PICKUP_ETA_MIN["uber"]
            estimated = False
            link = deeplink("uber", a, b, uber_live.get("product_id"))
            fare["productId"] = uber_live.get("product_id")
            fare["fareId"] = uber_live.get("fare_id")
            fare["bookable"] = get_settings().uber_booking_enabled and bool(uber_live.get("product_id"))
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
