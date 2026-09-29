"""Рабочий инструмент переводчиков: выгрузка строк, сборка .po из частей и проверка.

    python tools/i18n_work.py export            # locale/work/source.json: [{i, ru, en, where}]
    python tools/i18n_work.py build <код>       # locale/work/<код>/*.json ({"i": перевод}) -> locale/<код>.po + проверка
    python tools/i18n_work.py check <код>       # проверить готовый locale/<код>.po

Проверка: переведены все строки; в переводе те же плейсхолдеры (%d, %s, %.2f, %%, {name}; %-плейсхолдеры —
в том же порядке, т.к. Godot подставляет их по позиции), те же BBCode-теги
([color=…], [i], [/color]…) и столько же переносов строк, что и в исходнике.
"""
import glob
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import i18n_extract as extract  # noqa: E402

WORK = os.path.join(ROOT, "locale", "work")
PLACEHOLDER = re.compile(r"%[-+0#]*\d*(?:\.\d+)?[dsfx%]|\{\w+\}")
BBCODE = re.compile(r"\[/?[a-z]+(?:=[^\]]*)?\]")
# Строки, которые не переводятся (название языка — на нём самом).
KEEP_AS_IS = {"Русский", "Українська"}


def messages():
    return sorted(extract.collect())


def export():
    os.makedirs(WORK, exist_ok=True)
    english = extract.read_po(os.path.join(ROOT, "locale", "en.po"))
    all_messages = extract.collect()
    items = []
    for index, msgid in enumerate(sorted(all_messages)):
        items.append({"i": index, "ru": msgid, "en": english.get(msgid, ""), "where": sorted(all_messages[msgid])[0]})
    io.open(os.path.join(WORK, "source.json"), "w", encoding="utf8").write(json.dumps(items, ensure_ascii=False, indent=1))
    print("exported %d strings to locale/work/source.json" % len(items))


def problems(msgid, text):
    found = []
    if msgid in KEEP_AS_IS:
        return found
    if not text:
        return ["empty"]
    if sorted(PLACEHOLDER.findall(msgid)) != sorted(PLACEHOLDER.findall(text)):
        found.append("placeholders %s vs %s" % (PLACEHOLDER.findall(msgid), PLACEHOLDER.findall(text)))
    else:
        # %-плейсхолдеры Godot подставляет строго по порядку — переставлять их нельзя ({name} — можно).
        positional = lambda s: [p for p in PLACEHOLDER.findall(s) if p.startswith("%") and p != "%%"]
        if positional(msgid) != positional(text):
            found.append("placeholder order %s vs %s" % (positional(msgid), positional(text)))
    if sorted(BBCODE.findall(msgid)) != sorted(BBCODE.findall(text)):
        found.append("bbcode differs")
    if msgid.count("\n") != text.count("\n"):
        found.append("line breaks %d vs %d" % (msgid.count("\n"), text.count("\n")))
    return found


def build(code):
    source = json.load(io.open(os.path.join(WORK, "source.json"), encoding="utf8"))
    by_index = {item["i"]: item["ru"] for item in source}
    translations = {}
    for path in sorted(glob.glob(os.path.join(WORK, code, "*.json"))):
        chunk = json.load(io.open(path, encoding="utf8"))
        for key, text in chunk.items():
            index = int(key)
            if index in by_index:
                translations[by_index[index]] = text
    # Сохраняем уже готовые переводы из существующего .po (если собираем повторно).
    po_path = os.path.join(ROOT, "locale", code + ".po")
    existing = extract.read_po(po_path)
    for msgid, text in existing.items():
        translations.setdefault(msgid, text)
    extract.write_po(po_path, extract.collect(), translations, code)
    report(code)


def report(code):
    po = extract.read_po(os.path.join(ROOT, "locale", code + ".po"))
    source = json.load(io.open(os.path.join(WORK, "source.json"), encoding="utf8")) if os.path.exists(os.path.join(WORK, "source.json")) else None
    index_of = {item["ru"]: item["i"] for item in source} if source else {}
    bad = []
    for msgid in messages():
        issues = problems(msgid, po.get(msgid, ""))
        if issues:
            bad.append((index_of.get(msgid, "?"), issues))
    print("%s: %d strings, %d with problems" % (code, len(messages()), len(bad)))
    for index, issues in bad[:60]:
        print("  #%s: %s" % (index, "; ".join(issues)))
    return len(bad)


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "export":
        export()
    elif command == "build" and len(sys.argv) > 2:
        build(sys.argv[2])
    elif command == "check" and len(sys.argv) > 2:
        sys.exit(1 if report(sys.argv[2]) else 0)
    else:
        print(__doc__)
