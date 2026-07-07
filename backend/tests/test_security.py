import unittest

from app.core.security import hash_password, verify_password


class PasswordHashingTests(unittest.TestCase):
    def test_password_hash_verifies_matching_password(self):
        password_hash = hash_password("correct-password")

        self.assertTrue(verify_password("correct-password", password_hash))
        self.assertFalse(verify_password("wrong-password", password_hash))

    def test_password_hash_supports_long_passwords(self):
        password = "a" * 128
        password_hash = hash_password(password)

        self.assertTrue(verify_password(password, password_hash))
        self.assertFalse(verify_password(password[:-1] + "b", password_hash))


if __name__ == "__main__":
    unittest.main()
