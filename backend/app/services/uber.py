"""Uber Guest Rides API client (https://developer.uber.com/docs/guest-rides).

Needs an Uber app with the `guests.trips` scope and, for a third-party app,
the Uber for Business organization UUID (trips are billed to that org — the
API has no cash/payment option). UBER_SANDBOX=true targets sandbox-api.uber.com.
"""
import time

import httpx

from ..config import get_settings

_token: dict = {"value": None, "exp": 0.0}


def _base() -> str:
    s = get_settings()
    return "https://sandbox-api.uber.com" if s.uber_sandbox else s.uber_api_base


async def _access_token(c: httpx.AsyncClient) -> str:
    if _token["value"] and time.time() < _token["exp"] - 60:
        return _token["value"]
    s = get_settings()
    r = await c.post(s.uber_sandbox_auth_url if s.uber_sandbox else s.uber_auth_url, data={
        "client_id": s.uber_client_id, "client_secret": s.uber_client_secret,
        "grant_type": "client_credentials", "scope": s.uber_scope,
    })
    r.raise_for_status()
    body = r.json()
    _token.update(value=body["access_token"], exp=time.time() + int(body.get("expires_in", 3600)))
    return _token["value"]


async def _headers(c: httpx.AsyncClient) -> dict:
    s = get_settings()
    h = {"Authorization": f"Bearer {await _access_token(c)}", "Accept-Language": "en"}
    if s.uber_org_uuid:
        h["x-uber-organizationuuid"] = s.uber_org_uuid
    if s.uber_sandbox and s.uber_sandbox_run_id:
        h["x-uber-sandbox-runuuid"] = s.uber_sandbox_run_id
    return h


def _point(p: dict) -> dict:
    out = {"latitude": p["lat"], "longitude": p["lon"]}
    if p.get("name"):
        out["address"] = p["name"]
    return out


# ───────────────────────── estimates ─────────────────────────

def parse_estimates(body: dict) -> list[dict]:
    """Normalise /v1/guests/trips/estimates → [{name, product_id, fare_id, low, high, ...}]."""
    out = []
    for e in body.get("product_estimates", []):
        product = e.get("product", {})
        info = e.get("estimate_info", {})
        fare = info.get("fare") or {}
        est = info.get("estimate") or {}
        low = fare.get("value") if fare.get("value") is not None else est.get("low_estimate")
        if low is None or info.get("no_cars_available"):
            continue
        trip = info.get("trip") or {}
        out.append({
            "name": product.get("display_name", "Uber"),
            "product_id": product.get("product_id"),
            "fare_id": info.get("fare_id") or fare.get("fare_id"),
            "low": int(float(low)),
            "high": int(float(est.get("high_estimate") or low)),
            "duration_min": round(trip["duration_estimate"] / 60) if trip.get("duration_estimate") else None,
            "pickup_min": info.get("pickup_estimate"),
            "fulfillment": e.get("fulfillment_indicator"),
        })
    return out


async def estimates(a: dict, b: dict) -> list[dict]:
    async with httpx.AsyncClient(timeout=15) as c:
        r = await c.post(f"{_base()}/v1/guests/trips/estimates", headers=await _headers(c),
                         json={"pickup": _point(a), "dropoff": _point(b)})
    r.raise_for_status()
    return parse_estimates(r.json())


# ───────────────────────── trips ─────────────────────────

async def create_trip(a: dict, b: dict, product_id: str, fare_id: str | None, guest: dict) -> dict:
    payload = {
        "guest": guest,  # {first_name, last_name, phone_number}
        "pickup": _point(a),
        "dropoff": _point(b),
        "product_id": product_id,
        "call_enabled": True,
        "sender_display_name": "Tarajuu",
        "expense_memo": "Tarajuu ride",
    }
    if fare_id:
        payload["fare_id"] = fare_id  # locks the upfront fare shown to the user
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.post(f"{_base()}/v1/guests/trips", headers=await _headers(c), json=payload)
    if r.status_code >= 400:
        raise UberError(r.status_code, _error_message(r))
    return r.json()


async def get_trip(request_id: str) -> dict:
    async with httpx.AsyncClient(timeout=15) as c:
        r = await c.get(f"{_base()}/v1/guests/trips/{request_id}", headers=await _headers(c))
    if r.status_code >= 400:
        raise UberError(r.status_code, _error_message(r))
    return r.json()


async def cancel_trip(request_id: str) -> None:
    async with httpx.AsyncClient(timeout=15) as c:
        r = await c.delete(f"{_base()}/v1/guests/trips/{request_id}", headers=await _headers(c))
    if r.status_code >= 400 and r.status_code != 404:
        raise UberError(r.status_code, _error_message(r))


TERMINAL = {"no_drivers_available", "driver_canceled", "rider_canceled", "completed", "failed", "expired"}


def normalise_trip(t: dict) -> dict:
    """Trip JSON → what the app's tracking screen needs."""
    driver = t.get("driver") or {}
    vehicle = t.get("vehicle") or {}
    loc = t.get("location") or {}
    pickup = t.get("pickup") or {}
    dest = t.get("destination") or {}
    pin = (t.get("directed_dispatch_info") or {}).get("dispatch_pin")
    return {
        "status": t.get("status"),
        "terminal": t.get("status") in TERMINAL,
        "product": (t.get("product") or {}).get("display_name"),
        "driver": {
            "name": driver.get("name"),
            "rating": driver.get("rating"),
            "phone": driver.get("phone_number"),
            "photo": driver.get("picture_url"),
        } if driver else None,
        "vehicle": {
            "make": vehicle.get("make"),
            "model": vehicle.get("model"),
            "color": vehicle.get("vehicle_color_name"),
            "plate": vehicle.get("license_plate"),
        } if vehicle else None,
        "driverLocation": {"lat": loc["latitude"], "lon": loc["longitude"], "bearing": loc.get("bearing", 0)}
        if loc.get("latitude") is not None else None,
        "pickupEtaMin": pickup.get("eta"),
        "dropoffEtaMin": dest.get("eta"),
        "pin": pin,
        "trackingUrl": t.get("rider_tracking_url"),
    }


class UberError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def _error_message(r: httpx.Response) -> str:
    try:
        body = r.json()
        return body.get("message") or body.get("error_description") or body.get("code") or r.text[:200]
    except ValueError:
        return r.text[:200]
