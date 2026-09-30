"""Tarajuu scrape agent — runs on a PC with an ordinary internet connection.

Amazon rejects requests from cloud IPs, so the API server (SCRAPE_MODE=agent)
queues scrape jobs and this agent does them from your own connection:

    cd backend
    .venv/Scripts/python -m app.agent            # reads AGENT_API + AGENT_TOKEN from backend/.env

It only makes outbound HTTPS calls to the API (no ports to open), handles one
job at a time, and waits between Amazon requests to stay polite.
"""
import asyncio
import logging
import time

import httpx

from .config import get_settings
from .scrapers import amazon
from .scrapers.common import SourceBlocked
from .services.agent_queue import encode

log = logging.getLogger("tarajuu.agent")
MIN_GAP_SECONDS = 2.0  # between Amazon requests


async def handle(job: dict) -> dict:
    kind, args = job["kind"], job["args"]
    try:
        if kind == "amazon_search":
            return encode(kind, await amazon.search_direct(args["query"], args.get("limit", 12)))
        if kind == "amazon_product":
            return encode(kind, await amazon.product_direct(args["asin"]))
        return {"ok": False, "error": f"unknown job kind {kind}"}
    except SourceBlocked:
        return {"ok": False, "blocked": True}
    except Exception as e:  # noqa: BLE001
        log.exception("job %s failed", job["id"])
        return {"ok": False, "error": repr(e)[:300]}


async def main() -> None:
    s = get_settings()
    if not s.agent_api or not s.agent_token:
        raise SystemExit("Set AGENT_API and AGENT_TOKEN in backend/.env")
    headers = {"Authorization": f"Bearer {s.agent_token}"}
    log.info("agent polling %s", s.agent_api)
    last = 0.0
    async with httpx.AsyncClient(timeout=40) as c:
        while True:
            try:
                r = await c.post(f"{s.agent_api}/agent/claim", headers=headers)
                if r.status_code == 204:
                    continue
                r.raise_for_status()
                job = r.json()
                wait = MIN_GAP_SECONDS - (time.time() - last)
                if wait > 0:
                    await asyncio.sleep(wait)
                started = time.time()
                out = await handle(job)
                last = time.time()
                await c.post(f"{s.agent_api}/agent/jobs/{job['id']}/result", headers=headers, json=out)
                status = "ok" if out["ok"] else ("BLOCKED" if out.get("blocked") else "error")
                log.info("job %s %s %s → %s (%.1fs)", job["id"], job["kind"], job["args"], status, time.time() - started)
            except httpx.HTTPStatusError as e:
                log.error("API answered %s: %s", e.response.status_code, e.response.text[:200])
                await asyncio.sleep(10)
            except Exception as e:  # noqa: BLE001 — network blips: back off and retry
                log.warning("poll failed: %r", e)
                await asyncio.sleep(5)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    asyncio.run(main())
