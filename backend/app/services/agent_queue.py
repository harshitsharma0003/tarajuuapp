"""Server side of the scrape agent: queue a job, wait for the agent's result.

The agent (app/agent.py) long-polls POST /api/agent/claim and posts results to
POST /api/agent/jobs/{id}/result. Jobs live in Postgres (scrape_jobs).
"""
import asyncio
import time
from dataclasses import asdict

from ..db import pool
from ..scrapers.common import Listing, SourceBlocked

_last_seen = 0.0


class AgentOffline(Exception):
    """No scrape agent has polled recently, or it didn't answer in time."""


def touch() -> None:
    global _last_seen
    _last_seen = time.time()


def online() -> bool:
    return time.time() - _last_seen < 60


def encode(kind: str, value) -> dict:
    if kind == "amazon_search":
        return {"ok": True, "listings": [asdict(l) for l in value]}
    return {"ok": True, "listing": asdict(value)}


def _decode(kind: str, result: dict):
    if kind == "amazon_search":
        return [Listing(**d) for d in result["listings"]]
    return Listing(**result["listing"])


async def run(kind: str, args: dict, timeout: float = 60):
    if not online():
        raise AgentOffline("scrape agent is offline")
    job_id = await pool().fetchval("INSERT INTO scrape_jobs (kind, args) VALUES ($1, $2) RETURNING id", kind, args)
    deadline = time.time() + timeout
    while time.time() < deadline:
        row = await pool().fetchrow("SELECT status, result FROM scrape_jobs WHERE id=$1", job_id)
        if row["status"] == "done":
            return _decode(kind, row["result"])
        if row["status"] == "error":
            if (row["result"] or {}).get("blocked"):
                raise SourceBlocked("amazon")
            raise RuntimeError((row["result"] or {}).get("error", "agent job failed"))
        await asyncio.sleep(0.4)
    await pool().execute("UPDATE scrape_jobs SET status='expired' WHERE id=$1 AND status IN ('queued','running')", job_id)
    raise AgentOffline("scrape agent did not answer in time")
