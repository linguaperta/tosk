"""Read filtered kaikki.org (wiktextract) entries into compact lexemes."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from .lang import BAD_FORM_TAGS, Lang

POS_MAP = {
    "noun": "noun", "verb": "verb", "adj": "adj", "adv": "adv", "pron": "pron", "det": "det",
    "article": "det", "prep": "prep", "postp": "prep", "circumpos": "prep", "conj": "conj", "num": "num",
    "intj": "intj", "phrase": "phrase", "prep_phrase": "phrase", "particle": "particle",
    "contraction": "prep",
}
SKIP_SENSE_TAGS = {"obsolete", "archaic", "rare", "dated", "dialectal", "vulgar", "offensive", "derogatory",
                   "slur", "historical", "poetic", "literary", "nonstandard", "misspelling", "Tuscany", "regional"}
SKIP_GLOSS_RE = re.compile(r"\b(form of|plural of|singular of|abbreviation|initialism|alternative|"
                           r"misspelling|synonym of|apocopic|feminine of|masculine of|participle of)\b", re.I)
SKIP_INFL_TAGS = {"table-tags", "inflection-template", "class", "canonical", "diminutive", "augmentative",
                  "pejorative", "endearing", "romanization", "alternative", "auxiliary"} | BAD_FORM_TAGS


@dataclass
class Lexeme:
    lemma: str
    pos: str
    glosses: list[str]
    gender: str | None = None
    plural: str | None = None
    inflections: set[str] = field(default_factory=set)
    # verbs
    table: dict[str, dict[str, str]] = field(default_factory=dict)       # tense -> person -> form
    alts: dict[str, dict[str, list[str]]] = field(default_factory=dict)  # tense -> person -> alternatives
    aux: list[str] = field(default_factory=list)
    table_tags: str = ""
    n_senses: int = 0


FRAGMENT_START = {"in", "with", "before", "after", "or", "and", "such", "as", "for", "of", "by", "especially",
                  "usually", "used", "e.g.", "i.e.", "etc", "when", "which", "that", "who", "being", "also",
                  "often", "chiefly", "mostly", "typically", "generally", "sometimes", "from", "on", "at"}
GRAMMAR_WORDS = re.compile(r"\b(article|singular|plural|masculine|feminine|neuter|participle|auxiliary|"
                           r"infinitive|preposition|pronoun|conjunction|adverb|adjective|verb|noun|clitic|"
                           r"diminutive|suffix|prefix|contraction)\b", re.I)
MODALS = {"can", "may", "must", "shall", "will", "should", "would", "could", "might", "ought"}


EXPLANATION_RE = re.compile(r"^(used|forms?|indicates?|expresses|denotes|dismisses|e\.g\.|i\.e\.|see)\b", re.I)


def clean_gloss(g: str, pos: str) -> list[str]:
    """Short, answer-like glosses from a Wiktionary gloss: explanations and grammar notes are
    dropped ('Indicates the indirect object. to' -> ['to'])."""
    if re.search(r"script letter|name of the letter", g, re.I):
        return []
    g = re.sub(r"\([^()]*\)", "", g)
    g = re.sub(r"\([^()]*\)", "", g)
    g = g.replace("’", "'").strip().rstrip(".:")
    parts = []
    for clause in re.split(r";|:|\.\s", g):
        if EXPLANATION_RE.match(clause.strip()) or SKIP_GLOSS_RE.search(clause):
            continue
        parts += clause.split(",")
    out = []
    for part in parts:
        p = " ".join(part.split()).strip(" .!")
        p = re.sub(r"\s+etc$", "", p)
        if not p or p[0] in "'\"-" or SKIP_GLOSS_RE.search(p) or GRAMMAR_WORDS.search(p):
            continue
        if len(p.split()) > 1 and p.split(" ")[0].lower() in FRAGMENT_START:
            continue
        if "+" in p or any(ch.isdigit() for ch in p):
            continue
        if pos == "noun":
            p = re.sub(r"^(a|an|the) ", "", p)
        first = p.split(" ")[0]
        if pos == "verb" and not p.startswith("to ") and first.isalpha() and p[0].islower() and first not in MODALS:
            p = "to " + p
        if len(p) > 32 or len(p.split()) > 5:
            continue
        if p[0].isupper() and len(p.split()) > 2:   # explanatory sentence ("Used to form ...")
            continue
        out.append(p)
    return out


def entry_glosses(e: dict, pos: str, limit: int = 5) -> list[str]:
    out: list[str] = []
    for s in e.get("senses") or []:
        tags = set(s.get("tags") or [])
        if tags & SKIP_SENSE_TAGS or s.get("form_of") or s.get("alt_of") or "form-of" in tags:
            continue
        gl = s.get("glosses") or []
        if not gl:
            continue
        for g in clean_gloss(gl[0], pos):
            if g not in out:
                out.append(g)
        if len(out) >= limit:
            break
    return out[:limit]


GENDER_RE = re.compile(r"^(m|f|n|c|mf|m or f|f or m|m or n|n or m|f or n|n or f|m pl|f pl|n pl|m-p|f-p)\b")


def entry_gender(e: dict) -> str | None:
    word = e.get("word") or ""
    for h in e.get("head_templates") or []:
        exp = (h.get("expansion") or "").strip()
        if not exp:
            continue
        rest = exp[len(word):].strip() if exp.lower().startswith(word.lower()) else exp.split(" ", 1)[-1]
        m = GENDER_RE.match(rest)
        if m:
            g = m.group(1)
            if g in ("mf",):
                return "m|f"
            if " or " in g:
                a, _, b = g.split(" ")
                return f"{a}|{b}"
            return g.split(" ")[0].split("-")[0]
    return None


def _clean_form(f: str) -> list[str]:
    out = []
    for part in re.split(r"[()]", f):
        p = part.strip()
        if not p or " " in p and not p.startswith("het "):
            continue
        if p.startswith("het "):
            p = p[4:]
        if re.fullmatch(r"[\w'’-]+", p) and re.search(r"[^\W\d_]", p):
            out.append(p.replace("’", "'"))
    return out


def parse_entry(e: dict, lang: Lang) -> Lexeme | None:
    pos = POS_MAP.get(e.get("pos") or "")
    if not pos:
        return None
    lemma = (e.get("word") or "").strip()
    if not lemma:
        return None
    glosses = entry_glosses(e, pos)
    lx = Lexeme(lemma=lemma, pos=pos, glosses=glosses)
    lx.n_senses = sum(1 for sn in e.get("senses") or []
                      if not (set(sn.get("tags") or []) & SKIP_SENSE_TAGS) and not sn.get("form_of"))
    if pos == "noun":
        lx.gender = entry_gender(e)
    templates_seen = 0
    for f in e.get("forms") or []:
        tags = f.get("tags") or []
        form = f.get("form") or ""
        if f.get("source") == "conjugation":
            if "inflection-template" in tags:
                templates_seen += 1
                continue
            if templates_seen > 1:
                break      # only the first (standard) conjugation table
            if "table-tags" in tags:
                lx.table_tags = lx.table_tags or form
                continue
            sp = lang.spelling(form, f.get("link"))
            if "auxiliary" in tags:
                if sp not in lx.aux:
                    lx.aux.append(sp)
                continue
            slot = lang.slot(tags)
            if not slot or not sp or sp == "-" or "/" in sp:
                continue
            tense, persons = slot
            for person in persons.split(","):
                cur = lx.table.setdefault(tense, {})
                if person not in cur:
                    cur[person] = sp
                elif sp != cur[person]:
                    if lang.code == "nl" and person == "jij" and sp == cur.get("ik"):
                        continue   # inverted 'loop jij' form, not an alternative for 'jij loopt'
                    al = lx.alts.setdefault(tense, {}).setdefault(person, [])
                    if sp not in al:
                        al.append(sp)
            continue
        if pos == "verb":
            if "auxiliary" in tags and f.get("source") != "conjugation":
                continue
            continue
        if set(tags) & SKIP_INFL_TAGS:
            continue
        if pos == "pron" or (pos == "det" and lang.code == "nl"):
            continue   # pronoun/article tables list other words (ik: wij, we, ...), not inflections
        for p in _clean_form(lang.spelling(form, f.get("link")) if lang.code == "it" else form):
            if p.lower() != lemma.lower():
                lx.inflections.add(p.lower())
        if pos == "noun" and "plural" in tags and lx.plural is None:
            cf = _clean_form(form)
            if cf:
                lx.plural = cf[0]
    return lx


def load_lexemes(path: Path, lang: Lang) -> dict[tuple[str, str], Lexeme]:
    """(lemma, pos) -> merged Lexeme (several etymologies with the same POS are merged)."""
    out: dict[tuple[str, str], Lexeme] = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            e = json.loads(line)
            lx = parse_entry(e, lang)
            if lx is None:
                continue
            key = (lx.lemma, lx.pos)
            if key not in out:
                out[key] = lx
                continue
            cur = out[key]
            for g in lx.glosses:
                if g not in cur.glosses and len(cur.glosses) < 6:
                    cur.glosses.append(g)
            cur.inflections |= lx.inflections
            cur.n_senses += lx.n_senses
            cur.gender = cur.gender or lx.gender
            cur.plural = cur.plural or lx.plural
            if not cur.table and lx.table:
                cur.table, cur.alts, cur.aux, cur.table_tags = lx.table, lx.alts, lx.aux, lx.table_tags
    return out
