"""JWT issue/verify and the FastAPI dependencies that guard routes."""
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import get_settings
from .db import pool

_bearer = HTTPBearer(auto_error=False)


def issue_token(user_id: str) -> str:
    s = get_settings()
    now = datetime.now(timezone.utc)
    payload = {"sub": user_id, "iat": now, "exp": now + timedelta(days=s.jwt_ttl_days)}
    return jwt.encode(payload, s.jwt_secret, algorithm="HS256")


def _decode(token: str) -> str:
    try:
        return jwt.decode(token, get_settings().jwt_secret, algorithms=["HS256"])["sub"]
    except jwt.PyJWTError:
        raise HTTPException(401, "Invalid or expired session")


async def current_user(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> dict:
    if not creds:
        raise HTTPException(401, "Sign in required")
    uid = _decode(creds.credentials)
    row = await pool().fetchrow("SELECT id, phone, name, email FROM users WHERE id = $1", uid)
    if not row:
        raise HTTPException(401, "Account not found")
    return dict(row)


async def optional_user(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> dict | None:
    """Like current_user, but anonymous callers get None instead of a 401."""
    if not creds:
        return None
    try:
        return await current_user(creds)
    except HTTPException:
        return None
