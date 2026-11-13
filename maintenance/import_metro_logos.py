"""Import the user-supplied metro_logo.zip as offline SVG assets.

The 2026-11-12 source contains 54 SVGs using simple .class { fill: value; }
rules. flutter_svg's compiler does not apply these stylesheet classes. Expand
their fill values into presentation attributes, removing the expanded class
attributes and style elements without changing geometry, gradient definitions,
identifiers, internal references, or the original ZIP.
Unsupported CSS/SVG constructs fail explicitly rather than losing information.

Usage:
    python maintenance/import_metro_logos.py path/to/metro_logo.zip
    python maintenance/import_metro_logos.py path/to/metro_logo.zip --check
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr
import zipfile


SVG_NS = "{http://www.w3.org/2000/svg}"
FILE_NAME = re.compile(r"metro_logo_[a-z]+\.svg")
CSS_RULE = re.compile(r"\s*\.([A-Za-z_][\w-]*)\s*\{\s*fill\s*:\s*([^;{}]+)\s*;?\s*\}")
FILL_VALUE = re.compile(r"(?:none|red|#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?|url\(#[^\s()]+\))")
OPEN_TAG = re.compile(r'''<(?![!?/])(?:[^>"']|"[^"]*"|'[^']*')+>''')
ATTRIBUTE = re.compile(r'''([\w:.-]+)\s*=\s*("[^"]*"|'[^']*')''')
STYLE_ELEMENT = re.compile(r"<style(?:\s[^>]*)?>.*?</style\s*>", re.DOTALL)
ALLOWED_TAGS = {
    "svg", "defs", "style", "path", "rect", "polygon", "g", "circle",
    "ellipse", "linearGradient", "radialGradient", "stop",
}


def expand_fills(source: bytes) -> bytes:
    text = source.decode("utf-8-sig")
    if "<!" in text:
        raise ValueError("Declarations, entities and comments are outside this import format")
    root = ET.fromstring(text)
    if root.tag != f"{SVG_NS}svg":
        raise ValueError("Expected a namespaced SVG document")
    rules: list[tuple[str, str]] = []
    for element in root.iter():
        tag = element.tag.removeprefix(SVG_NS)
        if tag not in ALLOWED_TAGS or "style" in element.attrib:
            raise ValueError(f"Unsupported SVG tag or inline style: {tag}")
        for attribute, value in element.attrib.items():
            if attribute.lower().startswith("on"):
                raise ValueError("Event-handler attributes are not supported")
            if attribute.endswith("href") and not value.startswith("#"):
                raise ValueError("Only internal SVG references are supported")
        if tag != "style":
            continue
        css = element.text or ""
        position = 0
        while css[position:].strip():
            match = CSS_RULE.match(css, position)
            if match is None:
                raise ValueError(f"Unsupported stylesheet at offset {position}")
            value = match[2].strip()
            if not FILL_VALUE.fullmatch(value):
                raise ValueError(f"Unsupported fill value: {value}")
            rules.append((match[1], value))
            position = match.end()
    if not rules:
        raise ValueError("Expected at least one simple class fill rule")

    def fill_for(classes: str) -> str:
        names = set(classes.split())
        known = {name for name, _ in rules}
        if not names or not names <= known:
            raise ValueError(f"Unknown SVG class: {classes}")
        # All accepted selectors have equal specificity: stylesheet order wins.
        return next(value for name, value in reversed(rules) if name in names)

    def replace_tag(match: re.Match[str]) -> str:
        tag = match[0]
        attributes = list(ATTRIBUTE.finditer(tag))
        class_attribute = next((item for item in attributes if item[1] == "class"), None)
        if class_attribute is None:
            return tag
        classes = class_attribute[2][1:-1]
        fill = f"fill={quoteattr(fill_for(classes))}"
        existing = next((item for item in attributes if item[1] == "fill"), None)
        if existing is not None:
            tag = tag[:existing.start()] + fill + tag[existing.end():]
            # Recompute offsets if replacing fill changed the tag's length.
            class_attribute = next(item for item in ATTRIBUTE.finditer(tag) if item[1] == "class")
            return tag[:class_attribute.start()] + tag[class_attribute.end():]
        # Replace the no-longer-needed class attribute with the computed fill.
        return tag[:class_attribute.start()] + fill + tag[class_attribute.end():]

    converted = OPEN_TAG.sub(replace_tag, text)
    converted, removed_styles = STYLE_ELEMENT.subn("", converted)
    expected_styles = sum(element.tag == f"{SVG_NS}style" for element in root.iter())
    if removed_styles != expected_styles:
        raise ValueError("Could not remove every expanded stylesheet")
    result = converted.encode("utf-8")
    after = ET.fromstring(result)

    # Prepare the only allowed structural changes: remove expanded styles and
    # classes, add equivalent fill values, preserving surrounding XML text.
    for parent in list(root.iter()):
        previous = None
        for child in list(parent):
            if child.tag == f"{SVG_NS}style":
                if child.tail:
                    if previous is None:
                        parent.text = (parent.text or "") + child.tail
                    else:
                        previous.tail = (previous.tail or "") + child.tail
                parent.remove(child)
            else:
                previous = child
    for element in root.iter():
        if "class" in element.attrib:
            element.set("fill", fill_for(element.attrib.pop("class")))
    before_nodes, after_nodes = list(root.iter()), list(after.iter())
    if len(before_nodes) != len(after_nodes):
        raise ValueError("SVG structure changed during conversion")
    for before, current in zip(before_nodes, after_nodes, strict=True):
        if (before.tag, before.text, before.tail, before.attrib) != (
            current.tag, current.text, current.tail, current.attrib
        ):
            raise ValueError("Conversion changed more than expanded class fills and removed CSS")
    return result


def load_assets(source_zip: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(source_zip) as archive:
        entries = archive.infolist()
        if len(entries) != 54:
            raise ValueError(f"Expected 54 SVG files, found {len(entries)}")
        names = [entry.filename for entry in entries]
        if len(set(names)) != len(names):
            raise ValueError("ZIP contains duplicate filenames")
        if any(not FILE_NAME.fullmatch(name) for name in names):
            raise ValueError("ZIP must contain only flat metro_logo_[a-z]+.svg entries")
        if any(entry.file_size > 100_000 or entry.is_dir() for entry in entries):
            raise ValueError("Invalid SVG entry size or type")
        return {entry.filename: expand_fills(archive.read(entry)) for entry in entries}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_zip", type=Path)
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[1] / "assets" / "metro")
    parser.add_argument("--check", action="store_true", help="Verify assets without writing")
    args = parser.parse_args()
    assets = load_assets(args.source_zip)
    output = args.output.resolve()
    if args.check:
        if not output.is_dir() or {p.name for p in output.iterdir()} != set(assets):
            raise ValueError("Asset directory does not contain exactly the source SVG set")
        for name, data in assets.items():
            if (output / name).read_bytes() != data:
                raise ValueError(f"Asset differs from normalized source: {name}")
        print(f"Verified {len(assets)} reproducible SVG assets without writing")
        return
    if output.exists() and any(p.name not in assets or not p.is_file() for p in output.iterdir()):
        raise ValueError("Output contains unrelated entries; refusing to overwrite them")
    output.mkdir(parents=True, exist_ok=True)
    for name, data in assets.items():
        (output / name).write_bytes(data)
    print(f"Imported {len(assets)} SVG assets into {output}")


if __name__ == "__main__":
    main()
