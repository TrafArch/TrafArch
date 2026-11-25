"""Inline simple CSS paint rules so Flutter SVG rendering keeps the artwork colour."""

import argparse
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ASSETS = ROOT / 'assets/Line_Icon'
SVG = 'http://www.w3.org/2000/svg'
STYLE = f'{{{SVG}}}style'
SUPPORTED = {
    'clip-path',
    'color',
    'display',
    'enable-background',
    'fill',
    'fill-opacity',
    'fill-rule',
    'filter',
    'font-family',
    'font-size',
    'font-weight',
    'letter-spacing',
    'mask',
    'opacity',
    'paint-order',
    'stroke',
    'stroke-dasharray',
    'stroke-dashoffset',
    'stroke-linecap',
    'stroke-linejoin',
    'stroke-miterlimit',
    'stroke-opacity',
    'stroke-width',
    'text-anchor',
    'visibility',
}


def declarations(value):
    result = {}
    for item in value.split(';'):
        if ':' in item:
            name, setting = item.split(':', 1)
            result[name.strip()] = setting.strip()
    return result


def class_rules(root):
    rules = {}
    for parent in root.iter():
        for style in list(parent):
            if style.tag != STYLE:
                continue
            for selectors, body in re.findall(r'([^{}]+)\{([^{}]*)\}', style.text or ''):
                settings = declarations(body)
                for selector in selectors.split(','):
                    match = re.fullmatch(r'\s*\.([A-Za-z0-9_-]+)\s*', selector)
                    if match:
                        rules.setdefault(match[1], {}).update(settings)
            parent.remove(style)
    return rules


def normalize(path):
    ET.register_namespace('', SVG)
    ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
    tree = ET.parse(path)
    root = tree.getroot()
    rules = class_rules(root)
    changed = bool(rules)
    for element in root.iter():
        classes = element.attrib.pop('class', '').split()
        if not classes:
            continue
        changed = True
        inline = declarations(element.attrib.get('style', ''))
        for css_class in classes:
            for name, value in rules.get(css_class, {}).items():
                if name in SUPPORTED and name not in inline:
                    element.set(name, value)
    if changed:
        ET.indent(tree, space='  ')
        tree.write(path, encoding='utf-8', xml_declaration=True)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=DEFAULT_ASSETS)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    files = sorted(args.root.rglob('*.svg'))
    unsafe = [
        path
        for path in files
        if ET.parse(path).getroot().find(f'.//{STYLE}') is not None
        or any('class' in element.attrib for element in ET.parse(path).getroot().iter())
    ]
    if args.check:
        if unsafe:
            for path in unsafe:
                print(path.relative_to(args.root))
            parser.error('SVG CSS classes may render black in Flutter')
        print(f'{len(files)} SVGs have no CSS class paint rules')
        return
    changed = [path for path in files if normalize(path)]
    print(f'Normalized {len(changed)} of {len(files)} SVGs')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ET.ParseError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
