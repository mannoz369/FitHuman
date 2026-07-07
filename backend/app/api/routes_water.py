from datetime import timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, Header, Query, Response

from app.api.deps import get_current_user
from app.core.security import utc_now
from app.db.mongo import get_database
from app.schemas import (
    AddWaterRequest,
    UpdateWaterGoalRequest,
    WaterHistoryDayOut,
    WaterHistoryOut,
    WaterLogOut,
)
from app.utils.mongo import day_key

router = APIRouter(prefix="/water", tags=["water"])


def _disable_cache(response: Response) -> None:
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"


def _past_day_keys(timezone_name: str, days: int = 7) -> list[str]:
    try:
        local_timezone = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError:
        local_timezone = timezone.utc

    today = utc_now().astimezone(local_timezone).date()
    return [(today - timedelta(days=offset)).isoformat() for offset in range(days - 1, -1, -1)]


async def _get_or_create_today_log(
    current_user: dict,
    timezone_name: str,
) -> dict:
    db = get_database()
    today = day_key(timezone_name=timezone_name)
    now = utc_now()
    daily_goal_ml = float(current_user.get("water_goal_ml", 2500.0))

    await db.water_logs.update_one(
        {"user_id": current_user["_id"], "day": today},
        {
            "$setOnInsert": {
                "user_id": current_user["_id"],
                "day": today,
                "current_intake_ml": 0.0,
                "daily_goal_ml": daily_goal_ml,
                "created_at": now,
                "last_intake_at": None,
                "updated_at": now,
            },
        },
        upsert=True,
    )
    return await db.water_logs.find_one({"user_id": current_user["_id"], "day": today})


@router.get("/today", response_model=WaterLogOut)
async def get_today_water(
    response: Response,
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> WaterLogOut:
    _disable_cache(response)
    log = await _get_or_create_today_log(current_user, timezone_name)
    return WaterLogOut.model_validate(log)


@router.get("/history", response_model=WaterHistoryOut)
async def get_water_history(
    response: Response,
    days: int = Query(default=7, ge=1, le=30),
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> WaterHistoryOut:
    _disable_cache(response)
    db = get_database()
    day_keys = _past_day_keys(timezone_name, days)
    daily_goal_ml = float(current_user.get("water_goal_ml", 2500.0))

    cursor = db.water_logs.find({"user_id": current_user["_id"], "day": {"$in": day_keys}})
    logs_by_day = {log["day"]: log async for log in cursor}

    history_days: list[WaterHistoryDayOut] = []
    total_intake_ml = 0.0
    logged_day_count = 0

    for key in day_keys:
        log = logs_by_day.get(key)
        if log is None:
            history_days.append(WaterHistoryDayOut(day=key, daily_goal_ml=daily_goal_ml))
            continue

        intake = float(log.get("current_intake_ml", 0.0))
        total_intake_ml += intake
        logged_day_count += 1
        history_days.append(
            WaterHistoryDayOut(
                day=key,
                current_intake_ml=intake,
                daily_goal_ml=float(log.get("daily_goal_ml", daily_goal_ml)),
                last_intake_at=log.get("last_intake_at"),
                updated_at=log.get("updated_at"),
            )
        )

    average_intake_ml = total_intake_ml / logged_day_count if logged_day_count else 0.0
    return WaterHistoryOut(
        days=history_days,
        average_intake_ml=average_intake_ml,
        total_intake_ml=total_intake_ml,
        logged_day_count=logged_day_count,
    )


@router.post("/intake", response_model=WaterLogOut)
async def add_water_intake(
    payload: AddWaterRequest,
    response: Response,
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> WaterLogOut:
    _disable_cache(response)
    db = get_database()
    today = day_key(timezone_name=timezone_name)
    await _get_or_create_today_log(current_user, timezone_name)
    now = utc_now()

    await db.water_logs.update_one(
        {"user_id": current_user["_id"], "day": today},
        {
            "$inc": {"current_intake_ml": payload.amount_ml},
            "$set": {"last_intake_at": now, "updated_at": now},
        },
    )
    updated_log = await db.water_logs.find_one({"user_id": current_user["_id"], "day": today})
    return WaterLogOut.model_validate(updated_log)


@router.patch("/goal", response_model=WaterLogOut)
async def update_water_goal(
    payload: UpdateWaterGoalRequest,
    response: Response,
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> WaterLogOut:
    _disable_cache(response)
    db = get_database()
    today = day_key(timezone_name=timezone_name)
    await _get_or_create_today_log(current_user, timezone_name)
    now = utc_now()

    await db.users.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"water_goal_ml": payload.daily_goal_ml, "updated_at": now}},
    )
    await db.water_logs.update_one(
        {"user_id": current_user["_id"], "day": today},
        {"$set": {"daily_goal_ml": payload.daily_goal_ml, "updated_at": now}},
    )
    updated_log = await db.water_logs.find_one({"user_id": current_user["_id"], "day": today})
    return WaterLogOut.model_validate(updated_log)
