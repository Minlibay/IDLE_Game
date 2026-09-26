"""Собирает все русские строки игры и обновляет файлы переводов.

    python tools/i18n_extract.py

Ключ перевода — сама русская строка (так её ищет tr() / TranslationServer.translate()).
Откуда берутся строки:
  * .gd (scenes/, scripts/) — строковые литералы с кириллицей (вне комментариев);
  * .tscn / .tres — тексты узлов и данные (имена, описания);
  * data/treasures/*.json — каталог сокровищ, включая составные имена частей сетов («<слот> <of>»);
  * data/guild/*.json — бонусы гильдий и названия регионов;
  * server/src — ошибки и шаблоны отчётов, которые сервер присылает клиенту.

Результат: locale/messages.pot (все ключи) и locale/<язык>.po для каждого языка из LANGUAGES:
новые ключи добавляются с пустым переводом, старые переводы сохраняются, исчезнувшие ключи удаляются.
Пустой перевод = в игре остаётся русский текст.
"""
import glob
import io
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGUAGES = ["en"]
CYR = re.compile(r"[А-Яа-яЁё]")
CODE_LITERAL = re.compile(r'(?<![&^\w])"((?:[^"\\\n]|\\.)*)"')
RESOURCE_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"', re.S)
ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}


def unescape_code(text):
    return re.sub(r"\\(.)", lambda m: ESCAPES.get(m.group(1), "\\" + m.group(1)), text)


def unescape_resource(text):
    return text.replace('\\"', '"').replace("\\\\", "\\")


def strip_comments(source, marker):
    lines = []
    for line in source.split("\n"):
        stripped = line.strip()
        if stripped.startswith(marker) or stripped.startswith("*") or stripped.startswith("/*"):
            lines.append("")
        else:
            lines.append(line)
    return "\n".join(lines)


def collect():
    messages = {}  # msgid -> set of files

    def add(text, where):
        if CYR.search(text):
            messages.setdefault(text, set()).add(where)

    for path in glob.glob(os.path.join(ROOT, "scenes", "**", "*.gd"), recursive=True) + \
            glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True):
        source = strip_comments(io.open(path, encoding="utf8").read(), "#")
        for m in CODE_LITERAL.finditer(source):
            add(unescape_code(m.group(1)), rel(path))
    for path in glob.glob(os.path.join(ROOT, "scenes", "**", "*.tscn"), recursive=True) + \
            glob.glob(os.path.join(ROOT, "data", "**", "*.tres"), recursive=True):
        for m in RESOURCE_LITERAL.finditer(io.open(path, encoding="utf8").read()):
            add(unescape_resource(m.group(1)), rel(path))
    for path in glob.glob(os.path.join(ROOT, "data", "treasures", "*.json")):
        data = json.load(io.open(path, encoding="utf8"))
        walk_json(data, lambda text: add(text, rel(path)))
        slot_names = data.get("slot_names", {})
        for entry in data.get("sets", []):
            for slot in ["helmet", "shoulders", "armor", "legs", "boots"]:
                add("%s %s" % (slot_names.get(slot, slot), entry["of"]), rel(path))
    for path in glob.glob(os.path.join(ROOT, "data", "guild", "*.json")):
        walk_json(json.load(io.open(path, encoding="utf8")), lambda text: add(text, rel(path)))
    for path in glob.glob(os.path.join(ROOT, "server", "src", "**", "*.ts"), recursive=True):
        if path.endswith(".test.ts"):
            continue
        source = strip_comments(io.open(path, encoding="utf8").read(), "//")
        for m in CODE_LITERAL.finditer(source):
            add(unescape_code(m.group(1)), rel(path))
    return messages


def walk_json(value, add):
    if isinstance(value, str):
        add(value)
    elif isinstance(value, list):
        for item in value:
            walk_json(item, add)
    elif isinstance(value, dict):
        for item in value.values():
            walk_json(item, add)


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def po_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def read_po(path):
    """msgid -> msgstr из существующего .po."""
    result = {}
    if not os.path.exists(path):
        return result
    current = None
    msgid = msgstr = ""
    for line in io.open(path, encoding="utf8").read().split("\n"):
        line = line.strip()
        if line.startswith("msgid "):
            if current == "msgstr":
                result[msgid] = msgstr
            msgid, msgstr, current = unescape_code(line[7:-1]), "", "msgid"
        elif line.startswith("msgstr "):
            msgstr, current = unescape_code(line[8:-1]), "msgstr"
        elif line.startswith('"') and current:
            if current == "msgid":
                msgid += unescape_code(line[1:-1])
            else:
                msgstr += unescape_code(line[1:-1])
    if current == "msgstr":
        result[msgid] = msgstr
    result.pop("", None)
    return result


def write_po(path, messages, translations, language):
    out = ['msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"']
    if language:
        out.append('"Language: %s\\n"' % language)
    for msgid in sorted(messages):
        out.append("")
        out.append("#: " + " ".join(sorted(messages[msgid])))
        out.append('msgid "%s"' % po_escape(msgid))
        out.append('msgstr "%s"' % po_escape(translations.get(msgid, "")))
    io.open(path, "w", encoding="utf8", newline="\n").write("\n".join(out) + "\n")


def main():
    messages = collect()
    os.makedirs(os.path.join(ROOT, "locale"), exist_ok=True)
    write_po(os.path.join(ROOT, "locale", "messages.pot"), messages, {}, "")
    for language in LANGUAGES:
        path = os.path.join(ROOT, "locale", language + ".po")
        translations = read_po(path)
        write_po(path, messages, translations, language)
        missing = [m for m in messages if not translations.get(m)]
        print("%s: %d strings, %d untranslated" % (language, len(messages), len(missing)))


if __name__ == "__main__":
    main()
