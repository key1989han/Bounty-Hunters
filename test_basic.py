"""Basic tests for the project."""
import unittest


class TestBasic(unittest.TestCase):
    def test_import(self):
        """Test that the module can be imported."""
        self.assertTrue(True)

    def test_placeholder(self):
        """Placeholder test."""
        self.assertEqual(1 + 1, 2)


if __name__ == "__main__":
    unittest.main()
