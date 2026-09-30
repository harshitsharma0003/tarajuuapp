from fastapi import APIRouter, Depends, HTTPException, Query

from ..db import pool
from ..security import optional_user
from ..services import products
from ..services.catalog import CATEGORIES

router = APIRouter(prefix="/products", tags=["products"])


@router.get("/categories")
async def categories():
    return [{"key": k, **v} for k, v in CATEGORIES.items()]


@router.get("/search")
async def search(
    q: str = Query(..., min_length=1, max_length=120),
    record: bool = False,
    user: dict | None = Depends(optional_user),
):
    """Poll this until `status` == "done". Pass record=true on the first call of
    a user-initiated search so it lands in Recent searches."""
    res = await products.search(q)
    if record and user:
        await pool().execute(
            "INSERT INTO search_history (user_id, kind, query, title) VALUES ($1,'product',$2,$3)",
            user["id"], q, q.strip().title(),
        )
    return res


@router.get("/home")
async def home(cat: str = "fan"):
    """The 'Compare prices' strip on Home: first 5 results for a category."""
    if cat not in CATEGORIES:
        raise HTTPException(404, "Unknown category")
    res = await products.search(CATEGORIES[cat]["query"], category=cat)
    return {**res, "results": res["results"][:5]}


@router.get("/{product_id}")
async def detail(product_id: str, user: dict | None = Depends(optional_user)):
    try:
        out = await products.detail(product_id)
    except ValueError:
        out = None
    if not out:
        raise HTTPException(404, "Product not found")
    out["favourite"] = bool(user) and bool(await pool().fetchval(
        "SELECT 1 FROM favourites WHERE user_id=$1 AND product_id=$2", user["id"], out["id"]))
    return out
