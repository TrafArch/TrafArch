"""CU revision tests against a temporary baseline; never edits runtime assets."""
from contextlib import closing
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import publish_city_database as common
import publish_jinan_cu as publisher


class JinanPublisherTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.baseline = self.root / 'baseline'
        self.assets = self.root / 'assets'
        self.baseline.mkdir()
        self.assets.mkdir()
        published = Path(__file__).resolve().parents[2] / 'assets/data'
        manifest = json.loads((published / 'reference_manifest.json').read_text(encoding='utf-8'))
        for filename in common.FILES.values():
            shutil.copyfile(published / filename, self.baseline / filename)
        # Build a temporary pre-import fixture from the shipped schema. Remove
        # only this revision so retained Line 4 IDs and names remain the oracle.
        path = self.baseline / common.FILES['CU']
        with closing(sqlite3.connect(path)) as db:
            source = publisher.REVISIONS['lines238'][0]
            ids = [r[0] for r in db.execute('SELECT station_id FROM ' + common.quote(publisher.TABLE) + ' WHERE source_field=?', (source,))]
            for identity in ids:
                db.execute("DELETE FROM terminal_index WHERE region_code='2500' AND station_id=?", (identity,))
                db.execute('DELETE FROM ' + common.quote(publisher.TABLE) + ' WHERE station_id=?', (identity,))
                db.execute("DELETE FROM station_registry WHERE region_code='2500' AND station_id=?", (identity,))
            db.execute("UPDATE regions SET record_count=33 WHERE region_code='2500'")
            db.commit()
        with common.readonly(path) as db:
            manifest['packages']['CU'].update(
                sha256=common.digest(path.read_bytes()), bytes=path.stat().st_size,
                tables=common.counts(db))
            self.line4 = common.table_rows(db, publisher.TABLE)
        (self.baseline / 'reference_manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
        for path in self.baseline.iterdir():
            shutil.copyfile(path, self.assets / path.name)

    def tearDown(self):
        self.temp.cleanup()

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.assets.iterdir()}

    def publish(self, verify=False):
        return publisher.run(self.baseline, self.assets, verify, 'lines238')

    def test_publish_preserves_line4_and_is_reproducible(self):
        tu = (self.assets / common.FILES['TU']).read_bytes()
        self.assertEqual(self.publish()['station_count'], 52)
        with common.readonly(self.assets / common.FILES['CU']) as db:
            self.assertFalse(self.line4 - common.table_rows(db, publisher.TABLE))
            self.assertEqual(db.execute('SELECT count(*) FROM ' + common.quote(publisher.TABLE)).fetchone()[0], 85)
            self.assertEqual(db.execute("SELECT station_name FROM station_lookup WHERE region_code='2500' AND match_key='0000000000000319'").fetchone()[0], '机场北(暂未开通)')
        before = self.snapshot()
        self.assertEqual(self.publish(verify=True)['status'], 'verified')
        self.publish()
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((self.assets / common.FILES['TU']).read_bytes(), tu)

    def test_csv_tampering_rejected_without_publication(self):
        before = self.snapshot()
        source, path, lines = publisher.REVISIONS['lines238']
        altered = self.root / path.name
        altered.write_bytes(path.read_bytes() + b'\n')
        shutil.copyfile(path.with_suffix('.review.json'), altered.with_suffix('.review.json'))
        with patch.dict(publisher.REVISIONS, {'lines238': (source, altered, lines)}):
            with self.assertRaisesRegex(ValueError, 'CSV/review mismatch'):
                self.publish()
        self.assertEqual(self.snapshot(), before)

    def test_existing_keys_rejected_without_publication(self):
        self.publish()
        for path in self.assets.iterdir():
            shutil.copyfile(path, self.baseline / path.name)
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'already indexed'):
            self.publish()
        self.assertEqual(self.snapshot(), before)

    def test_manifest_failure_rolls_back_cu(self):
        before = self.snapshot()
        replace = common.os.replace

        def fail_manifest(source, destination):
            if Path(destination) == self.assets / 'reference_manifest.json':
                raise OSError('simulated manifest publication failure')
            return replace(source, destination)

        with patch.object(common.os, 'replace', side_effect=fail_manifest):
            with self.assertRaisesRegex(OSError, 'simulated manifest'):
                self.publish()
        self.assertEqual(self.snapshot(), before)


if __name__ == '__main__':
    unittest.main()
