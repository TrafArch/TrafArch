"""Offline publisher integration tests; supply the user-provided APK explicitly.

PowerShell: $env:TRAFARCH_SUICA_SOURCE_APK='C:\\path\\source.apk'
python -X utf8 -m unittest discover -s dev/suica -p 'test_*.py' -v
"""

from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).with_name("publish_suica.py")
DATABASE_HASH = "57d4fe1af5154e9adab0a4a38619fe8095c7f509ac28c743bf554ba199a43abd"
APK_HASH = "5b407a0456f7cf4592ce2964511c642fc6352b04d6a0cc23e855a268df14a132"


@unittest.skipUnless(os.environ.get("TRAFARCH_SUICA_SOURCE_APK"), "set TRAFARCH_SUICA_SOURCE_APK to the supplied APK")
class PublishSuicaTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="trafarch-suica-test-")
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name) / "published"
        self.apk = Path(os.environ["TRAFARCH_SUICA_SOURCE_APK"])

    def run_cli(self, *extra, source=None):
        return subprocess.run(
            [sys.executable, "-X", "utf8", str(SCRIPT), "--source-apk", str(source or self.apk), "--output-dir", str(self.output), *extra],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )

    def publish(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return self.output / "suica_stationcode.db"

    def test_publishes_original_bytes_and_all_original_records(self):
        before = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        target = self.publish()
        with zipfile.ZipFile(self.apk) as source:
            self.assertEqual(target.read_bytes(), source.read("assets/suica_stationcode.db"))
        self.assertEqual(hashlib.sha256(target.read_bytes()).hexdigest(), DATABASE_HASH)
        with closing(sqlite3.connect(target.as_uri() + "?mode=ro", uri=True)) as database:
            self.assertEqual(database.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
            self.assertEqual(database.execute("SELECT COUNT(*) FROM stationcode").fetchone(), (6435,))
            self.assertEqual(database.execute("SELECT companyname,linename,stationname FROM stationcode WHERE areacode=0 AND linecode=1 AND stationorder=1").fetchall(), [("JR東日本", "東海道本", "東京")])
        manifest = json.loads((self.output / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["source"]["apk_sha256"], APK_HASH)
        self.assertEqual(manifest["source"]["entry"], "assets/suica_stationcode.db")
        self.assertEqual(manifest["database"]["tables"], {"android_metadata": 0, "stationcode": 6435})
        self.assertEqual(hashlib.sha256(self.apk.read_bytes()).hexdigest(), before)

    def test_repeat_publication_and_verify_are_reproducible(self):
        self.publish()
        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.output.iterdir()}
        verified = self.run_cli("--verify")
        self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)
        self.assertEqual({p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.output.iterdir()}, before)
        self.publish()
        self.assertEqual({p.name: p.read_bytes() for p in self.output.iterdir()}, {name: entry[0] for name, entry in before.items()})

    def test_verify_rejects_changed_database_without_repairing_it(self):
        target = self.publish()
        altered = target.read_bytes() + b"changed"
        target.write_bytes(altered)
        result = self.run_cli("--verify")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("published database differs", result.stderr)
        self.assertEqual(target.read_bytes(), altered)

    def test_verify_rejects_changed_manifest_without_repairing_it(self):
        self.publish()
        target = self.output / "manifest.json"
        target.write_text("{}", encoding="utf-8")
        result = self.run_cli("--verify")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("published manifest differs", result.stderr)
        self.assertEqual(target.read_text(encoding="utf-8"), "{}")

    def test_rejects_a_different_apk_before_creating_output(self):
        other = Path(self.temporary.name) / "other.apk"
        with zipfile.ZipFile(other, "w") as output:
            output.writestr("assets/suica_stationcode.db", b"not the supplied database")
        result = self.run_cli(source=other)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source APK SHA256 mismatch", result.stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
