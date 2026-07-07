import unittest
from datetime import datetime, timezone

from app.schemas import WaterLogOut


class WaterSchemaTests(unittest.TestCase):
    def test_water_log_allows_missing_last_intake_timestamp(self):
        log = WaterLogOut(
            day="2026-07-04",
            current_intake_ml=0,
            daily_goal_ml=2500,
            updated_at=datetime(2026, 7, 4, tzinfo=timezone.utc),
        )

        self.assertIsNone(log.last_intake_at)

    def test_water_log_accepts_last_intake_timestamp(self):
        intake_at = datetime(2026, 7, 4, 6, 30, tzinfo=timezone.utc)

        log = WaterLogOut(
            day="2026-07-04",
            current_intake_ml=250,
            daily_goal_ml=2500,
            last_intake_at=intake_at,
            updated_at=intake_at,
        )

        self.assertEqual(log.last_intake_at, intake_at)


if __name__ == "__main__":
    unittest.main()
