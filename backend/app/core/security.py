import hashlib
from datetime import datetime, timedelta, timezone

import bcrypt
from jose import JWTError, jwt

from app.core.config import get_settings

PASSWORD_HASH_PREFIX = "bcrypt_sha256$"


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _password_digest(password: str) -> bytes:
    return hashlib.sha256(password.encode("utf-8")).digest()


def hash_password(password: str) -> str:
    password_hash = bcrypt.hashpw(_password_digest(password), bcrypt.gensalt())
    return f"{PASSWORD_HASH_PREFIX}{password_hash.decode('ascii')}"


def verify_password(password: str, password_hash: str) -> bool:
    if password_hash.startswith(PASSWORD_HASH_PREFIX):
        stored_hash = password_hash.removeprefix(PASSWORD_HASH_PREFIX).encode("ascii")
        return bcrypt.checkpw(_password_digest(password), stored_hash)

    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("ascii"))
    except ValueError:
        return False


def create_access_token(subject: str) -> str:
    settings = get_settings()
    expires_at = utc_now() + timedelta(minutes=settings.jwt_access_token_minutes)
    payload = {"sub": subject, "exp": expires_at}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> str | None:
    settings = get_settings()

    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError:
        return None

    subject = payload.get("sub")
    return subject if isinstance(subject, str) else None
