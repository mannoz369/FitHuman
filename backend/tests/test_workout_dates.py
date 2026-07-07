import unittest
from datetime import date, datetime, timezone
from unittest.mock import patch

from app.api.routes_workouts import (
    _as_utc,
    _days_remaining,
    _next_streak_for_completion,
    _previous_streak_day,
    _today_plan,
)
from app.core.security import utc_now


class WorkoutDateTests(unittest.TestCase):
    def test_naive_datetimes_are_treated_as_utc(self):
        naive = datetime(2026, 7, 2, 12, 30, 0)

        normalized = _as_utc(naive)

        self.assertEqual(normalized.tzinfo, timezone.utc)
        self.assertEqual(normalized.hour, 12)

    def test_days_remaining_accepts_naive_mongo_datetime(self):
        naive_future = utc_now().replace(tzinfo=None)

        self.assertGreaterEqual(_days_remaining(naive_future), 0)

    def test_today_plan_uses_user_timezone(self):
        plan_doc = {
            "starts_at": datetime(2026, 7, 2, 23, 30, tzinfo=timezone.utc),
            "weekly_plan": [
                {"day_name": "Day 1"},
                {"day_name": "Day 2"},
            ],
        }

        with patch("app.utils.mongo.utc_now") as mock_utc_now:
            mock_utc_now.return_value = datetime(2026, 7, 3, 0, 30, tzinfo=timezone.utc)

            self.assertEqual(_today_plan(plan_doc, "UTC")["day_name"], "Day 2")
            self.assertEqual(_today_plan(plan_doc, "Asia/Kolkata")["day_name"], "Day 1")

    def test_previous_streak_day_skips_planned_rest_days(self):
        plan_doc = {
            "starts_at": datetime(2026, 7, 6, 0, 0, tzinfo=timezone.utc),
            "weekly_plan": [
                {"day_name": "Workout", "is_rest_day": False},
                {"day_name": "Rest", "is_rest_day": True},
                {"day_name": "Cardio", "is_rest_day": False},
            ],
        }

        previous = _previous_streak_day(plan_doc, date(2026, 7, 8), "UTC")

        self.assertEqual(previous, "2026-07-06")

    def test_previous_streak_day_uses_yesterday_without_plan(self):
        previous = _previous_streak_day(None, date(2026, 7, 8), "UTC")

        self.assertEqual(previous, "2026-07-07")

    def test_next_streak_repairs_retry_after_session_already_exists(self):
        user = {"current_streak": 1, "last_workout_completed_on": "2026-07-06"}
        plan_doc = {
            "starts_at": datetime(2026, 7, 6, 0, 0, tzinfo=timezone.utc),
            "weekly_plan": [
                {"day_name": "Workout", "is_rest_day": False},
                {"day_name": "Rest", "is_rest_day": True},
                {"day_name": "Cardio", "is_rest_day": False},
            ],
        }

        next_streak = _next_streak_for_completion(user, plan_doc, "2026-07-08", "UTC")

        self.assertEqual(next_streak, 2)

    def test_next_streak_does_not_increment_same_completion_twice(self):
        user = {"current_streak": 2, "last_workout_completed_on": "2026-07-08"}

        next_streak = _next_streak_for_completion(user, None, "2026-07-08", "UTC")

        self.assertEqual(next_streak, 2)


if __name__ == "__main__":
    unittest.main()
