"""Places autocomplete / reverse geocode (Photon, OSM data) and routing (OSRM)."""
import math

import httpx

from ..config import get_settings

# India bounding box (lon/lat) so autocomplete doesn't wander abroad.
_INDIA_BBOX = "68.1,6.5,97.4,35.7"


def _ua() -> dict:
    return {"User-Agent": f"Tarajuu/1.0 ({get_settings().contact_email})"}


def _feature(f: dict) -> dict:
    p = f.get("properties", {})
    lon, lat = f["geometry"]["coordinates"]
    name = p.get("name") or p.get("street") or p.get("city") or "Unnamed place"
    parts = [p.get(k) for k in ("street", "district", "city", "state") if p.get(k) and p.get(k) != name]
    return {"name": name, "subtitle": ", ".join(dict.fromkeys(parts)), "lat": lat, "lon": lon}


_PLACES = "https://places.googleapis.com/v1"
_GEOCODE = "https://maps.googleapis.com/maps/api/geocode/json"


def _gkey() -> str:
    return get_settings().google_maps_api_key


async def _google_autocomplete(q: str, lat: float | None, lon: float | None, session: str | None) -> list[dict]:
    """Places API (New) autocomplete. Suggestions carry a placeId but no
    coordinates; the app resolves the chosen one via place_details()."""
    body: dict = {"input": q, "includedRegionCodes": ["in"], "languageCode": "en"}
    if session:
        body["sessionToken"] = session
    if lat is not None and lon is not None:
        body["locationBias"] = {"circle": {"center": {"latitude": lat, "longitude": lon}, "radius": 50000.0}}
        body["origin"] = {"latitude": lat, "longitude": lon}
    async with httpx.AsyncClient(timeout=8) as c:
        r = await c.post(f"{_PLACES}/places:autocomplete", json=body, headers={"X-Goog-Api-Key": _gkey()})
    r.raise_for_status()
    out = []
    for s in r.json().get("suggestions", []):
        p = s.get("placePrediction")
        if not p:
            continue
        fmt = p.get("structuredFormat", {})
        name = fmt.get("mainText", {}).get("text") or p.get("text", {}).get("text", "")
        out.append({"name": name, "subtitle": fmt.get("secondaryText", {}).get("text", ""),
                    "placeId": p["placeId"], "lat": None, "lon": None})
    return out


async def place_details(place_id: str, session: str | None = None) -> dict:
    params = {"sessionToken": session} if session else None
    headers = {"X-Goog-Api-Key": _gkey(), "X-Goog-FieldMask": "id,displayName,formattedAddress,location"}
    async with httpx.AsyncClient(timeout=8) as c:
        r = await c.get(f"{_PLACES}/places/{place_id}", params=params, headers=headers)
    r.raise_for_status()
    j = r.json()
    name = j.get("displayName", {}).get("text", "")
    addr = j.get("formattedAddress", "")
    if addr.startswith(name):
        addr = addr[len(name):].lstrip(", ")
    return {"name": name or addr, "subtitle": addr, "placeId": place_id,
            "lat": j["location"]["latitude"], "lon": j["location"]["longitude"]}


async def _google_reverse(lat: float, lon: float) -> dict | None:
    async with httpx.AsyncClient(timeout=8) as c:
        r = await c.get(_GEOCODE, params={"latlng": f"{lat},{lon}", "key": _gkey(), "language": "en"})
    r.raise_for_status()
    results = r.json().get("results", [])
    if not results:
        return None
    parts = [p.strip() for p in results[0]["formatted_address"].split(",")]
    # Drop the trailing "State PIN, India" noise for a compact label.
    parts = [p for p in parts if p != "India"]
    return {"name": parts[0], "subtitle": ", ".join(parts[1:4]), "lat": lat, "lon": lon}


async def autocomplete(q: str, lat: float | None = None, lon: float | None = None, session: str | None = None) -> list[dict]:
    if _gkey():
        return await _google_autocomplete(q, lat, lon, session)
    params = {"q": q, "limit": 8, "bbox": _INDIA_BBOX, "lang": "en"}
    if lat is not None and lon is not None:
        params.update(lat=lat, lon=lon)
    async with httpx.AsyncClient(timeout=8, headers=_ua()) as c:
        r = await c.get(f"{get_settings().photon_base}/api/", params=params)
    r.raise_for_status()
    return [_feature(f) for f in r.json().get("features", [])]


async def reverse(lat: float, lon: float) -> dict | None:
    if _gkey():
        try:
            return await _google_reverse(lat, lon)
        except Exception:  # noqa: BLE001 — fall back to Photon
            pass
    async with httpx.AsyncClient(timeout=8, headers=_ua()) as c:
        r = await c.get(f"{get_settings().photon_base}/reverse", params={"lat": lat, "lon": lon, "lang": "en"})
    r.raise_for_status()
    feats = r.json().get("features", [])
    return _feature(feats[0]) if feats else None


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


async def route(a: dict, b: dict) -> dict:
    """Driving distance (km) and duration (min). Falls back to a straight-line
    estimate × 1.35 at 24 km/h city speed if OSRM is unreachable."""
    try:
        url = f"{get_settings().osrm_base}/route/v1/driving/{a['lon']},{a['lat']};{b['lon']},{b['lat']}"
        async with httpx.AsyncClient(timeout=8, headers=_ua()) as c:
            r = await c.get(url, params={"overview": "full", "geometries": "geojson"})
        r.raise_for_status()
        rt = r.json()["routes"][0]
        return {
            "distanceKm": round(rt["distance"] / 1000, 1),
            "durationMin": max(1, round(rt["duration"] / 60)),
            "geometry": rt["geometry"]["coordinates"],
            "source": "osrm",
        }
    except Exception:  # noqa: BLE001
        km = haversine_km(a["lat"], a["lon"], b["lat"], b["lon"]) * 1.35
        return {"distanceKm": round(km, 1), "durationMin": max(1, round(km / 24 * 60)),
                "geometry": [[a["lon"], a["lat"]], [b["lon"], b["lat"]]], "source": "estimate"}
