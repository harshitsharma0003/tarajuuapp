from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from ..config import get_settings
from ..db import pool
from ..security import current_user, optional_user
from ..services import geo, rides, uber

router = APIRouter(tags=["rides"])


class Place(BaseModel):
    name: str = ""
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class EstimateReq(BaseModel):
    pickup: Place
    dropoff: Place
    type: str = "cab"


@router.get("/places/autocomplete")
async def autocomplete(q: str = Query(..., min_length=2, max_length=100), lat: float | None = None, lon: float | None = None):
    try:
        return await geo.autocomplete(q, lat, lon)
    except Exception:  # noqa: BLE001
        raise HTTPException(502, "Place search is unavailable right now")


@router.get("/places/reverse")
async def reverse(lat: float, lon: float):
    try:
        place = await geo.reverse(lat, lon)
    except Exception:  # noqa: BLE001
        raise HTTPException(502, "Reverse geocoding is unavailable right now")
    if not place:
        raise HTTPException(404, "No address found")
    return place


@router.post("/rides/estimate")
async def estimate(body: EstimateReq, user: dict | None = Depends(optional_user)):
    if body.type not in rides.RIDE_TYPES:
        raise HTTPException(400, "Unknown ride type")
    a, b = body.pickup.model_dump(), body.dropoff.model_dump()
    res = await rides.estimate(a, b, body.type)
    if user and res["fares"]:
        top = res["fares"][:2]
        subtitle = " · ".join(f"{f['provider'].title()} ₹{f['price']}" for f in top)
        await pool().execute(
            "INSERT INTO search_history (user_id, kind, query, title, subtitle) VALUES ($1,'ride',$2,$3,$4)",
            user["id"], body.model_dump_json(), f"{a['name'] or 'Pickup'} → {b['name'] or 'Drop'}", subtitle,
        )
    return res


# ───────────────────────── API booking (Uber Guest Rides) ─────────────────────────

class BookReq(BaseModel):
    pickup: Place
    dropoff: Place
    provider: str = "uber"
    productId: str
    fareId: str | None = None
    productName: str | None = None
    price: int | None = None


async def _booking(booking_id: str, user: dict):
    row = await pool().fetchrow("SELECT * FROM ride_bookings WHERE id=$1 AND user_id=$2", booking_id, user["id"])
    if not row:
        raise HTTPException(404, "Booking not found")
    return row


@router.post("/rides/book")
async def book(body: BookReq, user: dict = Depends(current_user)):
    s = get_settings()
    if body.provider != "uber" or not (s.uber_enabled and s.uber_booking_enabled):
        raise HTTPException(409, "In-app booking isn't available — book in the provider's app")
    if not user.get("phone"):
        raise HTTPException(400, "Add a mobile number to your account to book rides")
    first, _, last = (user.get("name") or "Tarajuu Rider").strip().partition(" ")
    a, b = body.pickup.model_dump(), body.dropoff.model_dump()
    try:
        trip = await uber.create_trip(a, b, body.productId, body.fareId,
                                      {"first_name": first, "last_name": last or "-", "phone_number": user["phone"]})
    except uber.UberError as e:
        raise HTTPException(502 if e.status >= 500 else 400, f"Uber: {e.message}")
    row = await pool().fetchrow(
        """INSERT INTO ride_bookings (user_id, provider, request_id, product, fare, pickup, dropoff, status)
           VALUES ($1,'uber',$2,$3,$4,$5,$6,$7) RETURNING id""",
        user["id"], trip["request_id"], body.productName, body.price, a, b, trip.get("status", "processing"),
    )
    return {"bookingId": str(row["id"]), "status": trip.get("status", "processing")}


@router.get("/rides/bookings/{booking_id}")
async def booking_status(booking_id: str, user: dict = Depends(current_user)):
    row = await _booking(booking_id, user)
    try:
        trip = uber.normalise_trip(await uber.get_trip(row["request_id"]))
    except uber.UberError as e:
        raise HTTPException(502, f"Uber: {e.message}")
    if trip["status"] and trip["status"] != row["status"]:
        await pool().execute("UPDATE ride_bookings SET status=$2, updated_at=now() WHERE id=$1", row["id"], trip["status"])
    return {"bookingId": booking_id, "provider": row["provider"], "pickup": row["pickup"], "dropoff": row["dropoff"],
            "fare": row["fare"], **trip}


@router.delete("/rides/bookings/{booking_id}")
async def cancel_booking(booking_id: str, user: dict = Depends(current_user)):
    row = await _booking(booking_id, user)
    try:
        await uber.cancel_trip(row["request_id"])
    except uber.UberError as e:
        raise HTTPException(502, f"Uber: {e.message}")
    await pool().execute("UPDATE ride_bookings SET status='rider_canceled', updated_at=now() WHERE id=$1", row["id"])
    return {"status": "rider_canceled"}
