#!/usr/bin/env python3
"""Publish reviewed user CU Jinan city-table revisions, entirely offline.

Consumes the original CLI's import-csv review artifact. The baseline is the
current published package, never the older recovered tools' default sources.
"""
from contextlib import closing
import argparse
import base64
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile

from publish_city_database import (
    FILES, canonical, counts, digest, quote, readonly, replace_set,
    schema, table_rows, validate,
)

TABLE = 'region_济南_2500'
SOURCE = 'user-jinan-cu-line4-20261030'
INPUT = Path(__file__).parent / 'inputs/jinan_cu_line4.csv'
REVISIONS = {
    'line4': (SOURCE, INPUT, {4: 33}),
    'lines238': ('user-jinan-cu-lines238-20261030',
                 INPUT.with_name('jinan_cu_lines238.csv'), {2: 19, 3: 19, 8: 14}),
}


def reviewed_rows(revision='line4'):
    source, path, lines = REVISIONS[revision]
    review = json.loads(path.with_suffix('.review.json').read_text(encoding='utf-8'))
    raw = path.read_bytes()
    if (review['protocol'] != 'CU' or review['source_id'] != source
            or review['source_sha256'] != digest(raw)
            or review['source_bytes'] != len(raw)
            or base64.b64decode(review['raw_source_base64']) != raw
            or review['status'] != 'ready_for_mapping' or review['conflicts']):
        raise ValueError('CSV/review mismatch or unreviewed conflicts')
    rows = review['records']
    expected_codes = [(line, f'{line * 100 + index:016d}')
                      for line, size in lines.items() for index in range(1, size + 1)]
    if len(rows) != len(expected_codes) or review['selected_records'] != list(range(1, len(rows) + 1)):
        raise ValueError('Expected all screenshot stations in order')
    for number, (row, (line, key)) in enumerate(zip(rows, expected_codes), 1):
        expected = ['2500', key, 'metro', f'{line}号线', row['station_name']]
        if (row['record'] != number or row['protocol'] != 'CU' or row['region_code'] != '2500'
                or row['source_key'] != key or row['raw_cells'] != expected
                or row['line_name'] != expected[3] or row['transport_type'] != 'metro'
                or not row['station_name']):
            raise ValueError('Unexpected station record')
    return rows


def maintain(db, rows, version, revision='line4'):
    source = REVISIONS[revision][0]
    existing = db.execute("SELECT table_name FROM regions WHERE region_code='2500'").fetchone()
    if bool(existing) != (revision == 'lines238'):
        raise ValueError('line4 requires pre-Jinan baseline; lines238 requires existing Line 4')
    if db.execute("SELECT region_name FROM region_codes WHERE region_code='2500'").fetchone() != ('济南市',):
        raise ValueError('Baseline does not identify CU 2500 as Jinan')
    if existing:
        if existing[0] != TABLE:
            raise ValueError('Unexpected Jinan city table')
        if db.execute('SELECT count(*) FROM ' + quote(TABLE) + " WHERE line_name='4号线'").fetchone()[0] != 33:
            raise ValueError('Expected existing 33 Line 4 stations')
    else:
        # Same existing per-city schema, with city CHECK and foreign key intact.
        template = db.execute("SELECT sql FROM sqlite_master WHERE name='region_绍兴_3120'").fetchone()[0]
        db.execute(template.replace('region_绍兴_3120', TABLE).replace("'3120'", "'2500'"))
        region_id = db.execute('SELECT max(region_id)+1 FROM regions').fetchone()[0]
        db.execute('INSERT INTO regions VALUES(?,?,?,?,?,?)',
                   (region_id, '2500', '250000', '济南', TABLE, 0))
    first_id = db.execute('SELECT coalesce(max(station_id),0) FROM ' + quote(TABLE)).fetchone()[0]
    for row in rows:
        number, key = first_id + row['record'], row['source_key']
        line, line_code = row['line_name'], key[-4:-2]
        if db.execute("SELECT 1 FROM terminal_index WHERE region_code='2500' AND match_key=?", (key,)).fetchone():
            raise ValueError('Station key already indexed: ' + key)
        db.execute('INSERT INTO station_registry VALUES(?,?)', ('2500', number))
        db.execute('INSERT INTO ' + quote(TABLE) + ' VALUES(' + ','.join('?' * 20) + ')', (
            number, '2500', 'metro', line, row['station_name'], '',
            'user_provided', 1, source, key, '2500', '济南', row['raw_value_json'],
            key[:14], line_code, str(int(line_code)), key[-2:], line,
            f'user_specified_16_digit_zero_padded_{line_code}xx', 1))
        # Match only the complete supplied CU code inside Jinan's namespace.
        db.execute('INSERT INTO terminal_index VALUES(?,?,?,?,?,?)',
                   ('2500', key, 'exact', -1, number, 100))
    if not existing:
        old_view = db.execute("SELECT sql FROM sqlite_master WHERE name='stations'").fetchone()[0]
        db.execute('DROP VIEW stations')
        db.execute(old_view + ' UNION ALL SELECT * FROM ' + quote(TABLE))
    db.execute("UPDATE regions SET record_count=? WHERE region_code='2500'",
               (db.execute('SELECT count(*) FROM ' + quote(TABLE)).fetchone()[0],))
    queries = {
        'region_count': 'SELECT count(*) FROM regions',
        'station_record_count': 'SELECT count(*) FROM stations',
        'default_station_record_count': 'SELECT count(*) FROM default_stations',
        'terminal_index_count': 'SELECT count(*) FROM terminal_index',
    }
    for key, query in queries.items():
        cursor = db.execute('UPDATE metadata SET value=? WHERE name=?',
                            (str(db.execute(query).fetchone()[0]), key))
        if cursor.rowcount != 1:
            raise ValueError('Missing CU count metadata: ' + key)
    db.execute("UPDATE reference_package SET value=? WHERE key='content_version'", (version,))
    db.commit()


def verify_preservation(before, after, rows):
    mutable = {'regions', 'station_registry', 'terminal_index', 'metadata', 'reference_package', TABLE}
    for table in counts(before):
        old, new = table_rows(before, table), table_rows(after, table)
        if table not in mutable and old != new:
            raise ValueError('Unrelated business rows changed: ' + table)
        if table in {'station_registry', 'terminal_index', TABLE} and old - new:
            raise ValueError('Existing rows removed: ' + table)
    for region in before.execute('SELECT * FROM regions'):
        current = after.execute('SELECT * FROM regions WHERE region_code=?', (region['region_code'],)).fetchone()
        if current is None or (list(region)[:-1] != list(current)[:-1]) or (region['region_code'] != '2500' and list(region) != list(current)):
            raise ValueError('Existing region changed beyond Jinan count')
    allowed_metadata = {'region_count', 'station_record_count', 'default_station_record_count', 'terminal_index_count'}
    for key, value in before.execute('SELECT * FROM metadata'):
        if key not in allowed_metadata and after.execute('SELECT value FROM metadata WHERE name=?', (key,)).fetchone()[0] != value:
            raise ValueError('Unrelated metadata changed: ' + key)
    expected_schema = [r for r in schema(before) if r[1] not in {'stations', TABLE}]
    actual_schema = [r for r in schema(after) if r[1] not in {'stations', TABLE}]
    if expected_schema != actual_schema or before.execute('PRAGMA user_version').fetchone()[0] != after.execute('PRAGMA user_version').fetchone()[0]:
        raise ValueError('Unrelated schema or user_version changed')
    for row in rows:
        result = after.execute('SELECT line_name,station_name,source_key FROM station_lookup WHERE region_code=? AND match_key=?', ('2500', row['source_key'])).fetchall()
        if [tuple(r) for r in result] != [(row['line_name'], row['station_name'], row['source_key'])]:
            raise ValueError('Station missing/ambiguous in runtime view')


def run(baseline, assets, verify=False, revision='line4'):
    baseline, assets = baseline.resolve(), assets.resolve()
    if baseline == assets or baseline.is_relative_to(assets) or assets.is_relative_to(baseline):
        raise ValueError('Baseline and publication must be separate directories')
    source, path, lines = REVISIONS[revision]
    rows = reviewed_rows(revision)
    manifest = json.loads((baseline / 'reference_manifest.json').read_text(encoding='utf-8'))
    for protocol, name in FILES.items():
        validate(baseline / name, manifest['packages'][protocol], protocol)
    evidence = {
        'id': source, 'protocol': 'CU', 'kind': 'csv', 'file': path.name,
        'sha256': digest(path.read_bytes()), 'bytes': path.stat().st_size,
        'origin': 'User screenshot station order and user-confirmed 16-digit zero-padded line/station codes; no physical-card verification',
        'priority': 500, 'review_sha256': digest(path.with_suffix('.review.json').read_bytes()),
        'baseline_manifest_sha256': digest((baseline / 'reference_manifest.json').read_bytes()),
        'publisher_sha256': digest(Path(__file__).read_bytes()),
        'publisher_helpers_sha256': digest(Path(__file__).with_name('publish_city_database.py').read_bytes()),
        'sqlite_version': sqlite3.sqlite_version,
    }
    version = digest(canonical(evidence).encode('utf-8'))
    with tempfile.TemporaryDirectory(prefix='trafarch-jinan-', dir=assets.parent) as directory:
        stage = Path(directory)
        target = stage / FILES['CU']
        shutil.copyfile(baseline / FILES['CU'], target)
        with closing(sqlite3.connect(target)) as db:
            db.execute('PRAGMA foreign_keys=ON')
            maintain(db, rows, version, revision)
        with readonly(baseline / FILES['CU']) as before, readonly(target) as after:
            verify_preservation(before, after, rows)
            spec = dict(manifest['packages']['CU'], sha256=digest(target.read_bytes()),
                        bytes=target.stat().st_size, content_version=version, tables=counts(after))
        manifest['packages']['CU'] = spec
        manifest['sources'].append(evidence)
        manifest['jinan_cu_' + revision + '_update'] = dict(
            evidence, station_count=len(rows), lines=lines, table=TABLE,
            match_mode='exact', tu_bytes_preserved=True)
        publication = stage / 'reference_manifest.json'
        publication.write_text(json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + '\n', encoding='utf-8')
        validate(target, spec, 'CU')
        if (assets / FILES['TU']).read_bytes() != (baseline / FILES['TU']).read_bytes():
            raise ValueError('TU differs from frozen baseline')
        if verify:
            if target.read_bytes() != (assets / FILES['CU']).read_bytes() or publication.read_bytes() != (assets / publication.name).read_bytes():
                raise ValueError('Published CU/manifest differs from reproducible output')
        else:
            replace_set([(target, assets / target.name), (publication, assets / publication.name)], stage)
    return {'status': 'verified' if verify else 'published', 'station_count': len(rows),
            'cu_sha256': spec['sha256'], 'tu_bytes_preserved': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-dir', type=Path, required=True)
    parser.add_argument('--asset-dir', type=Path, default=Path('assets/data'))
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--revision', choices=REVISIONS, default='line4')
    args = parser.parse_args()
    print(json.dumps(run(args.baseline_dir, args.asset_dir, args.verify, args.revision), ensure_ascii=False))
