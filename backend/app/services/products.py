"""Product search (PLP) and detail (PDP): scrape → match → persist → serialise."""
import asyncio
import logging
from datetime import datetime, timedelta, timezone

from ..config import get_settings
from ..db import pool
from ..scrapers import amazon, flipkart
from ..scrapers.common import Listing, SourceBlocked
from . import matcher
from .agent_queue import AgentOffline
from .catalog import category_for, emoji_for

log = logging.getLogger(__name__)


def normalise(q: str) -> str:
    return " ".join(q.lower().split())


# ───────────────────────── scraping with status ─────────────────────────

async def _run_source(name: str, coro) -> tuple[str, list[Listing]]:
    try:
        return "ok", await coro
    except SourceBlocked:
        log.warning("%s blocked the request", name)
        return "blocked", []
    except AgentOffline as e:
        log.warning("%s: %s", name, e)
        return "offline", []
    except Exception:  # noqa: BLE001 — one flaky source must not sink the search
        log.exception("%s search failed", name)
        return "error", []


async def _fetch_listings(query: str) -> tuple[dict, list[Listing], list[Listing]]:
    s = get_settings()
    tasks = {}
    if s.amazon_enabled:
        tasks["amazon"] = _run_source("amazon", amazon.search(query))
    if s.flipkart_enabled:
        tasks["flipkart"] = _run_source("flipkart", flipkart.search(query))
    results = dict(zip(tasks, await asyncio.gather(*tasks.values())))
    sources = {
        "amazon": results["amazon"][0] if "amazon" in results else "disabled",
        "flipkart": results["flipkart"][0] if "flipkart" in results else "disabled",
    }
    amz = results.get("amazon", ("", []))[1]
    fk = results.get("flipkart", ("", []))[1]
    return sources, amz, fk


# ───────────────────────── persistence ─────────────────────────

async def _upsert(conn, a: Listing | None, f: Listing | None, category: str | None) -> str:
    """Insert or update the product row for a matched pair; returns its id."""
    existing = None
    if a:
        existing = await conn.fetchrow("SELECT id, amazon_price, flipkart_price FROM products WHERE amazon_asin=$1", a.source_id)
    if not existing and f:
        existing = await conn.fetchrow("SELECT id, amazon_price, flipkart_price FROM products WHERE flipkart_pid=$1", f.source_id)

    lead = a or f
    fields = {
        "title": lead.title,
        "brand": lead.brand or lead.title.split()[0],
        "category": category,
        "image_url": (a.image if a and a.image else f.image if f else None),
    }
    if a:
        fields.update(amazon_asin=a.source_id, amazon_price=a.price, amazon_mrp=a.mrp, amazon_url=a.url,
                      amazon_rating=a.rating, amazon_reviews=a.reviews)
    if f:
        fields.update(flipkart_pid=f.source_id, flipkart_price=f.price, flipkart_mrp=f.mrp, flipkart_url=f.url,
                      flipkart_rating=f.rating, flipkart_reviews=f.reviews)

    if existing:
        pid = existing["id"]
        # A different listing may already own this ASIN/PID on another row; skip
        # re-linking in that case rather than violate the unique constraint.
        for col, key in (("amazon_asin", a), ("flipkart_pid", f)):
            if key:
                owner = await conn.fetchval(f"SELECT id FROM products WHERE {col}=$1", key.source_id)
                if owner and owner != pid:
                    fields.pop(col, None)
        if fields.get("category") is None:
            fields.pop("category")
        sets = ", ".join(f"{k}=${i + 2}" for i, k in enumerate(fields))
        await conn.execute(f"UPDATE products SET {sets}, updated_at=now() WHERE id=$1", pid, *fields.values())
    else:
        cols = ", ".join(fields)
        params = ", ".join(f"${i + 1}" for i in range(len(fields)))
        pid = await conn.fetchval(f"INSERT INTO products ({cols}) VALUES ({params}) RETURNING id", *fields.values())

    for src, listing, old in (("amazon", a, existing and existing["amazon_price"]),
                              ("flipkart", f, existing and existing["flipkart_price"])):
        if listing and listing.price and listing.price != old:
            await conn.execute("INSERT INTO price_history (product_id, source, price) VALUES ($1,$2,$3)",
                               pid, src, listing.price)
    return pid


# ───────────────────────── serialisation ─────────────────────────

def serialise(row, detail: bool = False) -> dict:
    offers = []
    if row["amazon_price"]:
        offers.append({"source": "amazon", "price": row["amazon_price"], "mrp": row["amazon_mrp"], "url": row["amazon_url"]})
    if row["flipkart_price"]:
        offers.append({"source": "flipkart", "price": row["flipkart_price"], "mrp": row["flipkart_mrp"], "url": row["flipkart_url"]})
    prices = [o["price"] for o in offers]
    best = min(prices) if prices else None
    worst = max(prices) if prices else None
    mrp = max([o["mrp"] for o in offers if o["mrp"]] or [0]) or None
    # Strike-through price: the other platform's price if dearer, else the MRP.
    compare_at = worst if worst and best and worst > best else mrp
    off_pct = round((compare_at - best) / compare_at * 100) if compare_at and best and compare_at > best else 0

    rating = row["amazon_rating"] or row["flipkart_rating"]
    rating = round(rating, 1) if rating else None
    reviews = max(row["amazon_reviews"] or 0, row["flipkart_reviews"] or 0) or None
    badge = None
    if off_pct >= 5:
        badge = {"text": f"-{off_pct}%", "type": "off"}
    elif reviews and reviews >= 10000:
        badge = {"text": "HOT", "type": "hot"}

    out = {
        "id": str(row["id"]),
        "title": row["title"],
        "brand": row["brand"],
        "category": row["category"],
        "emoji": emoji_for(row["category"]),
        "image": row["image_url"],
        "rating": rating,
        "reviews": reviews,
        "bestPrice": best,
        "compareAtPrice": compare_at if compare_at and best and compare_at > best else None,
        "offPercent": off_pct,
        "badge": badge,
        "offers": sorted(offers, key=lambda o: o["price"]),
    }
    if detail:
        images = list(row["images"] or [])
        if row["image_url"] and row["image_url"] not in images:
            images.insert(0, row["image_url"])
        out["images"] = images
    return out


async def _load(ids: list) -> list[dict]:
    if not ids:
        return []
    rows = await pool().fetch("SELECT * FROM products WHERE id = ANY($1::uuid[])", ids)
    by_id = {r["id"]: r for r in rows}
    return [serialise(by_id[i]) for i in ids if i in by_id]


# ───────────────────────── public API ─────────────────────────

# Background search jobs, keyed by normalised query. The API runs as a single
# uvicorn worker (see Dockerfile), so an in-process registry is enough.
_jobs: dict[str, asyncio.Task] = {}
_finished: dict[str, tuple[datetime, dict]] = {}  # recent jobs that found nothing


async def _scrape_and_store(norm: str, category: str | None) -> None:
    sources, amz, fk = await _fetch_listings(norm)
    ids = []
    async with pool().acquire() as conn:
        async with conn.transaction():
            for a, f in matcher.pair(amz, fk):
                ids.append(await _upsert(conn, a, f, category))
            if ids:
                await conn.execute(
                    """INSERT INTO search_cache (query_norm, product_ids, sources, fetched_at)
                       VALUES ($1, $2, $3, now())
                       ON CONFLICT (query_norm) DO UPDATE SET product_ids=$2, sources=$3, fetched_at=now()""",
                    norm, ids, sources,
                )
    if not ids:
        _finished[norm] = (datetime.now(timezone.utc), sources)


def _start_job(norm: str, category: str | None) -> None:
    if norm in _jobs and not _jobs[norm].done():
        return
    _finished.pop(norm, None)
    task = asyncio.create_task(_scrape_and_store(norm, category))

    def _done(t: asyncio.Task) -> None:
        _jobs.pop(norm, None)
        if not t.cancelled() and t.exception():
            log.error("search job %r failed", norm, exc_info=t.exception())
            _finished[norm] = (datetime.now(timezone.utc), {"amazon": "error", "flipkart": "error"})

    task.add_done_callback(_done)
    _jobs[norm] = task


async def search(query: str, category: str | None = None) -> dict:
    """Non-blocking search.

    Returns status "done" with results when the cache is fresh. Otherwise it
    starts (or joins) a background scrape and returns status "pending" plus any
    stale results; the app polls the same endpoint until status is "done".
    """
    norm = normalise(query)
    category = category or category_for(norm)
    ttl = timedelta(minutes=get_settings().search_cache_minutes)
    now = datetime.now(timezone.utc)
    cached = await pool().fetchrow("SELECT * FROM search_cache WHERE query_norm=$1", norm)
    stale_results = await _load(cached["product_ids"]) if cached else []

    if cached and now - cached["fetched_at"] < ttl:
        return {"query": query, "status": "done", "results": stale_results, "sources": cached["sources"]}

    finished = _finished.get(norm)
    if finished and norm not in _jobs and now - finished[0] < timedelta(seconds=60):
        # The last scrape came back empty/blocked; report it instead of looping.
        return {"query": query, "status": "done", "results": stale_results, "sources": finished[1]}

    _start_job(norm, category)
    return {"query": query, "status": "pending", "results": stale_results,
            "sources": cached["sources"] if cached else {}}


async def detail(product_id: str) -> dict | None:
    row = await pool().fetchrow("SELECT * FROM products WHERE id=$1", product_id)
    if not row:
        return None
    ttl = timedelta(hours=get_settings().detail_cache_hours)
    stale = not row["details_fetched_at"] or datetime.now(timezone.utc) - row["details_fetched_at"] > ttl
    delivery: dict[str, str | None] = {}

    if stale:
        s = get_settings()
        jobs = {}
        if row["amazon_asin"] and s.amazon_enabled:
            jobs["amazon"] = amazon.product(row["amazon_asin"])
        if row["flipkart_pid"] and s.flipkart_enabled:
            jobs["flipkart"] = flipkart.product(row["flipkart_pid"])
        results = dict(zip(jobs, await asyncio.gather(*jobs.values(), return_exceptions=True)))

        updates: dict = {}
        images: list[str] = []
        for src, res in results.items():
            if isinstance(res, Exception) or res is None:
                log.warning("%s detail fetch failed for %s: %r", src, product_id, res)
                continue
            if res.price:
                updates[f"{src}_price"] = res.price
            if res.mrp:
                updates[f"{src}_mrp"] = res.mrp
            if res.rating:
                updates[f"{src}_rating"] = res.rating
            if res.reviews:
                updates[f"{src}_reviews"] = res.reviews
            if src == "amazon" and res.brand:
                updates["brand"] = res.brand
            delivery[src] = res.delivery
            images += [u for u in res.images if u not in images]
        if images:
            updates["images"] = images[:10]
            updates["image_url"] = images[0]
        async with pool().acquire() as conn:
            for src in ("amazon", "flipkart"):
                new = updates.get(f"{src}_price")
                if new and new != row[f"{src}_price"]:
                    await conn.execute("INSERT INTO price_history (product_id, source, price) VALUES ($1,$2,$3)",
                                       row["id"], src, new)
            sets = ", ".join(f"{k}=${i + 2}" for i, k in enumerate(updates))
            prefix = f"{sets}, " if sets else ""
            await conn.execute(f"UPDATE products SET {prefix}details_fetched_at=now(), updated_at=now() WHERE id=$1",
                               row["id"], *updates.values())
            row = await conn.fetchrow("SELECT * FROM products WHERE id=$1", row["id"])

    out = serialise(row, detail=True)
    names = {"amazon": ("Amazon.in", "AMZ"), "flipkart": ("Flipkart", "FLK")}
    best = out["bestPrice"]
    out["sellers"] = [
        {
            "source": o["source"],
            "name": names[o["source"]][0],
            "logo": names[o["source"]][1],
            "price": o["price"],
            "mrp": o["mrp"],
            "url": o["url"],
            "delivery": delivery.get(o["source"]),
            "verified": True,
            "best": o["price"] == best,
        }
        for o in out["offers"]
    ]
    hist = await pool().fetch(
        "SELECT source, price, recorded_at FROM price_history WHERE product_id=$1 ORDER BY recorded_at DESC LIMIT 30",
        row["id"],
    )
    out["priceHistory"] = [{"source": h["source"], "price": h["price"], "at": h["recorded_at"].isoformat()} for h in hist]
    return out
