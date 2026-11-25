"""Prepare a local line colour asset from a checked-out RMG Palette source."""

import argparse
from collections import Counter, defaultdict
from contextlib import closing
import hashlib
import json
from pathlib import Path
import re
import sqlite3


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'third_party/railmapgen_palette/tu_colors.json'
HEX_COLOUR = re.compile(r'#[0-9a-fA-F]{6}')
NUMBERED_LINE = re.compile(r'([0-9]{1,3})\s*[号號]\s*[线線]')
LINE_ALIAS = re.compile(r'\s*[（(][^）)]*[）)]\s*$')
RMG_LINE_IDS = {
    '1000': {'1号线': 'bj1', '八通线': 'bj1', '4号线': 'bj4', '大兴线': 'bj4'},
    '5810': {'APM线': 'apm'},
    # sz8orig is a separate RMG entry. The TU label only identifies 8号线,
    # so its active palette is selected by the explicit sz8 identity.
    '5840': {'8号线': 'sz8', '坪山云巴1号线': 'szpsyb'},
}


def city_name(value):
    return value.strip().removesuffix('市')


def line_name(value):
    text = LINE_ALIAS.sub('', value.strip())
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


def read_source(path):
    raw = path.read_bytes()
    return json.loads(raw), hashlib.sha256(raw).hexdigest()


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
    city_config, _ = read_source(resources / 'city-config.json')
    city_rows = {}
    rmg_cities = {}
    for city in city_config:
        if city.get('country') != 'CN':
            continue
        label = city_name(simplified_name(city))
        if label:
            city_ids[label].append(city['id'])
        colour_file = resources / 'palettes' / f'{city["id"]}.json'
        rows, source_sha256 = read_source(colour_file)
        city_rows[city['id']] = rows
        lines = []
        for row in rows:
            names = _line_names(row)
            colour = row.get('colour')
            if not row.get('id') or not names or not isinstance(colour, str):
                continue
            if not HEX_COLOUR.fullmatch(colour):
                continue
            foreground = row.get('fg')
            lines.append({
                'id': row['id'],
                'names': names,
                'colour': colour.upper(),
                'foreground': foreground.upper()
                if isinstance(foreground, str)
                and HEX_COLOUR.fullmatch(foreground)
                else None,
            })
        rmg_cities[city['id']] = {
            'names': city.get('name', {}),
            'country': city.get('country'),
            'sourceSha256': source_sha256,
            'lines': lines,
        }

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
                rows = city_rows[city_id]
                info['rmg'] = city_id
                info['sourceSha256'] = rmg_cities[city_id]['sourceSha256']
                colours = matching_colours(tu, code, table, rows)
                if colours:
                    info['colors'] = colours
        cu_to_tu = {
            code: tu_codes[label]
            for code, name, _ in cu_regions
            if (label := city_name(name)) in tu_codes and cu_counts[label] == 1
        }

    return {
        'revision': revision,
        'cities': cities,
        'cuToTu': cu_to_tu,
        'rmgCities': rmg_cities,
    }


def _line_names(row):
    return {
        language: value.strip()
        for language, value in row.get('name', {}).items()
        if isinstance(value, str) and value.strip()
    }


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
    rmg_lines = sum(
        len(city['lines']) for city in palette['rmgCities'].values()
    )
    print(
        f'{rmg_lines} RMG line colours across {len(palette["rmgCities"])} cities; '
        f'{sum(map(len, covered))} selected for {len(covered)} TU cities'
    )


if __name__ == '__main__':
    main()
