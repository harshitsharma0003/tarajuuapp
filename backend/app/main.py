"""Tarajuu API — FastAPI app. Run: uvicorn app.main:app --port 8000"""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from . import db
from .config import get_settings
from .routers import auth, me, products, rides

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

for r in (auth.router, me.router, products.router, rides.router):
    app.include_router(r, prefix="/api")


@app.get("/api/health")
async def health():
    s = get_settings()
    await db.pool().fetchval("SELECT 1")
    return {
        "ok": True,
        "db": "ok",
        "amazon": s.amazon_enabled,
        "flipkart": s.flipkart_enabled,
        "uber": s.uber_enabled,
        "firebase": bool(s.firebase_project_id),
    }
