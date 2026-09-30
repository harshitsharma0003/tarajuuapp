"""Tarajuu API — FastAPI app. Run: uvicorn app.main:app --port 8000"""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import db
from .config import get_settings
from .routers import agent, auth, me, products, rides
from .services import agent_queue

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(_: FastAPI):
    await db.connect()
    yield
    await db.disconnect()


app = FastAPI(title="Tarajuu API", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in get_settings().cors_origins.split(",")],
    allow_methods=["*"],
    allow_headers=["*"],
)

for r in (agent.router, auth.router, me.router, products.router, rides.router):
    app.include_router(r, prefix="/api")


@app.get("/api/health")
async def health():
    s = get_settings()
    await db.pool().fetchval("SELECT 1")
    return {
        "ok": True,
        "db": "ok",
        "amazon": s.amazon_enabled,
        "scraper": s.scrape_mode if s.scrape_mode != "agent" else ("agent-online" if agent_queue.online() else "agent-offline"),
        "flipkart": s.flipkart_enabled,
        "uber": s.uber_enabled,
        "firebase": bool(s.firebase_project_id),
    }
