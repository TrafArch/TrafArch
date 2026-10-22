"""Reproduce the reviewed TU lookup snapshot from local JADX constants.

Only allowlisted literal constructors are parsed; Java is never executed.
Each extracted pair is checked against the independent original reference DB.
Use --check to compare against a frozen snapshot without writing it.
"""
import argparse
import json
from pathlib import Path
import re

from .common import open_readonly, read_json, require, sha256, write_json
from .tu_lookup import ALIAS_FIELDS, RAIL_FIELDS, validate_lookup

TOKEN = re.compile(r'\s*(?:("(?:\\.|[^"\\])*")|(-?(?:0x[0-9a-fA-F]+|\d+)(?:\.\d+)?[lLfFdD]?)|([A-Za-z_$][\w.$]*)|([(),;]))')

class Parser:
    def __init__(self, text, start):
        self.text, self.pos = text, start
    def token(self):
        m = TOKEN.match(self.text, self.pos)
        if not m:
            raise ValueError(f'Nonliteral expression at {self.pos}: {self.text[self.pos:self.pos+100]!r}')
        self.pos = m.end()
        return next((i, v) for i, v in enumerate(m.groups()) if v is not None)
    def peek(self):
        pos = self.pos
        t = self.token()
        self.pos = pos
        return t
    def expect(self, expected):
        actual = self.token()[1]
        if actual != expected:
            raise ValueError((expected, actual))
    def expr(self):
        kind, token = self.token()
        if kind == 0:
            return json.loads(token)
        if kind == 1:
            token = token.rstrip('lLfFdD')
            return float(token) if '.' in token else int(token, 16 if token.lstrip('-').startswith('0x') else 10)
        if kind != 2:
            raise ValueError(token)
        if token == 'new':
            _, token = self.token()
        if self.peek()[1] != '(':
            if token in ('true', 'false', 'null'):
                return {'true': True, 'false': False, 'null': None}[token]
            raise ValueError(token)
        self.expect('(')
        args = []
        if self.peek()[1] != ')':
            while True:
                args.append(self.expr())
                if self.peek()[1] != ',':
                    break
                self.expect(',')
        self.expect(')')
        if token in ('AbstractC1668k.m3470y', 'C1739d'):
            assert len(args) == 2
            return {'$pair': args}
        if token == 'AbstractC1785u.m3727B':
            assert all(isinstance(x, dict) and '$pair' in x for x in args)
            return {'$map': [x['$pair'] for x in args]}
        if token == 'AbstractC1774j.m3719A':
            return args
        if token == 'AbstractC1668k.m3460o':
            assert len(args) == 1
            return args
        if token == 'AbstractC1788x.m3731A':
            return {'$set': args}
        if token == 'simpleDateFormat.parse':
            return {'$date_literal': args[0]}
        raise ValueError(f'Nonallowlisted constructor {token}')


def extract(sources, reference, baseline):
    wanted = set(ALIAS_FIELDS + RAIL_FIELDS + ('N0.e.a',))
    fields, provenance = {}, {}
    for path in sorted([*(sources / 'p034M0').glob('*.java'), *(sources / 'p037N0').glob('*.java')]):
        text = path.read_text(encoding='utf-8')
        cls = re.search(r'JADX INFO: renamed from: ([\w.$]+)', text).group(1)
        if not any(fid.startswith(cls + '.') for fid in wanted):
            continue
        declarations = {java: original for original, java in re.findall(
            r'/\* JADX INFO: renamed from: (\w+) \*/\s*public static final [\w.<>?, ]+ (f\d+\w*)\s*[;=]', text)}
        for match in re.finditer(r'\b(f\d+\w*)\s*=\s*', text):
            field = cls + '.' + declarations[match.group(1)]
            if field not in wanted:
                continue
            parser = Parser(text, match.end())
            value = parser.expr()
            parser.expect(';')
            require(isinstance(value, dict) and '$map' in value, 'Expected source map')
            fields[field] = value['$map']
            provenance[field] = {'path': path.relative_to(sources).as_posix(),
                                 'sha256': sha256(path), 'line': text.count('\n', 0, match.start()) + 1}
    require(set(fields) == wanted, 'Original source fields missing')
    checked = 0
    ref, old = open_readonly(reference), open_readonly(baseline)
    try:
        for field, entries in fields.items():
            independently_extracted = [[json.loads(k), json.loads(v)] for k, v in ref.execute(
                'SELECT key_json,value_json FROM reference_entries WHERE field_id=? ORDER BY entry_index', (field,))]
            require(independently_extracted == entries, f'Independent extraction mismatch: {field}')
            checked += len(entries)
        packaged = set(old.execute('SELECT source_field,source_key FROM all_records'))
    finally:
        ref.close()
        old.close()
    def rows(names, missing=False):
        return [{'source_field': field, 'source_key': key, 'raw_value': value}
                for field in names for key, value in dict(fields[field]).items()
                if not missing or (field, key) not in packaged]
    document = {
        'format_version': 1, 'namespace': 'TU',
        'source_evidence': provenance,
        'verification': {'reference_sha256': sha256(reference), 'baseline_sha256': sha256(baseline),
                         'compared_original_pairs': checked},
        'terminal_aliases': rows(ALIAS_FIELDS),
        'rail_prefixes': rows(RAIL_FIELDS, missing=True),
        'rail_history': rows(('N0.e.a',)),
    }
    validate_lookup(document)
    require([len(document[s]) for s in ('terminal_aliases', 'rail_prefixes', 'rail_history')] == [4014, 270, 30],
            'Source revision differs from reviewed audit; review before adding records')
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    document = extract(args.sources, args.reference, args.baseline)
    if args.check:
        require(read_json(args.output) == document, 'Frozen lookup snapshot differs from original constants')
    else:
        require(not args.output.exists(), 'Refusing to overwrite a frozen snapshot; use --check')
        write_json(args.output, document)
    print(json.dumps({'status': 'verified' if args.check else 'extracted',
                      'original_pairs': document['verification']['compared_original_pairs'],
                      'aliases': 4014, 'line_prefixes': 270, 'history_keys': 30}))


if __name__ == '__main__':
    main()
