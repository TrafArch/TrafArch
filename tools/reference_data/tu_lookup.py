"""Contract for the reviewed TU rail/local-terminal supplement.

The original region tables remain byte-for-byte equivalent at the content
level. This document is a separate namespace and never merges local terminal
identifiers into city-prefixed rail keys.
"""
import datetime
import re

from .common import require

ALIAS_FIELDS = ('M0.s.a', 'M0.t.a', 'M0.u.a')
RAIL_FIELDS = ('M0.i0.a', 'M0.W.a', 'M0.a0.a', 'M0.e0.a')


def validate_lookup(document):
    require(isinstance(document, dict) and document.get('format_version') == 1,
            'Unsupported TU lookup document')
    require(document.get('namespace') == 'TU', 'Wrong lookup namespace')
    evidence = document.get('source_evidence')
    require(isinstance(evidence, dict), 'Missing lookup source evidence')
    for section, fields in [('terminal_aliases', ALIAS_FIELDS),
                            ('rail_prefixes', RAIL_FIELDS), ('rail_history', ('N0.e.a',))]:
        rows = document.get(section)
        require(isinstance(rows, list), f'Missing {section}')
        seen = set()
        for row in rows:
            require(isinstance(row, dict) and set(row) == {'source_field', 'source_key', 'raw_value'},
                    f'Wrong {section} row schema')
            field, key, value = row['source_field'], row['source_key'], row['raw_value']
            require(field in fields and field in evidence, 'Unreviewed lookup source field')
            require(isinstance(key, str) and re.fullmatch('[0-9A-F]+', key), 'Invalid lossless key')
            require((field, key) not in seen, 'Duplicate lookup field/key')
            seen.add((field, key))
            source = evidence[field]
            require(isinstance(source, dict) and re.fullmatch('[0-9a-f]{64}', source.get('sha256', ''))
                    and isinstance(source.get('path'), str) and type(source.get('line')) is int,
                    'Incomplete lookup provenance')
            if section == 'terminal_aliases':
                require(len(key) == 12 and isinstance(value, str) and re.fullmatch('[0-9A-F]{8}', value),
                        'Terminal alias requires 12-character local key and 8-character rail suffix')
            elif section == 'rail_prefixes':
                require(5 <= len(key) <= 16 and isinstance(value, list) and len(value) == 3
                        and all(isinstance(v, str) for v in value) and value[2] == '',
                        'Only verified line-only rail prefixes belong in this supplement')
                expected = RAIL_FIELDS[0 if key[0] < '3' else 1 if key[0] == '3' else 2 if key[0] < '6' else 3]
                require(field == expected, 'Rail field disagrees with original city dispatch')
            else:
                require(len(key) >= 5 and isinstance(value, list) and value, 'Invalid history')
                previous = None
                for rule in value:
                    require(isinstance(rule, list) and len(rule) == 4
                            and all(isinstance(v, str) for v in rule[1:])
                            and isinstance(rule[0], dict) and set(rule[0]) == {'$date_literal'},
                            'Invalid dated name override')
                    cutoff = datetime.datetime.fromisoformat(rule[0]['$date_literal'])
                    require(cutoff.tzinfo is not None, 'History cutoff requires the original UTC offset')
                    require(previous is None or cutoff <= previous, 'History must retain newest-first source order')
                    previous = cutoff
    return document
