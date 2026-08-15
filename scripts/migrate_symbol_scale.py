#!/usr/bin/env python3
"""One-time migration for the original 6x symbol workflow.

The old workflow scaled source layers by 6 in SVG *and* scaled copied symbols by
6 again. This migration bakes the source-layer scale into geometry while
preserving stroke widths, and removes the redundant scale from existing
library symbols.

Safe to rerun: already-migrated files are skipped.
"""
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

FACTOR = 6.0
ROOT = Path(__file__).resolve().parent.parent
SVG = "http://www.w3.org/2000/svg"
INK = "http://www.inkscape.org/namespaces/inkscape"
SOD = "http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
ET.register_namespace("", SVG)
ET.register_namespace("inkscape", INK)
ET.register_namespace("sodipodi", SOD)

NUMBER_RE = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")
LENGTH_RE = re.compile(r"^\s*([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)([A-Za-z%]*)\s*$")
SCALE_RE = re.compile(r"^\s*scale\(\s*6(?:\.0+)?\s*\)\s*$")
TRANSLATE_RE = re.compile(r"^\s*translate\(\s*([^, )]+)\s*(?:[, ]\s*([^ )]+))?\s*\)\s*$")

COORD_ATTRS = {
    "circle": ("cx", "cy", "r"),
    "ellipse": ("cx", "cy", "rx", "ry"),
    "rect": ("x", "y", "width", "height", "rx", "ry"),
    "line": ("x1", "y1", "x2", "y2"),
    "text": ("x", "y", "dx", "dy"),
    "tspan": ("x", "y", "dx", "dy"),
    "use": ("x", "y", "width", "height"),
    "image": ("x", "y", "width", "height"),
}
STYLE_LENGTHS = {"font-size", "letter-spacing", "word-spacing", "stroke-dashoffset"}
STYLE_LISTS = {"stroke-dasharray"}


def fmt(value: float) -> str:
    out = f"{value:.9f}".rstrip("0").rstrip(".")
    return "0" if out in {"-0", ""} else out


def scale_length(value: str, factor: float) -> str:
    match = LENGTH_RE.match(value)
    if not match:
        return value
    return fmt(float(match.group(1)) * factor) + match.group(2)


def scale_numbers(value: str, factor: float) -> str:
    return NUMBER_RE.sub(lambda m: fmt(float(m.group(0)) * factor), value)


def scale_style(style: str, factor: float) -> str:
    chunks: list[str] = []
    for chunk in style.split(";"):
        if not chunk.strip() or ":" not in chunk:
            if chunk.strip():
                chunks.append(chunk.strip())
            continue
        key, value = (part.strip() for part in chunk.split(":", 1))
        if key in STYLE_LENGTHS:
            value = scale_length(value, factor)
        elif key in STYLE_LISTS and value.lower() != "none":
            value = scale_numbers(value, factor)
        # Intentionally do NOT scale stroke-width.
        chunks.append(f"{key}:{value}")
    return ";".join(chunks)


def scale_translate(transform: str, factor: float) -> str:
    match = TRANSLATE_RE.match(transform)
    if not match:
        return transform
    x = fmt(float(match.group(1)) * factor)
    if match.group(2) is None:
        return f"translate({x})"
    y = fmt(float(match.group(2)) * factor)
    return f"translate({x},{y})"


def bake_element(el: ET.Element, factor: float) -> None:
    tag = el.tag.split("}")[-1]

    if tag == "path" and "d" in el.attrib:
        # The bundled sources contain M/L/H/V/C/Z paths. Arc flags cannot be
        # scaled as ordinary numbers, so fail loudly if an arc ever appears.
        if re.search(r"[Aa]", el.attrib["d"]):
            raise RuntimeError("Arc path encountered during one-time migration")
        el.set("d", scale_numbers(el.attrib["d"], factor))
    elif tag in {"polyline", "polygon"} and "points" in el.attrib:
        el.set("points", scale_numbers(el.attrib["points"], factor))

    for attr in COORD_ATTRS.get(tag, ()):
        if attr in el.attrib:
            el.set(attr, scale_length(el.attrib[attr], factor))

    transform = el.get("transform")
    if transform:
        el.set("transform", scale_translate(transform, factor))

    if "style" in el.attrib:
        el.set("style", scale_style(el.attrib["style"], factor))
    if "font-size" in el.attrib:
        el.set("font-size", scale_length(el.attrib["font-size"], factor))

    for child in list(el):
        bake_element(child, factor)


def migrate_source(path: Path) -> bool:
    tree = ET.parse(path)
    root = tree.getroot()
    changed = False

    for child in list(root):
        transform = child.get("transform")
        if transform and SCALE_RE.match(transform):
            child.attrib.pop("transform", None)
            for descendant in list(child):
                bake_element(descendant, FACTOR)
            changed = True

    if changed:
        tree.write(path, encoding="utf-8", xml_declaration=True)
    return changed


def divide_root_length(root: ET.Element, attr: str, factor: float) -> None:
    if attr in root.attrib:
        root.set(attr, scale_length(root.attrib[attr], 1.0 / factor))


def migrate_library(path: Path) -> bool:
    tree = ET.parse(path)
    root = tree.getroot()
    symbol = None
    for el in root.iter():
        if el.get("id") == "symbol":
            symbol = el
            break

    if symbol is None or not SCALE_RE.match(symbol.get("transform", "")):
        return False

    symbol.attrib.pop("transform", None)
    divide_root_length(root, "width", FACTOR)
    divide_root_length(root, "height", FACTOR)

    if "viewBox" in root.attrib:
        nums = root.attrib["viewBox"].replace(",", " ").split()
        if len(nums) == 4:
            root.set("viewBox", " ".join(fmt(float(n) / FACTOR) for n in nums))

    tree.write(path, encoding="utf-8", xml_declaration=True)
    return True


def main() -> int:
    sources = [ROOT / "templates" / "noah-symbol-sheet.svg"]
    sources += sorted((ROOT / "symbols" / "_sources").rglob("*.svg"))
    library = sorted(
        p for p in (ROOT / "symbols").rglob("*.svg")
        if "_sources" not in p.parts
    )

    source_count = sum(migrate_source(path) for path in sources)
    library_count = sum(migrate_library(path) for path in library)
    print(f"Migrated {source_count} source/template SVGs and {library_count} library SVGs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
