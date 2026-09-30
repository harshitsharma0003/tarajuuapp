"""POST /api/auth/firebase — exchange a Firebase ID token for a Tarajuu session."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..db import pool
from ..firebase_auth import verify_id_token
from ..security import issue_token

router = APIRouter(prefix="/auth", tags=["auth"])


class FirebaseLogin(BaseModel):
    idToken: str
    # Only sent from the sign-up screen.
    name: str | None = None
    email: str | None = None
    acceptedTerms: bool | None = None


def user_json(row) -> dict:
    return {"id": str(row["id"]), "phone": row["phone"], "name": row["name"], "email": row["email"]}


@router.post("/firebase")
async def firebase_login(body: FirebaseLogin):
    claims = verify_id_token(body.idToken)
    uid = claims["sub"]
    phone = claims.get("phone_number")
    name = (body.name or claims.get("name") or "").strip() or None
    email = (body.email or claims.get("email") or "").strip() or None

    async with pool().acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM users WHERE firebase_uid=$1", uid)
        if not row and phone:
            # Same phone signed in through a different Firebase account before.
            row = await conn.fetchrow("SELECT * FROM users WHERE phone=$1", phone)
        if row:
            row = await conn.fetchrow(
                """UPDATE users SET firebase_uid=$2, phone=COALESCE($3, phone),
                          name=COALESCE($4, name), email=COALESCE($5, email)
                   WHERE id=$1 RETURNING *""",
                row["id"], uid, phone, name, email,
            )
            is_new = False
        else:
            if body.name is not None and not body.acceptedTerms:
                raise HTTPException(400, "Please accept the Terms & Conditions to continue.")
            row = await conn.fetchrow(
                "INSERT INTO users (firebase_uid, phone, name, email) VALUES ($1,$2,$3,$4) RETURNING *",
                uid, phone, name, email,
            )
            is_new = True
    return {"token": issue_token(str(row["id"])), "user": user_json(row), "isNew": is_new}
