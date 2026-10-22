"""Lossless source contract for the TU 1E city normalization directory.

The runtime aliases ported from this directory live in
lib/features/transit_analysis/tunion_record_context.dart; this module and its
frozen document remain as the reproducible source contract for that port.
"""
import re

from .common import require


def validate_normalization(document):
    require(isinstance(document, dict) and document.get('format_version') == 1
            and document.get('namespace') == 'TU', 'Unsupported TU normalization document')
    fields = {'M0.N.a': 'city_names', 'M0.f.a': 'local_city_names',
              'M0.a.h': 'issuer_city_suffixes', 'M0.a.i': 'issuer_cities'}
    evidence = document.get('source_evidence', {})
    for field, section in fields.items():
        proof = evidence.get(field, {})
        require(re.fullmatch('[0-9a-f]{64}', proof.get('sha256', '')) is not None
                and isinstance(proof.get('path'), str) and type(proof.get('line')) is int,
                'Missing TU normalization source evidence')
        values = document.get(section)
        require(isinstance(values, list) and values, 'Missing TU normalization directory')
        if section.endswith('_names'):
            require(all(isinstance(r, list) and len(r) == 2 and type(r[0]) is int
                        and isinstance(r[1], str) for r in values), 'Invalid city directory')
        else:
            expected = str if section == 'issuer_city_suffixes' else int
            require(all(type(r) is expected for r in values), 'Invalid issuer city set')
    return document
