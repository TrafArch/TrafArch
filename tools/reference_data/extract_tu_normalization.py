"""Re-extract original TU city directories without executing Java or network.

The original constant pairs/sets are independently compared with the frozen
reference extraction, including source order and duplicate set literals.

The runtime aliases are ported by hand in
lib/features/transit_analysis/tunion_record_context.dart; this extractor keeps
the frozen document reproducible for future reference-data updates.
"""
import argparse
import json
from pathlib import Path
import re

from .common import open_readonly, read_json, require, sha256, write_json
from .extract_tu_lookup import Parser
from .tu_normalization import validate_normalization


def extract(sources, reference):
    wanted = {'M0.N.a': 'city_names', 'M0.f.a': 'local_city_names',
              'M0.a.h': 'issuer_city_suffixes', 'M0.a.i': 'issuer_cities'}
    document = {'format_version': 1, 'namespace': 'TU', 'source_evidence': {}}
    count = 0
    db = open_readonly(reference)
    try:
        for path in sorted((sources / 'p034M0').glob('*.java')):
            text = path.read_text(encoding='utf-8')
            cls = re.search(r'JADX INFO: renamed from: ([\w.$]+)', text).group(1)
            if not any(f.startswith(cls + '.') for f in wanted):
                continue
            declarations = {j: o for o, j in re.findall(
                r'/\* JADX INFO: renamed from: (\w+) \*/\s*public static final [\w.<>?, ]+ (f\d+\w*)\s*[;=]', text)}
            for match in re.finditer(r'\b(f\d+\w*)\s*=\s*', text):
                field = cls + '.' + declarations[match.group(1)]
                if field not in wanted:
                    continue
                parser = Parser(text, match.end())
                value = parser.expr()
                parser.expect(';')
                kind = '$map' if field in ('M0.N.a', 'M0.f.a') else '$set'
                require(isinstance(value, dict) and kind in value, 'Unexpected source expression')
                pairs = value[kind]
                oracle = [[json.loads(k), json.loads(v)] for k, v in db.execute(
                    'SELECT key_json,value_json FROM reference_entries WHERE field_id=? ORDER BY entry_index', (field,))]
                require((oracle if kind == '$map' else [v for _, v in oracle]) == pairs,
                        'Independent city directory extraction mismatch: ' + field)
                count += len(pairs)
                document[wanted[field]] = pairs
                document['source_evidence'][field] = {
                    'path': path.relative_to(sources).as_posix(), 'sha256': sha256(path),
                    'line': text.count('\n', 0, match.start()) + 1}
    finally:
        db.close()
    document['verification'] = {'reference_sha256': sha256(reference), 'compared_original_pairs': count}
    return validate_normalization(document)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sources', type=Path, required=True)
    p.add_argument('--reference', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--check', action='store_true')
    a = p.parse_args()
    doc = extract(a.sources, a.reference)
    if a.check:
        require(read_json(a.output) == doc, 'Frozen TU city directory changed')
    else:
        require(not a.output.exists(), 'Refusing to overwrite frozen source')
        write_json(a.output, doc)
    print(json.dumps({'status': 'verified' if a.check else 'extracted',
                      'original_pairs': doc['verification']['compared_original_pairs']}))


if __name__ == '__main__':
    main()
