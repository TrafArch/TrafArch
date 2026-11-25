import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from reserve_version import COUNTER, reserve


class ReservationTest(unittest.TestCase):
    def test_consecutive_clicks_and_newer_source(self):
        metadata = {}

        def exchange(data=None):
            if data is not None:
                for row in data["annotations"]:
                    metadata[row["key"]] = row["value"]
            return [{"key": k, "value": v} for k, v in metadata.items()]

        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory, "pubspec.yaml")
            for source, expected in [(2245, 2245), (2245, 2246), (2249, 2249)]:
                pubspec.write_bytes(f"name: test\nversion: 2.0.0-beta2+{source}\n".encode())
                self.assertEqual(reserve(pubspec, exchange), expected)
                self.assertIn(f"2.0.0-beta2+{expected}", pubspec.read_text())
                self.assertEqual(metadata[COUNTER], str(expected))

    def test_bad_state_or_failed_write_leaves_pubspec_intact(self):
        cases = [
            Mock(return_value=[{"key": COUNTER, "value": "oops"}]),
            Mock(return_value=[{"key": COUNTER, "value": "2100000000"}]),
            Mock(side_effect=[[], OSError("unavailable")]),
        ]
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory, "pubspec.yaml")
            initial = b"version: 2.0.0-beta2+2245\n"
            for exchange in cases:
                pubspec.write_bytes(initial)
                with self.assertRaises((OSError, ValueError)):
                    reserve(pubspec, exchange)
                self.assertEqual(pubspec.read_bytes(), initial)
