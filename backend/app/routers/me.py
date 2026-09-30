"""Signed-in user: profile, savings badge, recent searches, favourites."""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..db import pool
from ..security import current_user
from ..services.products import serialise
from .auth import user_json

router = APIRouter(prefix="/me", tags=["me"])


class ProfileUpdate(BaseModel):
    name: str | None = None
    email: str | None = None


class BuyClick(BaseModel):
    productId: str | None = None
    kind: str = "product"  # "product" | "ride"
    source: str
    savedAmount: int = 0


@router.get("")
async def me(user: dict = Depends(current_user)):
    saved = await pool().fetchval("SELECT COALESCE(SUM(saved_amount),0) FROM buy_clicks WHERE user_id=$1", user["id"])
    return {"user": user_json(user), "savedTotal": saved}


@router.patch("")
async def update(body: ProfileUpdate, user: dict = Depends(current_user)):
    row = await pool().fetchrow(
        "UPDATE users SET name=COALESCE($2,name), email=COALESCE($3,email) WHERE id=$1 RETURNING *",
        user["id"], body.name, body.email,
    )
    return {"user": user_json(row)}


@router.get("/recent")
async def recent(user: dict = Depends(current_user)):
    rows = await pool().fetch(
        """SELECT DISTINCT ON (kind, lower(title)) kind, query, title, subtitle, created_at
           FROM search_history WHERE user_id=$1 ORDER BY kind, lower(title), created_at DESC""",
        user["id"],
    )
    searches = sorted(rows, key=lambda r: r["created_at"], reverse=True)[:8]
    favs = await pool().fetch(
        """SELECT p.* FROM favourites f JOIN products p ON p.id=f.product_id
           WHERE f.user_id=$1 ORDER BY f.created_at DESC LIMIT 20""",
        user["id"],
    )
    return {
        "searches": [{"kind": r["kind"], "query": r["query"], "title": r["title"], "subtitle": r["subtitle"]}
                     for r in searches],
        "favourites": [serialise(r) for r in favs],
    }


@router.put("/favourites/{product_id}")
async def add_fav(product_id: str, user: dict = Depends(current_user)):
    if not await pool().fetchval("SELECT 1 FROM products WHERE id=$1", product_id):
        raise HTTPException(404, "Product not found")
    await pool().execute("INSERT INTO favourites (user_id, product_id) VALUES ($1,$2) ON CONFLICT DO NOTHING",
                         user["id"], product_id)
    return {"favourite": True}


@router.delete("/favourites/{product_id}")
async def remove_fav(product_id: str, user: dict = Depends(current_user)):
    await pool().execute("DELETE FROM favourites WHERE user_id=$1 AND product_id=$2", user["id"], product_id)
    return {"favourite": False}


@router.post("/buy-click")
async def buy_click(body: BuyClick, user: dict = Depends(current_user)):
    await pool().execute(
        "INSERT INTO buy_clicks (user_id, product_id, kind, source, saved_amount) VALUES ($1,$2,$3,$4,$5)",
        user["id"], body.productId, body.kind, body.source, max(0, body.savedAmount),
    )
    return {"ok": True}
