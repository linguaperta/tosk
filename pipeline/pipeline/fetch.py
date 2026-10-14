"""`python -m pipeline fetch`: download the open-data sources into the cache.

Large dumps are streamed over HTTP and filtered line by line, so the multi-GB raw files never
touch the disk. Only small filtered JSONL files are kept:

  kaikki-it.jsonl     Italian lemma entries (en.wiktionary via kaikki.org), words in the freq list
  kaikki-nl.jsonl     Dutch lemma entries, same filter
  kaikki-{code}.jsonl     the same for every other course language in SOURCES (es, ...)
  kaikki-nlwikt-{code}.jsonl  the course language's entries in the Dutch Wiktionary (Dutch glosses)
  en-trans-it-nl.jsonl    English Wiktionary translation tables that list both it and nl words (Italian)
  en-trans-nl.jsonl       the same for every PIVOT_CODES language: one pass over the English dump keeps
                          every sense that lists a Dutch word and a word in any of them
  nlwikt-nl-aux.jsonl     Dutch verbs from the Dutch Wiktionary: perfect auxiliary (hebben/zijn)
  tatoeba/*.tsv.bz2   Tatoeba per-language sentence and link exports (small, kept compressed)
  freq/{it,nl}_50k.txt  hermitdave/FrequencyWords 2018 lists
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import Callable, Iterable, Iterator

import requests

from .paths import cache_dir

# Per course language: kaikki.org (en.wiktionary) language name, Tatoeba ISO 639-3 code,
# nl.wiktionary language name (Dutch glosses; None for Dutch itself), FrequencyWords code.
# Adding a language starts with one line here (docs/new-language.md).
SOURCES: dict[str, dict[str, str | None]] = {
    "it": {"kaikki": "Italian", "tatoeba": "ita", "nlwikt": "Italiaans", "freq": "it"},
    "nl": {"kaikki": "Dutch", "tatoeba": "nld", "nlwikt": None, "freq": "nl"},
    "es": {"kaikki": "Spanish", "tatoeba": "spa", "nlwikt": "Spaans", "freq": "es"},
    "pt": {"kaikki": "Portuguese", "tatoeba": "por", "nlwikt": "Portugees", "freq": "pt"},
    "fr": {"kaikki": "French", "tatoeba": "fra", "nlwikt": "Frans", "freq": "fr"},
    "eo": {"kaikki": "Esperanto", "tatoeba": "epo", "nlwikt": "Esperanto", "freq": "eo"},
    "sv": {"kaikki": "Swedish", "tatoeba": "swe", "nlwikt": "Zweeds", "freq": "sv"},
    "nb": {"kaikki": "Norwegian Bokmål", "tatoeba": "nob", "nlwikt": "Noors", "freq": "no"},
    "da": {"kaikki": "Danish", "tatoeba": "dan", "nlwikt": "Deens", "freq": "da"},
}
# translation-table codes kept by the English pivot pass (en-trans-nl.jsonl); 'no' is how
# en.wiktionary often tags Norwegian without a Bokmål/Nynorsk split
PIVOT_CODES = ("it", "es", "pt", "fr", "eo", "sv", "nb", "no", "da")


def kaikki_url(code: str) -> str:
    name = SOURCES[code]["kaikki"]
    return f"https://kaikki.org/dictionary/{name}/kaikki.org-dictionary-{name.replace(' ', '')}.jsonl".replace(" ", "%20")


def nlwikt_url(name: str) -> str:
    return f"https://kaikki.org/nlwiktionary/{name}/kaikki.org-dictionary-{name}.jsonl"


KAIKKI_EN = "https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl"
NLWIKT_NL = nlwikt_url("Nederlands")
FREQ_BASE = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/"
TATOEBA_BASE = "https://downloads.tatoeba.org/exports/per_language/"


def tatoeba_files(code: str) -> list[str]:
    """The language's sentences and English links, plus its Dutch links (not for Dutch itself)."""
    t3 = SOURCES[code]["tatoeba"]
    out = [f"{t3}/{t3}_sentences.tsv.bz2", f"{t3}/{t3}-eng_links.tsv.bz2", "eng/eng_sentences.tsv.bz2"]
    if code != "nl":
        out += [f"{t3}/{t3}-nld_links.tsv.bz2", "nld/nld_sentences.tsv.bz2"]
    return out

SKIP_POS = {"name", "character", "symbol", "suffix", "prefix", "infix", "interfix", "affix",
            "romanization", "punct", "abbrev", "letter", "proverb", "combining_form"}
KEEP_KEYS = ("word", "pos", "etymology_number", "head_templates", "forms", "senses", "lang_code")


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _stream_lines(url: str) -> Iterator[bytes]:
    with requests.get(url, stream=True, timeout=120) as r:
        r.raise_for_status()
        total = int(r.headers.get("content-length") or 0)
        done = 0
        last = time.time()
        buf = b""
        for chunk in r.iter_content(chunk_size=1 << 20):
            done += len(chunk)
            buf += chunk
            *lines, buf = buf.split(b"\n")
            yield from lines
            if time.time() - last > 15:
                last = time.time()
                pct = f"{100 * done / total:.0f}%" if total else f"{done >> 20} MB"
                log(f"    {url.rsplit('/', 1)[-1]}: {pct}")
        if buf:
            yield buf


def _download(url: str, dest: Path, force: bool = False) -> Path:
    if dest.exists() and not force:
        log(f"  cached {dest.name}")
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    log(f"  downloading {url}")
    with requests.get(url, stream=True, timeout=120) as r:
        r.raise_for_status()
        with open(tmp, "wb") as f:
            for chunk in r.iter_content(chunk_size=1 << 20):
                f.write(chunk)
    tmp.replace(dest)
    return dest


def _filter_to(url: str, dest: Path, keep: Callable[[dict], dict | None], prefilter: Callable[[bytes], bool] | None = None,
               force: bool = False) -> Path:
    if dest.exists() and not force:
        log(f"  cached {dest.name}")
        return dest
    log(f"  streaming + filtering {url}")
    tmp = dest.with_suffix(dest.suffix + ".part")
    n_in = n_out = 0
    with open(tmp, "w", encoding="utf-8", newline="\n") as out:
        for line in _stream_lines(url):
            n_in += 1
            if prefilter and not prefilter(line):
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            rec = keep(e)
            if rec is not None:
                out.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
                n_out += 1
    tmp.replace(dest)
    log(f"  kept {n_out} of {n_in} lines -> {dest.name}")
    return dest


def load_freq_words(path: Path) -> list[tuple[str, int]]:
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2 and parts[1].isdigit():
                out.append((parts[0], int(parts[1])))
    return out


def _is_form_of_only(e: dict) -> bool:
    senses = e.get("senses") or []
    if not senses:
        return True
    for s in senses:
        tags = s.get("tags") or []
        if not (s.get("form_of") or "form-of" in tags or "alt-of" in tags or s.get("alt_of")):
            return False
    return True


def kaikki_keep(words: set[str], lang_code: str) -> Callable[[dict], dict | None]:
    def keep(e: dict) -> dict | None:
        if e.get("lang_code") != lang_code or e.get("pos") in SKIP_POS:
            return None
        w = e.get("word") or ""
        lw = w.lower()
        if lw not in words:
            parts = lw.replace("'", "' ").split()
            if not (1 < len(parts) <= 4 and all(p in words for p in parts)):
                return None
        if _is_form_of_only(e):
            return None
        rec = {k: e[k] for k in KEEP_KEYS if k in e}
        rec["senses"] = [
            {k: s[k] for k in ("glosses", "tags", "form_of", "alt_of") if k in s} for s in e.get("senses", [])
        ]
        rec["head_templates"] = [{k: h.get(k) for k in ("name", "args", "expansion")} for h in e.get("head_templates", [])]
        forms = []
        for f in e.get("forms", []):
            g = {"form": f.get("form"), "tags": f.get("tags", [])}
            if f.get("source"):
                g["source"] = f["source"]
            links = f.get("links")
            if links and isinstance(links[0], list) and len(links[0]) > 1:
                g["link"] = links[0][1].split("#", 1)[0]
            forms.append(g)
        rec["forms"] = forms
        return rec
    return keep


def nlwikt_keep(code: str, words: set[str] | None = None) -> Callable[[dict], dict | None]:
    """The course language's entries in the Dutch Wiktionary: word, pos, glosses (Dutch); only words
    in the frequency list when `words` is given (the Spanish dump has ~200k entries)."""
    def keep(e: dict) -> dict | None:
        if e.get("lang_code") != code or (words is not None and (e.get("word") or "").lower() not in words):
            return None
        return _nlwikt_rec(e)
    return keep


def _nlwikt_rec(e: dict) -> dict | None:
    senses = [{"glosses": s.get("glosses", []), "tags": s.get("tags", [])} for s in e.get("senses", [])
              if s.get("glosses")]
    if not senses:
        return None
    return {"word": e.get("word"), "pos": e.get("pos"), "senses": senses}


def nlwikt_aux_keep(e: dict) -> dict | None:
    """Dutch verbs from the Dutch Wiktionary: perfect auxiliary (hebben/zijn) per verb.

    en.wiktionary's Dutch tables (kaikki) do not carry the auxiliary; nl.wiktionary's
    'vervoeging' tables list the perfect forms ('heb gewerkt', 'ben gegaan').
    """
    if e.get("lang_code") != "nl" or e.get("pos") != "verb":
        return None
    aux: list[str] = []
    participle = None
    for f in e.get("forms") or []:
        tags = set(f.get("tags") or [])
        form = f.get("form") or ""
        if {"perfect", "present", "first-person"} <= tags and "past" not in tags:
            first = form.split(" ", 1)[0]
            a = {"heb": "hebben", "ben": "zijn"}.get(first)
            if a and a not in aux:
                aux.append(a)
        if {"past", "participle"} <= tags and participle is None:
            participle = form
    if not aux:
        return None
    return {"word": e.get("word"), "aux": aux, "participle": participle}


def en_trans_keep(e: dict, codes: tuple[str, ...] = ("it",)) -> dict | None:
    """Senses of an English entry whose translation table lists a Dutch word and a word in one of
    `codes` (the Dutch pivot): {"word", "pos", "senses": [{"sense", "nl": [...], "<code>": [...]}]}."""
    trs = list(e.get("translations") or [])
    for s in e.get("senses") or []:
        trs.extend(s.get("translations") or [])
    by_sense: dict[str, dict[str, list[str]]] = {}
    wanted = set(codes) | {"nl"}
    for t in trs:
        code = t.get("code") or t.get("lang_code")
        if code not in wanted or not t.get("word"):
            continue
        d = by_sense.setdefault(t.get("sense") or "", {})
        lst = d.setdefault(code, [])
        if t["word"] not in lst:
            lst.append(t["word"])
    senses = [{"sense": k, **v} for k, v in by_sense.items() if v.get("nl") and len(v) > 1]
    if not senses:
        return None
    return {"word": e.get("word"), "pos": e.get("pos"), "senses": senses}


def fetch(langs: Iterable[str] = ("it", "nl"), force: bool = False, skip_english: bool = False) -> None:
    c = cache_dir()
    log(f"cache: {c}")
    langs = list(langs)
    unknown = [x for x in langs if x not in SOURCES]
    if unknown:
        raise SystemExit(f"no sources configured for {unknown}: add them to fetch.SOURCES")
    freq_words: dict[str, set[str]] = {}
    for lang in langs:
        fc = SOURCES[lang]["freq"]
        p = _download(f"{FREQ_BASE}{fc}/{fc}_50k.txt", c / "freq" / f"{lang}_50k.txt", force)
        freq_words[lang] = {w.lower() for w, _ in load_freq_words(p)}
    for f in dict.fromkeys(f for lang in langs for f in tatoeba_files(lang)):
        _download(TATOEBA_BASE + f, c / "tatoeba" / f.rsplit("/", 1)[-1], force)
    for lang in langs:
        _filter_to(kaikki_url(lang), c / f"kaikki-{lang}.jsonl", kaikki_keep(freq_words[lang], lang), force=force)
    if "nl" in langs:
        _filter_to(NLWIKT_NL, c / "nlwikt-nl-aux.jsonl", nlwikt_aux_keep,
                   prefilter=lambda b: b'"perfect"' in b, force=force)
    for lang in langs:
        if SOURCES[lang]["nlwikt"]:
            _filter_to(nlwikt_url(SOURCES[lang]["nlwikt"]), c / f"kaikki-nlwikt-{lang}.jsonl", nlwikt_keep(lang, freq_words[lang]),
                       force=force)
    if not skip_english and "it" in langs:
        _filter_to(KAIKKI_EN, c / "en-trans-it-nl.jsonl", en_trans_keep,
                   prefilter=lambda b: b'"code": "it"' in b and b'"code": "nl"' in b, force=force)
    if not skip_english and any(x not in ("it", "nl") for x in langs):
        # one pass for every v0.6 language: the 3+ GB dump is streamed once, not once per course
        codes = tuple(f'"code": "{x}"'.encode() for x in PIVOT_CODES)
        _filter_to(KAIKKI_EN, c / "en-trans-nl.jsonl", lambda e: en_trans_keep(e, PIVOT_CODES),
                   prefilter=lambda b: b'"code": "nl"' in b and any(x in b for x in codes), force=force)
    log("fetch done")
