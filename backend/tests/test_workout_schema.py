import unittest

from app.schemas import Exercise
from app.services.gemini import fallback_calorie_estimate


class WorkoutSchemaTests(unittest.TestCase):
    def test_manual_cardio_small_duration_is_normalized_from_minutes_to_seconds(self):
        exercise = Exercise(
            name="Brisk Walking / Light Jogging",
            category="cardio",
            execution_style="manual_timed",
            target_reps=0,
            target_seconds=30,
            rest_seconds=20,
        )

        self.assertEqual(exercise.target_seconds, 1800)

    def test_timed_home_workout_keeps_seconds(self):
        exercise = Exercise(
            name="Plank",
            category="home_workout",
            execution_style="timed",
            target_reps=0,
            target_seconds=30,
            rest_seconds=20,
        )

        self.assertEqual(exercise.target_seconds, 30)

    def test_manual_cardio_seconds_are_not_double_converted(self):
        exercise = Exercise(
            name="Brisk Walking / Light Jogging",
            category="cardio",
            execution_style="manual_timed",
            target_reps=0,
            target_seconds=1800,
            rest_seconds=20,
        )

        self.assertEqual(exercise.target_seconds, 1800)

    def test_fallback_calorie_estimate_uses_manual_cardio_target_seconds(self):
        exercise = Exercise(
            name="Brisk Walking",
            category="cardio",
            execution_style="manual_timed",
            target_reps=0,
            target_seconds=1800,
            rest_seconds=20,
        )

        self.assertGreater(fallback_calorie_estimate(None, [exercise], 1, 0), 0)


if __name__ == "__main__":
    unittest.main()
