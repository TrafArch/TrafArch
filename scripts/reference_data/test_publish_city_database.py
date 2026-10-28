"""Regression tests for authoritative city-table publication and rollback."""
from contextlib import closing
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

import publish_city_database as publisher


class CityPublisherTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.baseline = self.root / 'baseline'
        self.baseline.mkdir()
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        self.source = self.root / 'developer.sqlite'
        self.report = self.root / 'evidence/report.json'
        self.fixture = self.root / 'test-fixture.json'
        for protocol, name in publisher.FILES.items():
            with closing(sqlite3.connect(self.baseline / name)) as db:
                db.executescript("""
                    CREATE TABLE reference_package(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                    CREATE TABLE reference_documents(name TEXT PRIMARY KEY,json TEXT NOT NULL);
                """)
                db.executemany('INSERT INTO reference_package VALUES(?,?)', [('protocol', protocol), ('format_version', '1'), ('content_version', 'baseline')])
                if protocol == 'TU':
                    db.executescript("""
                        PRAGMA user_version=4;
                        CREATE TABLE regions(region_id INTEGER,region_code TEXT,table_name TEXT);
                        INSERT INTO regions VALUES(1,'1121','region_天津_1121');
                        CREATE TABLE "region_天津_1121"(station_id INTEGER PRIMARY KEY,transport_type TEXT,line_name TEXT,station_name TEXT,system_name TEXT,source_field TEXT,source_key TEXT,source_region_code TEXT,source_region_name TEXT,raw_value_json TEXT,confidence TEXT);
                        CREATE TABLE region_1_transport_summary(transport_type TEXT PRIMARY KEY,station_count INTEGER);
                        INSERT INTO region_1_transport_summary VALUES('metro',1);
                        CREATE TABLE source_metadata(name TEXT PRIMARY KEY,value TEXT);
                        INSERT INTO source_metadata VALUES('station_count','1'),('transport_type_counts','{"metro":1}'),('unknown_transport_type_count','0');
                        CREATE TABLE record_provenance(table_name TEXT,station_id INTEGER,source_table TEXT,source_station_id INTEGER,native_namespace TEXT,copy_role TEXT,record_kind TEXT,lookup_key_namespace TEXT,classification_basis TEXT,source_row_sha256 TEXT,PRIMARY KEY(table_name,station_id),UNIQUE(source_table,source_station_id));
                        CREATE VIEW all_records AS SELECT s.*,p.native_namespace FROM "region_天津_1121" s JOIN record_provenance p ON p.table_name='region_天津_1121' AND p.station_id=s.station_id;
                    """)
                    db.execute('INSERT INTO reference_documents VALUES(?,?)', ('tu_lookup', '{}'))
                    self.insert_row(db, 1, 'old')
                    db.execute('INSERT INTO record_provenance VALUES(?,?,?,?,?,?,?,?,?,?)', ('region_天津_1121', 1, 'region_天津_1121', 1, 'TU', 'native', 'station_mapping', 'TU', 'old', 'hash'))
                db.commit()
        manifest = {'format_version': 1, 'sources': [], 'normalization': {}, 'packages': {}}
        for protocol, name in publisher.FILES.items():
            path = self.baseline / name
            with publisher.readonly(path) as db:
                manifest['packages'][protocol] = {'file': name, 'sha256': publisher.digest(path.read_bytes()), 'bytes': path.stat().st_size, 'content_version': 'baseline', 'tables': publisher.counts(db)}
            shutil.copyfile(path, self.assets / name)
        (self.baseline / 'reference_manifest.json').write_text(json.dumps(manifest))
        (self.assets / 'reference_manifest.json').write_text(json.dumps(manifest))
        shutil.copyfile(self.baseline / publisher.FILES['TU'], self.source)
        with closing(sqlite3.connect(self.source)) as db:
            # Authoritative replacement removes an old row and supplies another.
            db.execute('DELETE FROM "region_天津_1121"')
            db.execute('DELETE FROM record_provenance')
            self.insert_row(db, 2, '丽江道')
            db.commit()

    @staticmethod
    def insert_row(db, identity, station):
        db.execute('INSERT INTO "region_天津_1121" VALUES(?,?,?,?,?,?,?,?,?,?,?)', (identity, 'metro', '7号线', station, '', 'M0.i0.a', '00070018', '1121', '天津', '["","7号线","' + station + '"]', 'high'))

    def tearDown(self):
        self.temp.cleanup()

    def publish(self, **kwargs):
        return publisher.run(self.source, self.baseline, self.assets, self.report, fixture_output=self.fixture, **kwargs)

    def test_publishes_authoritative_rows_without_resurrecting_deleted_rows(self):
        before = self.source.read_bytes()
        result = self.publish()
        self.assertEqual(result['provenance_rows_added'], 1)
        with publisher.readonly(self.assets / publisher.FILES['TU']) as db:
            self.assertEqual([r[0] for r in db.execute('SELECT station_id FROM "region_天津_1121"')], [2])
            self.assertEqual(db.execute('SELECT count(*) FROM all_records').fetchone()[0], 1)
            self.assertNotIn('community_reference_rows', publisher.counts(db))
        self.assertEqual(self.source.read_bytes(), before)
        self.assertEqual((self.assets / publisher.FILES['CU']).read_bytes(), (self.baseline / publisher.FILES['CU']).read_bytes())
        row = json.loads(self.fixture.read_text(encoding='utf-8'))['rows'][0]
        self.assertEqual((row['city'], row['table'], row['source_key']), ('1121', 'region_天津_1121', '00070018'))

    def test_repeat_publication_is_byte_reproducible_and_verify_does_not_publish(self):
        self.publish()
        original = {p.name: p.read_bytes() for p in self.assets.iterdir()}
        self.assertTrue(self.publish(verify=True)['idempotent'])
        self.assertTrue(self.publish()['idempotent'])
        self.assertEqual(original, {p.name: p.read_bytes() for p in self.assets.iterdir()})

    def test_unknown_source_classification_is_rejected(self):
        with closing(sqlite3.connect(self.source)) as db:
            db.execute('UPDATE "region_天津_1121" SET source_field=?', ('unreviewed',))
            db.commit()
        before = {p.name: p.read_bytes() for p in self.assets.iterdir()}
        with self.assertRaisesRegex(ValueError, 'Unreviewed missing provenance'):
            self.publish()
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.assets.iterdir()})

    def test_extra_table_is_rejected_without_mutation(self):
        with closing(sqlite3.connect(self.source)) as db:
            db.execute('CREATE TABLE community_reference_rows(value TEXT)')
        with self.assertRaisesRegex(ValueError, 'schema differs'):
            self.publish()

    def test_invalid_baseline_hash_is_rejected(self):
        with (self.baseline / publisher.FILES['CU']).open('ab') as handle:
            handle.write(b'changed')
        with self.assertRaisesRegex(ValueError, 'manifest digest/size mismatch'):
            self.publish()

    def test_report_cannot_overwrite_published_asset(self):
        with self.assertRaisesRegex(ValueError, 'Report must be outside'):
            publisher.run(self.source, self.baseline, self.assets, self.assets / 'report.json')

    def test_partial_publish_failure_restores_every_replaced_file(self):
        stage = self.root / 'stage'
        stage.mkdir()
        pairs = []
        for index in range(3):
            src, dst = stage / str(index), self.assets / str(index)
            src.write_text('new')
            dst.write_text('old')
            pairs.append((src, dst))
        original_replace = publisher.os.replace
        calls = 0
        def fail_second(source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('injected replacement failure')
            return original_replace(source, destination)
        with patch.object(publisher.os, 'replace', side_effect=fail_second):
            with self.assertRaisesRegex(OSError, 'injected'):
                publisher.replace_set(pairs, stage)
        self.assertTrue(all(dst.read_text() == 'old' for _, dst in pairs))


if __name__ == '__main__':
    unittest.main()
