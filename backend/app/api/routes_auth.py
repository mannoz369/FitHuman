from fastapi import APIRouter, HTTPException, status
from pymongo.errors import DuplicateKeyError

from app.core.security import create_access_token, hash_password, utc_now, verify_password
from app.db.mongo import get_database
from app.schemas import AuthResponse, LoginRequest, RegisterRequest, UserOut
from app.utils.mongo import serialize_document

router = APIRouter(prefix="/auth", tags=["auth"])


def user_out(user: dict) -> UserOut:
    return UserOut.model_validate(serialize_document(user))


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest) -> AuthResponse:
    db = get_database()
    now = utc_now()
    user_doc = {
        "email": payload.email.lower(),
        "name": payload.name,
        "password_hash": hash_password(payload.password),
        "profile": None,
        "current_streak": 0,
        "last_workout_completed_on": None,
        "water_goal_ml": 2500.0,
        "created_at": now,
        "updated_at": now,
    }

    try:
        result = await db.users.insert_one(user_doc)
    except DuplicateKeyError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered") from exc

    user_doc["_id"] = result.inserted_id
    return AuthResponse(access_token=create_access_token(str(result.inserted_id)), user=user_out(user_doc))


@router.post("/login", response_model=AuthResponse)
async def login(payload: LoginRequest) -> AuthResponse:
    db = get_database()
    user = await db.users.find_one({"email": payload.email.lower()})

    if user is None or not verify_password(payload.password, user["password_hash"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

    return AuthResponse(access_token=create_access_token(str(user["_id"])), user=user_out(user))
