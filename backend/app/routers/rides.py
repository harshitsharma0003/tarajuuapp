from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from ..db import pool
from ..security import optional_user
from ..services import geo, rides

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
