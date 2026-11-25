"""Prepare a local line colour asset from a checked-out RMG Palette source."""

import argparse
from collections import Counter, defaultdict
from contextlib import closing
import json
from pathlib import Path
import re
import sqlite3


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'third_party/railmapgen_palette/tu_colors.json'
HEX_COLOUR = re.compile(r'#[0-9a-fA-F]{6}')
NUMBERED_LINE = re.compile(r'([0-9]{1,3})\s*[号號]\s*[线線]')
RMG_LINE_IDS = {
    '1000': {'1号线': 'bj1', '八通线': 'bj1', '4号线': 'bj4', '大兴线': 'bj4'},
    '5810': {'APM线': 'apm'},
}


def city_name(value):
    return value.strip().removesuffix('市')


def line_name(value):
    text = value.strip()
    match = NUMBERED_LINE.fullmatch(text)
    return f'{int(match[1])}号线' if match else text.upper()


def read_asset_db(system):
    path = ROOT / f'assets/data/TrafArch_Database_{system}.sqlite'
    return sqlite3.connect(path.as_uri() + '?mode=ro&immutable=1', uri=True)


def regions(connection):
    return connection.execute(
        'SELECT region_code, region_name, table_name FROM regions '
        'WHERE region_code IS NOT NULL ORDER BY region_code'
    ).fetchall()


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def simplified_name(row):
    return row.get('name', {}).get('zh-Hans') or ''


def matching_colours(tu, code, table, rows):
    line_ids = RMG_LINE_IDS.get(code, {})
    ids = defaultdict(list)
    names = defaultdict(list)
    for row in rows:
        ids[row['id']].append(row.get('colour'))
        names[line_name(simplified_name(row))].append(row.get('colour'))

    quoted_table = '"' + table.replace('"', '""') + '"'
    lines = tu.execute(
        f'SELECT DISTINCT line_name FROM {quoted_table} '
        "WHERE transport_type IN ('metro', 'rail', 'maglev') AND line_name IS NOT NULL"
    )
    colours = {}
    for (label,) in lines:
        key = line_name(label)
        hits = ids[line_ids[key]] if key in line_ids else names[key]
        if len(hits) == 1 and isinstance(hits[0], str) and HEX_COLOUR.fullmatch(hits[0]):
            colours[key] = hits[0].upper()
    return colours


def build_palette(resources, revision):
    city_ids = defaultdict(list)
    for city in read_json(resources / 'city-config.json'):
        label = city_name(simplified_name(city))
        if label:
            city_ids[label].append(city['id'])

    with closing(read_asset_db('TU')) as tu, closing(read_asset_db('CU')) as cu:
        tu_regions = regions(tu)
        cu_regions = regions(cu)
        tu_counts = Counter(city_name(name) for _, name, _ in tu_regions)
        cu_counts = Counter(city_name(name) for _, name, _ in cu_regions)
        tu_codes = {
            city_name(name): code
            for code, name, _ in tu_regions
            if tu_counts[city_name(name)] == 1
        }
        cities = {}
        for code, name, table in tu_regions:
            label = city_name(name)
            hits = city_ids.get(label, [])
            info = cities[code] = {'name': label}
            if label in tu_codes and len(hits) == 1:
                city_id = hits[0]
                colour_file = resources / 'palettes' / f'{city_id}.json'
                colours = matching_colours(tu, code, table, read_json(colour_file))
                if colours:
                    info.update(rmg=city_id, colors=colours)
        cu_to_tu = {
            code: tu_codes[label]
            for code, name, _ in cu_regions
            if (label := city_name(name)) in tu_codes and cu_counts[label] == 1
        }

    return {'revision': revision, 'cities': cities, 'cuToTu': cu_to_tu}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rmg-repo', required=True, type=Path)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.revision):
        parser.error('--revision must be the full RMG Palette commit SHA')

    resources = args.rmg_repo / 'public/resources'
    palette = build_palette(resources, args.revision)
    content = json.dumps(palette, ensure_ascii=False, indent=2, sort_keys=True) + '\n'
    if args.check:
        if OUTPUT.read_text(encoding='utf-8') != content:
            parser.error(f'{OUTPUT} does not match the specified source')
    else:
        OUTPUT.write_text(content, encoding='utf-8', newline='\n')
    covered = [item['colors'] for item in palette['cities'].values() if 'colors' in item]
    print(f'{sum(map(len, covered))} line colours across {len(covered)} cities')


if __name__ == '__main__':
    main()
