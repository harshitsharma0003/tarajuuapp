"""Verify Firebase ID tokens (phone OTP + Google sign-in both yield one).

Uses Google's published signing keys directly, so no service-account file is
needed on the server — only FIREBASE_PROJECT_ID.

Keys are fetched over IPv4 with a short timeout (some networks have a broken
IPv6 path that makes the default fetch hang) and cached in memory and on disk,
so a network blip never turns a valid login into "invalid token".
"""
import json
import logging
import time
from pathlib import Path

import httpx
import jwt
from fastapi import HTTPException

from .config import get_settings

log = logging.getLogger(__name__)

_JWKS_URL = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
_CACHE_FILE = Path(__file__).resolve().parent.parent / ".firebase_jwks.json"
_TTL = 3600
_keys: dict[str, object] = {}
_fetched_at = 0.0


def _load(jwks: dict) -> dict[str, object]:
    return {k["kid"]: jwt.PyJWK(k).key for k in jwks.get("keys", []) if k.get("kid")}


def _refresh() -> None:
    global _keys, _fetched_at
    transport = httpx.HTTPTransport(local_address="0.0.0.0", retries=2)  # force IPv4
    with httpx.Client(transport=transport, timeout=10) as c:
        r = c.get(_JWKS_URL)
    r.raise_for_status()
    jwks = r.json()
    _keys, _fetched_at = _load(jwks), time.time()
    try:
        _CACHE_FILE.write_text(json.dumps(jwks))
    except OSError:
        pass


def _key_for(kid: str):
    global _keys
    if not _keys and _CACHE_FILE.exists():
        try:
            _keys = _load(json.loads(_CACHE_FILE.read_text()))
        except (OSError, ValueError, jwt.PyJWTError):
            pass
    if kid not in _keys or time.time() - _fetched_at > _TTL:
        try:
            _refresh()
        except Exception as e:  # noqa: BLE001 — fall back to cached keys
            log.warning("Firebase key refresh failed: %s", e)
    return _keys.get(kid)


def verify_id_token(id_token: str) -> dict:
    project = get_settings().firebase_project_id
    if not project:
        raise HTTPException(503, "Sign-in is not configured on the server (FIREBASE_PROJECT_ID)")
    try:
        kid = jwt.get_unverified_header(id_token).get("kid", "")
    except jwt.PyJWTError as e:
        raise HTTPException(401, f"Invalid Firebase token: {e}")
    key = _key_for(kid)
    if key is None:
        raise HTTPException(503, "Couldn't reach Google to check your login. Please try again in a moment.")
    try:
        claims = jwt.decode(
            id_token, key, algorithms=["RS256"], audience=project,
            issuer=f"https://securetoken.google.com/{project}",
            leeway=120,  # tolerate phone/PC clock drift
        )
    except jwt.PyJWTError as e:
        log.warning("Firebase token rejected: %s", e)
        raise HTTPException(401, f"Invalid Firebase token: {e}")
    if not claims.get("sub"):
        raise HTTPException(401, "Invalid Firebase token: no subject")
    return claims
