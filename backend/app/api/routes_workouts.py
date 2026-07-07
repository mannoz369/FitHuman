from datetime import datetime, timedelta, timezone

from bson import ObjectId
from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException, Query, status

from app.api.deps import get_current_user
from app.core.security import utc_now
from app.db.mongo import get_database
from app.schemas import (
    CompleteWorkoutRequest,
    CompleteWorkoutResponse,
    CurrentWorkoutPlanResponse,
    Exercise,
    UserProfile,
    WeeklyPlanResponse,
    WorkoutCaloriesSummaryOut,
    WorkoutPlanOut,
    WorkoutProgressIn,
    WorkoutProgressOut,
    WorkoutSessionOut,
)
from app.services.gemini import estimate_calories_burned, generate_monthly_workout_template
from app.utils.mongo import day_key, object_id, serialize_document

router = APIRouter(tags=["workouts"])
PLAN_DURATION_DAYS = 30


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.tzinfo.utcoffset(value) is None:
        return value.replace(tzinfo=timezone.utc)

    return value.astimezone(timezone.utc)


def _date_plus_30_days(value: datetime) -> datetime:
    return _as_utc(value) + timedelta(days=PLAN_DURATION_DAYS)


def _days_remaining(ends_at: datetime, timezone_name: str = "UTC") -> int:
    today = datetime.fromisoformat(day_key(timezone_name=timezone_name)).date()
    end_date = datetime.fromisoformat(day_key(_as_utc(ends_at), timezone_name)).date()
    return max((end_date - today).days, 0)


def _today_plan(plan_doc: dict, timezone_name: str = "UTC") -> dict | None:
    today = datetime.fromisoformat(day_key(timezone_name=timezone_name)).date()
    return _plan_for_local_date(plan_doc, today, timezone_name)


def _plan_for_local_date(
    plan_doc: dict,
    local_date,
    timezone_name: str = "UTC",
) -> dict | None:
    weekly_plan = plan_doc.get("weekly_plan") or []
    if not weekly_plan:
        return None

    start_day = datetime.fromisoformat(day_key(_as_utc(plan_doc["starts_at"]), timezone_name)).date()
    elapsed_days = max((local_date - start_day).days, 0)
    return weekly_plan[elapsed_days % len(weekly_plan)]


def _previous_streak_day(
    plan_doc: dict | None,
    completed_local_date,
    timezone_name: str = "UTC",
) -> str:
    previous_day = completed_local_date - timedelta(days=1)
    if plan_doc is None:
        return previous_day.isoformat()

    weekly_plan = plan_doc.get("weekly_plan") or []
    if not weekly_plan:
        return previous_day.isoformat()

    for _ in range(len(weekly_plan)):
        daily_plan = _plan_for_local_date(plan_doc, previous_day, timezone_name)
        if daily_plan is None or not daily_plan.get("is_rest_day", False):
            return previous_day.isoformat()
        previous_day -= timedelta(days=1)

    return (completed_local_date - timedelta(days=1)).isoformat()


def _next_streak_for_completion(
    current_user: dict,
    plan_doc: dict | None,
    completed_on: str,
    timezone_name: str,
) -> int:
    last_completed_on = current_user.get("last_workout_completed_on")
    if last_completed_on == completed_on:
        return current_user.get("current_streak", 0)

    completed_local_date = datetime.fromisoformat(completed_on).date()
    previous_streak_day = _previous_streak_day(plan_doc, completed_local_date, timezone_name)
    current_streak = current_user.get("current_streak", 0)
    return current_streak + 1 if last_completed_on == previous_streak_day else 1


async def _sync_user_streak_for_completion(
    current_user: dict,
    plan_doc: dict | None,
    completed_on: str,
    timezone_name: str,
) -> int:
    db = get_database()
    next_streak = await _streak_ending_on(
        db,
        current_user["_id"],
        plan_doc,
        completed_on,
        timezone_name,
    )
    if next_streak == 0:
        next_streak = _next_streak_for_completion(
            current_user,
            plan_doc,
            completed_on,
            timezone_name,
        )
    if (
        current_user.get("last_workout_completed_on") == completed_on
        and current_user.get("current_streak", 0) == next_streak
    ):
        return next_streak

    await db.users.update_one(
        {"_id": current_user["_id"]},
        {
            "$set": {
                "current_streak": next_streak,
                "last_workout_completed_on": completed_on,
                "updated_at": utc_now(),
            }
        },
    )
    current_user["current_streak"] = next_streak
    current_user["last_workout_completed_on"] = completed_on
    return next_streak


async def _streak_ending_on(
    db,
    user_id: ObjectId,
    plan_doc: dict | None,
    completed_on: str,
    timezone_name: str,
) -> int:
    completed_local_date = datetime.fromisoformat(completed_on).date()
    cursor = (
        db.workout_sessions.find(
            {
                "user_id": user_id,
                "completed_on": {"$lte": completed_on},
            },
            {"completed_on": 1},
        )
        .sort("completed_on", -1)
        .limit(730)
    )
    completed_dates = {session["completed_on"] async for session in cursor}
    if completed_on not in completed_dates:
        return 0

    if completed_dates:
        earliest_completed_date = datetime.fromisoformat(min(completed_dates)).date()
        max_scan_days = max((completed_local_date - earliest_completed_date).days + 8, 8)
    else:
        max_scan_days = 8

    streak = 0
    streak_day = completed_local_date
    for _ in range(max_scan_days):
        daily_plan = _plan_for_local_date(plan_doc, streak_day, timezone_name) if plan_doc else None
        if daily_plan is not None and daily_plan.get("is_rest_day", False):
            streak_day -= timedelta(days=1)
            continue

        if streak_day.isoformat() not in completed_dates:
            break

        streak += 1
        streak_day -= timedelta(days=1)

    return streak


def _plan_out(plan_doc: dict | None, timezone_name: str = "UTC") -> WorkoutPlanOut | None:
    if plan_doc is None:
        return None

    serialized = serialize_document(plan_doc)
    serialized["starts_at"] = _as_utc(plan_doc["starts_at"])
    serialized["ends_at"] = _as_utc(plan_doc["ends_at"])
    serialized["days_remaining"] = _days_remaining(plan_doc["ends_at"], timezone_name)
    serialized["today_plan"] = _today_plan(plan_doc, timezone_name)
    return WorkoutPlanOut.model_validate(serialized)


def _session_out(session_doc: dict) -> WorkoutSessionOut:
    serialized = serialize_document(session_doc)
    serialized["completed_at"] = _as_utc(session_doc["completed_at"])
    return WorkoutSessionOut.model_validate(serialized)


def _session_plan_snapshot(
    plan_doc: dict | None,
    day_name: str | None,
    timezone_name: str,
) -> tuple[list[dict], int | None]:
    if plan_doc is None:
        return [], None

    daily_plan = None
    if day_name is not None:
        daily_plan = next(
            (day for day in plan_doc.get("weekly_plan", []) if day.get("day_name") == day_name),
            None,
        )

    daily_plan = daily_plan or _today_plan(plan_doc, timezone_name)
    if daily_plan is None:
        return [], None

    return daily_plan.get("exercises", []), daily_plan.get("set_count")


async def _active_plan_for_user(user_id: ObjectId) -> dict | None:
    db = get_database()
    return await db.workout_plans.find_one(
        {"user_id": user_id, "is_active": True},
        sort=[("created_at", -1)],
    )


async def _estimate_and_store_session_calories(
    session_id: ObjectId,
    profile_snapshot: dict | None,
    day_name: str | None,
    exercise_docs: list[dict],
    set_count: int | None,
    duration_seconds: int | None,
) -> None:
    profile = UserProfile.model_validate(profile_snapshot) if profile_snapshot is not None else None
    exercises = [Exercise.model_validate(exercise) for exercise in exercise_docs]
    calories_burned, calorie_estimate_source = await estimate_calories_burned(
        profile,
        day_name,
        exercises,
        set_count,
        duration_seconds,
    )

    db = get_database()
    await db.workout_sessions.update_one(
        {"_id": session_id},
        {
            "$set": {
                "calories_burned": calories_burned,
                "calorie_estimate_source": calorie_estimate_source,
                "updated_at": utc_now(),
            }
        },
    )


async def _mark_workout_progress_complete(
    user_id: ObjectId,
    plan_id: ObjectId,
    progress_day: str,
    completed_at: datetime,
) -> None:
    db = get_database()
    await db.workout_progress.update_one(
        {"user_id": user_id, "plan_id": plan_id, "day": progress_day},
        {
            "$set": {
                "day": progress_day,
                "current_exercise_index": 0,
                "is_workout_complete": True,
                "updated_at": completed_at,
            }
        },
        upsert=True,
    )


async def _today_progress_for_plan(
    user_id: ObjectId,
    plan_id: ObjectId,
    timezone_name: str,
) -> WorkoutProgressOut | None:
    db = get_database()
    progress_day = day_key(timezone_name=timezone_name)
    plan_id_string = str(plan_id)

    completed_session = await db.workout_sessions.find_one(
        {
            "user_id": user_id,
            "plan_id": plan_id,
            "completed_on": progress_day,
        }
    )
    if completed_session is not None:
        return WorkoutProgressOut(
            plan_id=plan_id_string,
            current_exercise_index=0,
            is_workout_complete=True,
            updated_at=completed_session.get("completed_at", utc_now()),
        )

    progress = await db.workout_progress.find_one(
        {"user_id": user_id, "plan_id": plan_id, "day": progress_day}
    )
    if progress is None:
        return None

    serialized = serialize_document(progress)
    serialized["plan_id"] = plan_id_string
    return WorkoutProgressOut.model_validate(serialized)


async def _store_new_plan(user_id: ObjectId, profile: UserProfile, plan: WeeklyPlanResponse) -> dict:
    db = get_database()
    now = utc_now()

    await db.workout_plans.update_many(
        {"user_id": user_id, "is_active": True},
        {"$set": {"is_active": False, "updated_at": now}},
    )

    plan_doc = {
        "user_id": user_id,
        "weekly_plan": [day.model_dump() for day in plan.weekly_plan],
        "profile_snapshot": profile.model_dump(),
        "starts_at": now,
        "ends_at": _date_plus_30_days(now),
        "is_active": True,
        "source": "gemini",
        "created_at": now,
        "updated_at": now,
    }
    result = await db.workout_plans.insert_one(plan_doc)
    plan_doc["_id"] = result.inserted_id
    return plan_doc


@router.post("/onboarding/complete", response_model=WorkoutPlanOut, status_code=status.HTTP_201_CREATED)
@router.post("/workout-plans/generate", response_model=WorkoutPlanOut, status_code=status.HTTP_201_CREATED)
async def generate_workout_plan(
    profile: UserProfile,
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> WorkoutPlanOut:
    db = get_database()
    plan = await generate_monthly_workout_template(profile)

    await db.users.update_one(
        {"_id": current_user["_id"]},
        {"$set": {"profile": profile.model_dump(), "updated_at": utc_now()}},
    )
    plan_doc = await _store_new_plan(current_user["_id"], profile, plan)
    return _plan_out(plan_doc, timezone_name)


@router.get("/workout-plans/current", response_model=CurrentWorkoutPlanResponse)
async def get_current_workout_plan(
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> CurrentWorkoutPlanResponse:
    plan_doc = await _active_plan_for_user(current_user["_id"])
    if plan_doc is None:
        return CurrentWorkoutPlanResponse(
            plan=None,
            needs_new_plan=True,
            current_streak=current_user.get("current_streak", 0),
        )

    today_progress = await _today_progress_for_plan(
        current_user["_id"],
        plan_doc["_id"],
        timezone_name,
    )
    today_is_workout_complete = today_progress.is_workout_complete if today_progress else False
    current_streak = current_user.get("current_streak", 0)
    if today_is_workout_complete:
        current_streak = await _sync_user_streak_for_completion(
            current_user,
            plan_doc,
            day_key(timezone_name=timezone_name),
            timezone_name,
        )

    return CurrentWorkoutPlanResponse(
        plan=_plan_out(plan_doc, timezone_name),
        needs_new_plan=utc_now() >= _as_utc(plan_doc["ends_at"]),
        today_progress=today_progress,
        today_is_workout_complete=today_is_workout_complete,
        current_streak=current_streak,
    )


@router.post("/workout-plans/current/continue", response_model=WorkoutPlanOut)
async def continue_current_workout_plan(
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> WorkoutPlanOut:
    db = get_database()
    plan_doc = await _active_plan_for_user(current_user["_id"])
    if plan_doc is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No active workout plan")

    now = utc_now()
    await db.workout_plans.update_one(
        {"_id": plan_doc["_id"]},
        {
            "$set": {
                "starts_at": now,
                "ends_at": _date_plus_30_days(now),
                "updated_at": now,
            }
        },
    )
    updated_plan = await db.workout_plans.find_one({"_id": plan_doc["_id"]})
    return _plan_out(updated_plan, timezone_name)


@router.get("/workouts/progress", response_model=WorkoutProgressOut | None)
async def get_workout_progress(
    plan_id: str | None = Query(default=None),
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> WorkoutProgressOut | None:
    db = get_database()
    active_plan = await _active_plan_for_user(current_user["_id"]) if plan_id is None else None
    resolved_plan_id = plan_id or (str(active_plan["_id"]) if active_plan else None)

    if resolved_plan_id is None:
        return None

    try:
        plan_object_id = object_id(resolved_plan_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid plan_id") from exc

    return await _today_progress_for_plan(current_user["_id"], plan_object_id, timezone_name)


@router.put("/workouts/progress", response_model=WorkoutProgressOut)
async def save_workout_progress(
    payload: WorkoutProgressIn,
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> WorkoutProgressOut:
    db = get_database()
    try:
        plan_object_id = object_id(payload.plan_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid plan_id") from exc

    plan = await db.workout_plans.find_one({"_id": plan_object_id, "user_id": current_user["_id"]})
    if plan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Workout plan not found")

    now = utc_now()
    progress_day = day_key(timezone_name=timezone_name)
    await db.workout_progress.update_one(
        {"user_id": current_user["_id"], "plan_id": plan_object_id, "day": progress_day},
        {
            "$set": {
                "day": progress_day,
                "current_exercise_index": payload.current_exercise_index,
                "is_workout_complete": payload.is_workout_complete,
                "updated_at": now,
            }
        },
        upsert=True,
    )

    return WorkoutProgressOut(
        plan_id=payload.plan_id,
        current_exercise_index=payload.current_exercise_index,
        is_workout_complete=payload.is_workout_complete,
        updated_at=now,
    )


@router.get("/workouts/sessions", response_model=WorkoutCaloriesSummaryOut)
async def list_workout_sessions(
    limit: int = Query(default=90, ge=1, le=365),
    current_user: dict = Depends(get_current_user),
) -> WorkoutCaloriesSummaryOut:
    db = get_database()
    cursor = (
        db.workout_sessions.find({"user_id": current_user["_id"]})
        .sort("completed_on", -1)
        .limit(limit)
    )
    sessions = [_session_out(session) async for session in cursor]
    stats_cursor = db.workout_sessions.aggregate(
        [
            {
                "$match": {
                    "user_id": current_user["_id"],
                    "calories_burned": {"$ne": None},
                }
            },
            {
                "$group": {
                    "_id": None,
                    "total": {"$sum": "$calories_burned"},
                    "average": {"$avg": "$calories_burned"},
                }
            },
        ]
    )
    stats = await stats_cursor.to_list(length=1)
    total = int(stats[0]["total"]) if stats else 0
    average = float(stats[0]["average"]) if stats else 0
    workout_count = await db.workout_sessions.count_documents({"user_id": current_user["_id"]})

    return WorkoutCaloriesSummaryOut(
        sessions=sessions,
        average_calories_burned=round(average, 1),
        total_calories_burned=total,
        workout_count=workout_count,
    )


@router.post("/workouts/complete", response_model=CompleteWorkoutResponse)
async def complete_workout(
    payload: CompleteWorkoutRequest,
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_user),
    timezone_name: str = Header(default="UTC", alias="X-Time-Zone"),
) -> CompleteWorkoutResponse:
    db = get_database()
    completed_at = _as_utc(payload.completed_at or utc_now())
    completed_on = day_key(completed_at, timezone_name)

    plan_object_id = None
    plan_doc = None
    if payload.plan_id is not None:
        try:
            plan_object_id = object_id(payload.plan_id)
        except ValueError as exc:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid plan_id") from exc
        plan_doc = await db.workout_plans.find_one(
            {"_id": plan_object_id, "user_id": current_user["_id"]}
        )
        if plan_doc is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Workout plan not found")
    else:
        plan_doc = await _active_plan_for_user(current_user["_id"])
        plan_object_id = plan_doc["_id"] if plan_doc is not None else None

    existing = await db.workout_sessions.find_one(
        {"user_id": current_user["_id"], "completed_on": completed_on}
    )
    if existing is not None:
        if plan_object_id is not None:
            await _mark_workout_progress_complete(
                current_user["_id"],
                plan_object_id,
                completed_on,
                completed_at,
            )
        current_streak = await _sync_user_streak_for_completion(
            current_user,
            plan_doc,
            completed_on,
            timezone_name,
        )
        if existing.get("calories_burned") is None:
            background_tasks.add_task(
                _estimate_and_store_session_calories,
                existing["_id"],
                plan_doc.get("profile_snapshot") if plan_doc is not None else None,
                existing.get("day_name"),
                existing.get("exercises", []),
                existing.get("set_count"),
                existing.get("duration_seconds"),
            )
        return CompleteWorkoutResponse(
            completed_on=completed_on,
            current_streak=current_streak,
            already_completed=True,
            duration_seconds=existing.get("duration_seconds"),
            calories_burned=existing.get("calories_burned"),
        )

    next_streak = _next_streak_for_completion(
        current_user,
        plan_doc,
        completed_on,
        timezone_name,
    )
    snapshot_exercises = [exercise.model_dump() for exercise in payload.exercises]
    snapshot_set_count = payload.set_count
    if not snapshot_exercises:
        snapshot_exercises, snapshot_set_count = _session_plan_snapshot(
            plan_doc,
            payload.day_name,
            timezone_name,
        )

    profile_snapshot = plan_doc.get("profile_snapshot") if plan_doc is not None else None
    session_result = await db.workout_sessions.insert_one(
        {
            "user_id": current_user["_id"],
            "plan_id": plan_object_id,
            "day_name": payload.day_name,
            "duration_seconds": payload.duration_seconds,
            "calories_burned": None,
            "calorie_estimate_source": "pending",
            "set_count": snapshot_set_count,
            "exercises": snapshot_exercises,
            "completed_at": completed_at,
            "completed_on": completed_on,
            "created_at": utc_now(),
        }
    )
    await db.users.update_one(
        {"_id": current_user["_id"]},
        {
            "$set": {
                "current_streak": next_streak,
                "last_workout_completed_on": completed_on,
                "updated_at": utc_now(),
            }
        },
    )
    if plan_object_id is not None:
        await _mark_workout_progress_complete(
            current_user["_id"],
            plan_object_id,
            completed_on,
            completed_at,
        )
    background_tasks.add_task(
        _estimate_and_store_session_calories,
        session_result.inserted_id,
        profile_snapshot,
        payload.day_name,
        snapshot_exercises,
        snapshot_set_count,
        payload.duration_seconds,
    )

    return CompleteWorkoutResponse(
        completed_on=completed_on,
        current_streak=next_streak,
        already_completed=False,
        duration_seconds=payload.duration_seconds,
        calories_burned=None,
    )
