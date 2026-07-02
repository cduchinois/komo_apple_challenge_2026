#!/usr/bin/env python3
"""Add machine translations to Komo String Catalogs (.xcstrings)."""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

from deep_translator import GoogleTranslator, MyMemoryTranslator

ROOT = Path(__file__).resolve().parents[1]

# Apple String Catalog locale → (MyMemory source, MyMemory target) or None = copy en
LOCALES: dict[str, tuple[str, str] | None] = {
    "fr": ("en-GB", "fr-FR"),
    "es": ("en-GB", "es-ES"),
    "de": ("en-GB", "de-DE"),
    "pt": ("en-GB", "pt-PT"),
    "ja": ("en-GB", "ja-JP"),
    "zh-Hans": ("en-GB", "zh-CN"),
    "it": ("en-GB", "it-IT"),
    "en-GB": None,
    "en-AU": None,
}

CATALOGS = [
    ROOT / "Komo/Resources/Localizable.xcstrings",
    ROOT / "KomoWidget/Localizable.xcstrings",
    ROOT / "Komo/Resources/InfoPlist.xcstrings",
]

PH_RE = re.compile(r"(%(?:\d+\$)?[@lldf%]+)")
KOMO_RE = re.compile(r"\b(KOMO|Komo|komo)\b")


def protect(text: str) -> tuple[str, list[str], list[str]]:
    placeholders: list[str] = []

    def ph_sub(m: re.Match[str]) -> str:
        placeholders.append(m.group(1))
        return f"__PH{len(placeholders) - 1}__"

    protected = PH_RE.sub(ph_sub, text)
    komo_tokens: list[str] = []

    def komo_sub(m: re.Match[str]) -> str:
        komo_tokens.append(m.group(1))
        return f"__KOMO{len(komo_tokens) - 1}__"

    protected = KOMO_RE.sub(komo_sub, protected)
    return protected, placeholders, komo_tokens


def restore(text: str, placeholders: list[str], komo_tokens: list[str]) -> str:
    for i, token in enumerate(komo_tokens):
        text = text.replace(f"__KOMO{i}__", token)
    for i, ph in enumerate(placeholders):
        text = text.replace(f"__PH{i}__", ph)
    return text


def english_source(key: str, entry: dict) -> str | None:
    locs = entry.get("localizations") or {}
    if "en" in locs:
        value = locs["en"]["stringUnit"]["value"]
        if value.strip():
            return value
    if key.strip():
        return key
    return None


def translate(text: str, mm_source: str, mm_target: str, cache: dict[tuple[str, str], str]) -> str:
    cache_key = (mm_target, text)
    if cache_key in cache:
        return cache[cache_key]

    protected, placeholders, komo_tokens = protect(text)

    google_target = mm_target.split("-")[0]
    if google_target == "zh":
        google_target = "zh-CN"

    for attempt in range(3):
        try:
            translated = GoogleTranslator(source="en", target=google_target).translate(protected)
            if translated:
                result = restore(translated, placeholders, komo_tokens)
                cache[cache_key] = result
                time.sleep(0.02)
                return result
        except Exception:
            time.sleep(0.3 * (attempt + 1))

    try:
        translated = MyMemoryTranslator(source=mm_source, target=mm_target).translate(protected)
        result = restore(translated or text, placeholders, komo_tokens)
        cache[cache_key] = result
        return result
    except Exception:
        cache[cache_key] = text
        return text


def process_catalog(path: Path, cache: dict[tuple[str, str], str], force: bool) -> int:
    with path.open(encoding="utf-8") as f:
        data = json.load(f)

    strings = data.setdefault("strings", {})
    added = 0
    total_keys = len([k for k in strings if k.strip()])

    for idx, (key, entry) in enumerate(strings.items(), start=1):
        source = english_source(key, entry)
        if source is None:
            continue

        locs = entry.setdefault("localizations", {})
        if "en" not in locs:
            locs["en"] = {"stringUnit": {"state": "translated", "value": source}}

        for locale, mm_pair in LOCALES.items():
            if not force and locale in locs:
                continue

            if mm_pair is None:
                value = locs["en"]["stringUnit"]["value"]
            else:
                mm_source, mm_target = mm_pair
                value = translate(source, mm_source, mm_target, cache)

            locs[locale] = {"stringUnit": {"state": "translated", "value": value}}
            added += 1

        if idx % 20 == 0:
            print(f"  …{idx}/{total_keys} keys", flush=True)
            with path.open("w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
                f.write("\n")

    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    return added


def main() -> None:
    force = "--force" in sys.argv
    cache: dict[tuple[str, str], str] = {}
    total = 0

    for catalog in CATALOGS:
        if not catalog.exists():
            print(f"skip missing {catalog}")
            continue
        print(f"Processing {catalog.name}…", flush=True)
        count = process_catalog(catalog, cache, force)
        print(f"  +{count} locale entries", flush=True)
        total += count

    print(f"Done. {total} entries written.", flush=True)


if __name__ == "__main__":
    main()
