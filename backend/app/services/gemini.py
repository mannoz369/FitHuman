import json

import httpx

from app.core.config import get_settings
from app.schemas import Exercise, UserProfile, WeeklyPlanResponse


def _gemini_schema() -> dict:
    return {
        "type": "OBJECT",
        "properties": {
            "weekly_plan": {
                "type": "ARRAY",
                "items": {
                    "type": "OBJECT",
                    "properties": {
                        "day_name": {"type": "STRING"},
                        "is_rest_day": {"type": "BOOLEAN"},
                        "set_count": {"type": "INTEGER"},
                        "exercises": {
                            "type": "ARRAY",
                            "items": {
                                "type": "OBJECT",
                                "properties": {
                                    "name": {"type": "STRING"},
                                    "category": {"type": "STRING"},
                                    "execution_style": {"type": "STRING"},
                                    "target_reps": {"type": "INTEGER"},
                                    "target_seconds": {"type": "INTEGER"},
                                    "rest_seconds": {"type": "INTEGER"},
                                },
                                "required": [
                                    "name",
                                    "category",
                                    "execution_style",
                                    "target_reps",
                                    "target_seconds",
                                    "rest_seconds",
                                ],
                            },
                        },
                    },
                    "required": ["day_name", "is_rest_day", "set_count", "exercises"],
                },
            }
        },
        "required": ["weekly_plan"],
    }


async def generate_monthly_workout_template(profile: UserProfile) -> WeeklyPlanResponse:
    settings = get_settings()
    prompt_summary = (
        f"Weight: {profile.weight_kg:.0f} kg. "
        f"Height: {profile.height_cm:.0f} cm. "
        f"Goal: {profile.goal}."
    )

    body = {
        "system_instruction": {
            "parts": [
                {
                    "text": (
                        "You are an expert fitness AI generating a personalized 7-day home "
                        "workout template that repeats for a 30-day monthly plan. Output "
                        "strictly valid JSON. Personalize exercise choices, volume, and weekly "
                        "balance for the user's weight, height, and goal. Each non-rest day "
                        "must include set_count between 2 and 4 and 4 to 6 exercises repeated "
                        "as a circuit for that set_count. Cardio = Walking/Running ONLY "
                        "(manual_timed). Rest = 20s. Categories must be 'home_workout' or "
                        "'cardio'. Execution styles must be 'counted', 'timed', or "
                        "'manual_timed'. Counted exercises use target_reps and "
                        "target_seconds = 0. Timed exercises use target_seconds and "
                        "target_reps = 0. target_seconds is always seconds, never minutes. "
                        "For manual_timed cardio, use realistic walking/running durations "
                        "in seconds, for example 10 minutes = 600, 20 minutes = 1200, "
                        "30 minutes = 1800, and 45 minutes = 2700. Never output 10, 20, "
                        "30, or 45 when you mean minutes. Rest days must have set_count = 0 "
                        "and an empty exercises array."
                    )
                }
            ]
        },
        "contents": [
            {
                "role": "user",
                "parts": [{"text": f"Generate a monthly workout template. {prompt_summary}"}],
            }
        ],
        "generationConfig": {
            "response_mime_type": "application/json",
            "responseSchema": _gemini_schema(),
        },
    }

    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{settings.gemini_model}:generateContent?key={settings.gemini_api_key}"
    )

    async with httpx.AsyncClient(timeout=60) as client:
        response = await client.post(url, json=body)
        response.raise_for_status()
        payload = response.json()

    raw_json = payload["candidates"][0]["content"]["parts"][0]["text"].strip()
    if raw_json.startswith("```json"):
        raw_json = raw_json[7:]
    elif raw_json.startswith("```"):
        raw_json = raw_json[3:]

    if raw_json.endswith("```"):
        raw_json = raw_json[:-3]

    return WeeklyPlanResponse.model_validate(json.loads(raw_json.strip()))


def fallback_calorie_estimate(
    profile: UserProfile | None,
    exercises: list[Exercise],
    set_count: int | None,
    duration_seconds: int | None,
) -> int:
    weight_kg = profile.weight_kg if profile is not None else 70
    sets = max(set_count or 1, 1)
    active_seconds = max(duration_seconds or 0, 0)

    cardio_seconds = sum(
        exercise.target_seconds * sets
        for exercise in exercises
        if exercise.category == "cardio" and exercise.execution_style == "manual_timed"
    )
    home_seconds = active_seconds
    if home_seconds == 0:
        home_seconds = sum(
            (
                exercise.target_seconds
                if exercise.execution_style == "timed"
                else 30 if exercise.execution_style == "counted" else 0
            )
            * sets
            for exercise in exercises
            if exercise.category == "home_workout"
        )

    cardio_met = 0.0
    cardio_names = " ".join(exercise.name.lower() for exercise in exercises if exercise.category == "cardio")
    if cardio_seconds > 0:
        cardio_met = 9.0 if "run" in cardio_names or "jog" in cardio_names else 4.0

    home_met = 5.0 if home_seconds > 0 else 0.0
    calories = (
        cardio_met * 3.5 * weight_kg / 200 * (cardio_seconds / 60)
        + home_met * 3.5 * weight_kg / 200 * (home_seconds / 60)
    )
    return max(int(round(calories)), 0)


def _calorie_schema() -> dict:
    return {
        "type": "OBJECT",
        "properties": {
            "calories_burned": {"type": "INTEGER"},
        },
        "required": ["calories_burned"],
    }


async def estimate_calories_burned(
    profile: UserProfile | None,
    day_name: str | None,
    exercises: list[Exercise],
    set_count: int | None,
    duration_seconds: int | None,
) -> tuple[int, str]:
    fallback = fallback_calorie_estimate(profile, exercises, set_count, duration_seconds)
    if not exercises:
        return fallback, "fallback"

    profile_summary = (
        f"Weight: {profile.weight_kg:.0f} kg. Height: {profile.height_cm:.0f} cm. "
        f"Goal: {profile.goal}."
        if profile is not None
        else "No profile was available. Assume 70 kg body weight."
    )
    exercise_payload = [exercise.model_dump() for exercise in exercises]
    body = {
        "system_instruction": {
            "parts": [
                {
                    "text": (
                        "Estimate total active calories burned for one completed workout session. "
                        "Return strictly valid JSON. Use the user's body weight and the completed "
                        "exercise list. For manual_timed cardio, use target_seconds because the app "
                        "cannot measure outdoor/treadmill cardio accurately after Mark as Done. For "
                        "home workout counted/timed exercises, use duration_seconds as the real active "
                        "session duration and the exercise names, reps, set_count, and timed targets "
                        "to pick a reasonable intensity. Return a conservative whole-number estimate."
                    )
                }
            ]
        },
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": json.dumps(
                            {
                                "profile": profile_summary,
                                "day_name": day_name,
                                "set_count": set_count,
                                "duration_seconds": duration_seconds,
                                "exercises": exercise_payload,
                                "fallback_reference_calories": fallback,
                            }
                        )
                    }
                ],
            }
        ],
        "generationConfig": {
            "response_mime_type": "application/json",
            "responseSchema": _calorie_schema(),
        },
    }

    try:
        settings = get_settings()
        url = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"{settings.gemini_model}:generateContent?key={settings.gemini_api_key}"
        )
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(url, json=body)
            response.raise_for_status()
            payload = response.json()

        raw_json = payload["candidates"][0]["content"]["parts"][0]["text"].strip()
        if raw_json.startswith("```json"):
            raw_json = raw_json[7:]
        elif raw_json.startswith("```"):
            raw_json = raw_json[3:]

        if raw_json.endswith("```"):
            raw_json = raw_json[:-3]

        estimated = int(json.loads(raw_json.strip())["calories_burned"])
        return max(estimated, 0), "gemini"
    except Exception:
        return fallback, "fallback"
