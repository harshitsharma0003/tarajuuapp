"""Verify Firebase ID tokens (phone OTP + Google sign-in both yield one).

Uses Google's published signing keys directly, so no service-account file is
needed on the server — only FIREBASE_PROJECT_ID.
"""
import jwt
from fastapi import HTTPException

from .config import get_settings

_JWKS_URL = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
_jwks = jwt.PyJWKClient(_JWKS_URL, cache_keys=True, lifespan=3600)


def verify_id_token(id_token: str) -> dict:
    project = get_settings().firebase_project_id
    if not project:
        raise HTTPException(503, "Sign-in is not configured on the server (FIREBASE_PROJECT_ID)")
    try:
        key = _jwks.get_signing_key_from_jwt(id_token).key
        claims = jwt.decode(
            id_token, key, algorithms=["RS256"], audience=project,
            issuer=f"https://securetoken.google.com/{project}",
        )
    except jwt.PyJWTError as e:
        raise HTTPException(401, f"Invalid Firebase token: {e}")
    if not claims.get("sub"):
        raise HTTPException(401, "Invalid Firebase token: no subject")
    return claims
