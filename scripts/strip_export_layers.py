#!/usr/bin/env python3
"""Create an export-only SVG copy with non-exporting Inkscape layers removed."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SVG_NS = "http://www.w3.org/2000/svg"
INKSCAPE_NS = "http://www.inkscape.org/namespaces/inkscape"
LABEL = f"{{{INKSCAPE_NS}}}label"
GROUPMODE = f"{{{INKSCAPE_NS}}}groupmode"

# Keep familiar prefixes in the temporary SVG rather than ns0/ns1.
ET.register_namespace("", SVG_NS)
ET.register_namespace("inkscape", INKSCAPE_NS)
ET.register_namespace("sodipodi", "http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd")
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")

DASHES = "\u2010\u2011\u2012\u2013\u2014\u2212"


def normalize_label(value: str) -> str:
    value = value.strip().upper()
    value = re.sub(f"[{DASHES}]", "-", value)
    value = re.sub(r"\s*-\s*", " - ", value)
    value = re.sub(r"\s+", " ", value)
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument(
        "--exclude-layer",
        action="append",
        default=[],
        help="Inkscape layer label to remove; may be supplied more than once",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    excludes = args.exclude_layer or ["10 - GUIDES"]
    wanted = {normalize_label(item) for item in excludes}

    try:
        tree = ET.parse(args.source)
    except (OSError, ET.ParseError) as exc:
        print(f"Could not parse SVG: {exc}", file=sys.stderr)
        return 2

    root = tree.getroot()
    removed: list[str] = []

    # ElementTree has no parent pointers, so inspect each parent's direct children.
    for parent in root.iter():
        for child in list(parent):
            if child.tag != f"{{{SVG_NS}}}g":
                continue
            if child.attrib.get(GROUPMODE) != "layer":
                continue

            label = child.attrib.get(LABEL, "")
            if normalize_label(label) in wanted:
                parent.remove(child)
                removed.append(label)

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        tree.write(args.destination, encoding="utf-8", xml_declaration=True)
    except OSError as exc:
        print(f"Could not write export SVG: {exc}", file=sys.stderr)
        return 3

    if removed:
        print("Removed export-only layer(s): " + ", ".join(removed))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
