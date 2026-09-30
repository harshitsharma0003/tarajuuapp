"""Flipkart via the official Affiliate API (https://affiliate.flipkart.com).

Needs FLIPKART_AFFILIATE_ID + FLIPKART_AFFILIATE_TOKEN. Without them the source
reports "disabled" and the app shows Amazon-only prices.
"""
import httpx

from ..config import get_settings
from .common import Listing

_BASE = "https://affiliate-api.flipkart.net/affiliate/1.0"


def _headers() -> dict:
    s = get_settings()
    return {"Fk-Affiliate-Id": s.flipkart_affiliate_id, "Fk-Affiliate-Token": s.flipkart_affiliate_token}


def _amount(obj: dict | None) -> int | None:
    if not obj or obj.get("amount") is None:
        return None
    return int(float(obj["amount"]))


def _to_listing(entry: dict) -> Listing | None:
    base = entry.get("productBaseInfoV1") or {}
    pid = base.get("productId")
    title = base.get("title")
    if not pid or not title:
        return None
    images = [u for u in (base.get("imageUrls") or {}).values() if u]
    # Prefer the largest rendition (keys look like "200x200", "400x400", "800x800").
    images.sort(key=lambda u: len(u))
    special = _amount(base.get("flipkartSpecialPrice"))
    selling = _amount(base.get("flipkartSellingPrice"))
    return Listing(
        source="flipkart",
        source_id=pid,
        title=title,
        price=special or selling,
        mrp=_amount(base.get("maximumRetailPrice")),
        image=images[-1] if images else None,
        images=list(reversed(images)),
        url=base.get("productUrl"),
        brand=base.get("productBrand"),
    )


async def search(query: str, limit: int = 12) -> list[Listing]:
    async with httpx.AsyncClient(timeout=get_settings().scrape_timeout_seconds) as c:
        r = await c.get(f"{_BASE}/search.json", params={"query": query, "resultCount": limit}, headers=_headers())
    r.raise_for_status()
    out = [_to_listing(p) for p in r.json().get("products", [])]
    return [l for l in out if l and l.price]


async def product(pid: str) -> Listing | None:
    async with httpx.AsyncClient(timeout=get_settings().scrape_timeout_seconds) as c:
        r = await c.get(f"{_BASE}/product.json", params={"id": pid}, headers=_headers())
    r.raise_for_status()
    return _to_listing(r.json())
