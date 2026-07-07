from fastapi import APIRouter, Depends

from app.api.deps import get_current_user
from app.core.security import utc_now
from app.db.mongo import get_database
from app.schemas import UserOut, UserProfile
from app.utils.mongo import serialize_document

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserOut)
async def get_me(current_user: dict = Depends(get_current_user)) -> UserOut:
    return UserOut.model_validate(serialize_document(current_user))


@router.patch("/me/profile", response_model=UserOut)
async def update_profile(
    profile: UserProfile,
    current_user: dict = Depends(get_current_user),
) -> UserOut:
    db = get_database()
    await db.users.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"profile": profile.model_dump(), "updated_at": utc_now()}},
    )
    updated_user = await db.users.find_one({"_id": current_user["_id"]})
    return UserOut.model_validate(serialize_document(updated_user))
