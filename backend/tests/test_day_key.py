import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from app.api.routes_water import _past_day_keys
from app.utils.mongo import day_key


class DayKeyTests(unittest.TestCase):
    def test_day_key_uses_supplied_timezone(self):
        value = datetime(2026, 7, 2, 20, 0, tzinfo=timezone.utc)

        self.assertEqual(day_key(value), "2026-07-02")
        self.assertEqual(day_key(value, timezone_name="Asia/Kolkata"), "2026-07-03")

    def test_day_key_falls_back_to_utc_for_unknown_timezone(self):
        value = datetime(2026, 7, 2, 20, 0, tzinfo=timezone.utc)

        self.assertEqual(day_key(value, timezone_name="Not/A_Timezone"), "2026-07-02")

    def test_past_day_keys_use_supplied_timezone(self):
        with patch("app.api.routes_water.utc_now") as mock_utc_now:
            mock_utc_now.return_value = datetime(2026, 7, 2, 20, 0, tzinfo=timezone.utc)

            self.assertEqual(
                _past_day_keys("Asia/Kolkata", days=3),
                ["2026-07-01", "2026-07-02", "2026-07-03"],
            )


if __name__ == "__main__":
    unittest.main()
