"""Endpoints the local scrape agent talks to (Bearer AGENT_TOKEN)."""
import asyncio
import secrets

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

from ..config import get_settings
from ..db import pool
from ..services import agent_queue

router = APIRouter(prefix="/agent", tags=["agent"])
_bearer = HTTPBearer(auto_error=False)


def agent_auth(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> None:
    token = get_settings().agent_token
    if not token or not creds or not secrets.compare_digest(creds.credentials, token):
        raise HTTPException(401, "Invalid agent token")


class JobResult(BaseModel):
    ok: bool
    listings: list[dict] | None = None
    listing: dict | None = None
    blocked: bool = False
    error: str | None = None


@router.post("/claim", dependencies=[Depends(agent_auth)])
async def claim():
    """Long-poll (≤25s) for the next job. 204 = nothing to do, poll again."""
    await pool().execute("DELETE FROM scrape_jobs WHERE created_at < now() - interval '1 day'")
    for _ in range(50):
        agent_queue.touch()
        row = await pool().fetchrow(
            """UPDATE scrape_jobs SET status='running', claimed_at=now()
               WHERE id = (SELECT id FROM scrape_jobs WHERE status='queued'
                           ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
               RETURNING id, kind, args"""
        )
        if row:
            return {"id": row["id"], "kind": row["kind"], "args": row["args"]}
        await asyncio.sleep(0.5)
    return Response(status_code=204)


@router.post("/jobs/{job_id}/result", dependencies=[Depends(agent_auth)])
async def result(job_id: int, body: JobResult):
    agent_queue.touch()
    await pool().execute(
        "UPDATE scrape_jobs SET status=$2, result=$3, finished_at=now() WHERE id=$1 AND status='running'",
        job_id, "done" if body.ok else "error", body.model_dump(exclude_none=True),
    )
    return {"ok": True}
