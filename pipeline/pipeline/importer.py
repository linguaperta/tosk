"""`python -m pipeline import it nl`: cached dumps -> JSONL source pack in content/{course}/.

Inputs (all in the cache, see fetch.py) plus two hand-written files in the content folder:
  course.yaml   units, skills and their queries (also used by the compiler)
  seed.yaml     curated vocabulary: lemma, tags (which skill), Dutch glosses for Italian items,
                optional English gloss overrides. Glosses written there are marked tr_src 'claude'.

Outputs: lexicon/*.jsonl, verbs/*.jsonl, sentences/*.jsonl (one file per unit + pool.jsonl for
the distractor pool), ids.tsv (permanent ids, reused on every run).
"""
from __future__ import annotations

import bz2
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import yaml

from . import features, query
from .align import Aligner
from .content import load_course_yaml, write_jsonl
from .fetch import load_freq_words
from .ids import IdRegistry
from .lang import Lang, get_lang
from .paths import cache_dir, content_dir
from .tokens import tokenize
from .wikt import Lexeme, load_lexemes

POOL_SIZE = {"it": 3000, "nl": 3000}
POS_PRIORITY = ["verb", "pron", "det", "prep", "conj", "num", "adv", "adj", "noun", "intj", "phrase", "particle"]
FUNCTION_POS = {"pron", "det", "prep", "conj"}
SINGLE_LETTER_OK ={"prep", "conj", "pron", "det", "intj", "adv", "verb"}
MAX_WORDS = 10
MIN_WORDS = 2
ITEM_QUOTA = 25          # sentences per skill item
VT_QUOTA = 24            # sentences per (grammar verb, tense)
VTP_QUOTA = 5            # sentences per (grammar verb, tense, person)
VTP_MIN = 2              # ... always accepted up to this many, even when the verb+tense quota is full
# Grammar gating: words a learner at the item's skill does not know yet (later skills, pool words,
# unlinked words; names and numbers don't count). The engine caps them at runtime (2 for vocabulary
# focus, 1 for grammar focus); pool and unlinked words never become known, so at most one of those.
MAX_UNKNOWN = 2
MAX_UNKNOWN_GRAMMAR = 1
MAX_NEVER_KNOWN = 1
NEVER = 1 << 30
# Perfect auxiliaries for Dutch verbs whose nl.wiktionary page has no perfect table (Claude-curated).
NL_AUX_OVERRIDES = {"zijn": ["zijn"], "hebben": ["hebben"], "worden": ["zijn"], "blijven": ["zijn"]}
# nl.wiktionary lists 'zijn' as a second auxiliary for most transitive verbs because of the passive
# ('het is gedaan'); for these course verbs only 'hebben' forms an active perfect ('ik heb gedaan',
# never 'ik ben gedaan'), so 'ben gedaan' must not be an accepted alternative.
NL_AUX_OVERRIDES.update({v: ["hebben"] for v in (
    "bedoelen", "brengen", "denken", "doen", "helpen", "houden", "laten", "maken", "proberen", "vinden",
    "zeggen", "zien", "geven", "horen", "kennen", "krijgen", "leven", "nemen", "praten", "vertellen")})


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


_INVISIBLE = dict.fromkeys(map(ord, "​‌‍⁠﻿­"))


def clean_text(text: str) -> str:
    """Tatoeba text without invisible characters (zero-width spaces, soft hyphens) and with single
    plain spaces: 'draagt ​​een' would not re-render from tokens."""
    return " ".join(text.translate(_INVISIBLE).replace(" ", " ").split())


def dedupe_key(text: str) -> str:
    """Sentences that differ only in case, punctuation or spacing are duplicates ('Grazie mille!'
    and 'Grazie mille.'): the app compares sentences by their normalized text."""
    s = re.sub(r"[^\w\s'’]", " ", text.lower())
    return " ".join(s.replace("’", "'").split())


# --------------------------------------------------------------------------------------- frequency
def lemma_scores(lexemes: dict[tuple[str, str], Lexeme], counts: dict[str, int]) -> dict[tuple[str, str], float]:
    """Frequency score: count of the lemma plus the counts of inflected forms that are not
    themselves a lemma. A lemma string shared by homographs gives its full count to the entry with
    the most Wiktionary senses (ties: POS_PRIORITY) and 0.5% to the others, so e.g. the musical-note
    noun 'la' does not inherit the frequency of the pronoun 'la'. A non-verb whose lemma is also a
    conjugated verb form ('stato', 'era', 'credo') gets 10% of that count."""
    lemma_owner: dict[str, tuple[str, str]] = {}
    for key in sorted(lexemes, key=lambda k: (k[0].lower(), k[1] not in FUNCTION_POS, k[1] != "verb", -lexemes[k].n_senses,
                                              POS_PRIORITY.index(k[1]) if k[1] in POS_PRIORITY else 99)):
        lemma_owner.setdefault(key[0].lower(), key)
    infl_of: dict[str, set[tuple[str, str]]] = defaultdict(set)   # inflected form -> lexemes
    for key, lx in lexemes.items():
        for f in lx.inflections:
            infl_of[f].add(key)
    lemma_set = set(lemma_owner)
    verb_forms: dict[str, set[str]] = defaultdict(set)   # conjugated form -> verb lemmas
    for (lemma, pos), lx in lexemes.items():
        if pos == "verb":
            for tense, t in lx.table.items():
                if tense != "infinitive":
                    for f in t.values():
                        if " " not in f:
                            verb_forms[f.lower()].add(lemma)
    # an inflected form shared by several lexemes ('wist': weten and wissen) counts only for the
    # one whose lemma is most frequent
    surfaces_of: dict[tuple[str, str], set[str]] = {}
    surface_owner: dict[str, tuple[str, str]] = {}
    for key, lx in lexemes.items():
        surf = set(lx.inflections)
        for t in lx.table.values():
            surf |= {f.lower() for f in t.values() if " " not in f}
        surfaces_of[key] = surf
        for s_ in surf:
            cur = surface_owner.get(s_)
            if cur is None or (counts.get(key[0].lower(), 0), key) > (counts.get(cur[0].lower(), 0), cur):
                surface_owner[s_] = key
    scores = {}
    for key, lx in lexemes.items():
        low = lx.lemma.lower()
        if " " in low:
            parts = low.split()
            base = min((counts.get(p, 0) for p in parts), default=0) * 0.05
        else:
            base = counts.get(low, 0) * (1.0 if lemma_owner[low] == key else 0.005)
            if verb_forms.get(low, set()) - {lx.lemma}:
                base *= 0.01 if lx.pos == "verb" else 0.1   # "waren" (to wander) vs "waren" (past of zijn)
            others = [k for k in infl_of.get(low, ()) if k != key and k[0].lower() != low]
            if others and (lx.pos != "verb" or any(lexemes[k].n_senses >= lx.n_senses for k in others)):
                base *= 0.1      # 'giorni' (lemma entry) is the plural of 'giorno'; 'dingen' of 'ding'
        extra = 0
        for s in surfaces_of[key]:
            if s != low and s not in lemma_set and surface_owner.get(s) == key:
                extra += counts.get(s, 0)
        scores[key] = base + extra
    return scores


# --------------------------------------------------------------------------------------- Dutch glosses for Italian
def _clean_nl(g: str) -> list[str]:
    g = re.sub(r"\([^()]*\)|\[[^\]]*\]?|\{[^}]*\}?", "", g).strip()
    g = re.sub(r"\b(ww|zn|bn|bw|vz|vnw|ovg|ontg|inerg|wederk|onov|ov)\b\.?", "", g)
    out = []
    for part in re.split(r"[;,]", g):
        p = " ".join(part.split()).strip(" .!:")
        if p and len(p) <= 30 and len(p.split()) <= 3 and not p[0].isupper() and "=" not in p:
            out.append(p)
    return out


class NlGlosser:
    """Dutch glosses for Italian words: nl.wiktionary first, then the English translation-table pivot."""

    POS_EQ = {"noun": {"noun"}, "verb": {"verb"}, "adj": {"adj"}, "adv": {"adv"}, "pron": {"pron"},
              "det": {"det", "article", "pron"}, "prep": {"prep"}, "conj": {"conj"}, "num": {"num"},
              "intj": {"intj", "phrase"}, "phrase": {"phrase", "intj", "adv"}}

    def __init__(self, cache: Path):
        self.nlw: dict[tuple[str, str], list[str]] = defaultdict(list)
        p = cache / "kaikki-nlwikt-it.jsonl"
        if p.exists():
            for line in open(p, encoding="utf-8"):
                e = json.loads(line)
                pos = {"article": "det", "name": "name"}.get(e.get("pos"), e.get("pos"))
                for s in e.get("senses", []):
                    for g in s.get("glosses", [])[:1]:
                        for c in _clean_nl(g):
                            if c not in self.nlw[(e["word"], pos)]:
                                self.nlw[(e["word"], pos)].append(c)
        self.pivot: dict[str, list[tuple[str, str, list[str]]]] = defaultdict(list)
        p = cache / "en-trans-it-nl.jsonl"
        if p.exists():
            for line in open(p, encoding="utf-8"):
                e = json.loads(line)
                for s in e["senses"]:
                    for w in s["it"]:
                        self.pivot[w].append((e["word"], e["pos"], s["nl"]))

    def gloss(self, lemma: str, pos: str, en: list[str]) -> tuple[list[str], str | None]:
        direct = self.nlw.get((lemma, pos), [])
        en_heads = {g[3:] if g.startswith("to ") else g for g in en[:3]}
        score: Counter = Counter()
        ok_pos = self.POS_EQ.get(pos, {pos})
        for en_word, en_pos, nls in self.pivot.get(lemma, []):
            if en_pos not in ok_pos:
                continue
            w = 3.0 if en_word in en_heads else 1.0
            for i, nl in enumerate(nls):
                for c in _clean_nl(nl):
                    score[c] += w / (1 + 0.2 * i)
        piv = [c for c, s in sorted(score.items(), key=lambda kv: (-kv[1], kv[0])) if s >= 2.0][:3]
        if direct:
            out = direct[:3]
            for c in piv:
                if c not in out and len(out) < 4:
                    out.append(c)
            return out, "nlwiktionary"
        if piv:
            return piv, "wiktionary-pivot"
        return [], None


# --------------------------------------------------------------------------------------- verbs
def build_verb(lang: Lang, lx: Lexeme, aux_tables: dict[str, dict[str, str]], aux: list[str]) -> dict | None:
    table = lx.table
    if not table.get("infinitive"):
        return None
    forms: dict[str, dict] = {}
    complete: dict[str, dict[str, str]] = {}
    for tense in lang.simple_tenses:
        t = table.get(tense, {})
        if all(t.get(p) for p in lang.persons):
            complete[tense] = t
    if lang.present not in complete:
        return None
    cls = lang.verb_class(lx.lemma, complete, lx.table_tags)
    irr = lang.irregular_in(lx.lemma, cls, {**complete, "participle": table.get("participle", {})})
    forms["infinitive"] = {"_": {"form": table["infinitive"]["_"]}}
    if table.get("participle", {}).get("_"):
        forms["participle"] = {"_": {"form": table["participle"]["_"]}}
    if table.get("gerund", {}).get("_"):
        forms["gerund"] = {"_": {"form": table["gerund"]["_"]}}
    for tense in lang.simple_tenses:
        if tense not in complete:
            continue
        regular = tense not in irr
        tab = {}
        for p in lang.persons:
            f = complete[tense][p]
            rec: dict = {"form": f}
            stem, ending = lang.split(lx.lemma, cls, tense, p, f, regular, complete[tense])
            if stem is not None and ending is not None:
                rec["stem"], rec["ending"] = stem, ending
            alts = lx.alts.get(tense, {}).get(p)
            if alts:
                rec["alts"] = list(alts)
            tab[p] = rec
        forms[tense] = tab
    part = table.get("participle", {}).get("_")
    aux = [a for a in aux if a in aux_tables] if part else []
    if aux:
        for ctense in lang.compound_tenses:
            tab = {}
            for p in lang.persons:
                form, alts = lang.compound(aux_tables[aux[0]], part, p, aux[0])
                for other in aux[1:]:
                    f2, a2 = lang.compound(aux_tables[other], part, p, other)
                    alts += [f2, *a2]
                rec = {"form": form}
                if alts:
                    rec["alts"] = alts
                tab[p] = rec
            forms[ctense] = tab
    irregular = bool(set(irr) & set(lang.tenses)) or "irregular" in (lx.table_tags or "")
    if lang.code == "it":
        stem = lx.lemma[:-3] if cls in ("are", "ere", "ire", "isc") else None
    else:
        p = complete[lang.present]
        stem = p["ik"] if lang.present not in irr else None
    out = {"class": cls, "stem": stem, "irregular": irregular, "irregular_in": irr,
           "auxiliary": "|".join(aux) if aux else None, "forms": forms}
    return out


# --------------------------------------------------------------------------------------- tatoeba
def _read_tsv_bz2(path: Path):
    with bz2.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            yield line.rstrip("\n").split("\t")


def load_tatoeba(code: str, cache: Path) -> tuple[dict[int, str], dict[int, dict[str, tuple[int, str]]]]:
    tdir = cache / "tatoeba"
    t3 = {"it": "ita", "nl": "nld"}[code]
    target: dict[int, str] = {}
    for parts in _read_tsv_bz2(tdir / f"{t3}_sentences.tsv.bz2"):
        if len(parts) < 3:
            continue
        text = clean_text(parts[2])
        n = len(text.split())
        if MIN_WORDS <= n <= MAX_WORDS:
            target[int(parts[0])] = text
    links: dict[str, dict[int, list[int]]] = {}
    pairs = [("en", f"{t3}-eng_links.tsv.bz2", "eng")]
    if code == "it":
        pairs.append(("nl", "ita-nld_links.tsv.bz2", "nld"))
    for lang, fname, _ in pairs:
        d: dict[int, list[int]] = defaultdict(list)
        for parts in _read_tsv_bz2(tdir / fname):
            a, b = int(parts[0]), int(parts[1])
            if a in target:
                d[a].append(b)
        links[lang] = d
    need: dict[str, set[int]] = {lang: {x for v in d.values() for x in v} for lang, d in links.items()}
    texts: dict[str, dict[int, str]] = {}
    for lang, fname in (("en", "eng_sentences.tsv.bz2"), ("nl", "nld_sentences.tsv.bz2")):
        if lang not in need:
            continue
        tx = {}
        for parts in _read_tsv_bz2(tdir / fname):
            if len(parts) >= 3 and int(parts[0]) in need[lang]:
                tx[int(parts[0])] = clean_text(parts[2])
        texts[lang] = tx
    trs: dict[int, dict[str, tuple[int, str]]] = {}
    for sid in target:
        tr = {}
        for lang, d in links.items():
            ids = sorted(x for x in d.get(sid, []) if x in texts[lang])
            if ids:
                tr[lang] = (ids[0], texts[lang][ids[0]])
        if "en" in tr:
            trs[sid] = tr
    return target, trs


# --------------------------------------------------------------------------------------- main
def run_import(code: str, content_root: str | None = None) -> None:
    lang = get_lang(code)
    cache = cache_dir()
    root = content_dir(content_root) / code
    course = load_course_yaml(root)
    seed = yaml.safe_load(open(root / "seed.yaml", encoding="utf-8")) or {}
    ids = IdRegistry(code, root / "ids.tsv")
    log(f"[{code}] loading wiktionary entries")
    lexemes = load_lexemes(cache / f"kaikki-{code}.jsonl", lang)
    counts = {w.lower(): c for w, c in reversed(load_freq_words(cache / "freq" / f"{code}_50k.txt"))}
    scores = lemma_scores(lexemes, counts)
    translations = course["translations"]

    # ---- seed (curated) entries
    seed_entries = [s for s in (seed.get("items") or [])]
    excluded = set(seed.get("exclude") or [])   # 'lemma' or 'lemma/pos': never in the pool
    by_lemma = defaultdict(list)
    for key in lexemes:
        by_lemma[key[0]].append(key)
    chosen: dict[tuple[str, str], dict] = {}   # (lemma,pos) -> seed overrides
    for s in seed_entries:
        lemma = s["lemma"]
        pos = s.get("pos")
        key = None
        if pos and (lemma, pos) in lexemes:
            key = (lemma, pos)
        elif by_lemma.get(lemma):
            # seed POS not in Wiktionary (e.g. 'grazie' is a noun there): use the best entry and
            # re-label it with the seed POS
            best = sorted(by_lemma[lemma], key=lambda k: (-scores.get(k, 0), k))[0]
            key = (lemma, pos or best[1])
            if key not in lexemes:
                src = lexemes[best]
                lexemes[key] = Lexeme(lemma=lemma, pos=key[1], glosses=list(src.glosses),
                                      inflections=set(src.inflections), n_senses=src.n_senses)
                scores[key] = scores.get(best, 0)
                scores[best] = 0      # the re-labelled copy replaces the original
        if key is None and not s.get("tags"):
            continue   # gloss-only entry for a word that is not in this pack
        if key is None:
            if not pos or not s.get("en"):
                raise SystemExit(f"[{code}] seed item {lemma!r} not in Wiktionary data; give pos and en")
            key = (lemma, pos)
            lexemes[key] = Lexeme(lemma=lemma, pos=pos, glosses=[])
            scores[key] = counts.get(lemma.lower(), 0) if " " not in lemma else 0
        if key in chosen:
            prev = chosen[key]
            prev["tags"] = sorted(set(prev.get("tags", [])) | set(s.get("tags", [])))
            continue
        chosen[key] = s
        if s.get("inflections"):
            new = {x.lower() for x in s["inflections"]} - lexemes[key].inflections
            lexemes[key].inflections |= new
            scores[key] = scores.get(key, 0) + sum(counts.get(x, 0) for x in new)

    # A tagged (taught) seed item takes the frequency of its lemma from the homographs that Wiktionary
    # lists with more senses ('madre' adj vs noun, 'bene' noun vs adv, 'solo' conj vs adv), so the
    # alignment links the word to the taught item. Verbs and other seed items keep their own score.
    for key, s in chosen.items():
        if not s.get("tags"):
            continue
        others = [k for k in by_lemma.get(key[0], []) if k != key and k not in chosen and k[1] != "verb"]
        top = max([scores.get(k, 0) for k in others], default=0)
        if top > scores.get(key, 0):
            scores[key] = top
            for k in others:
                scores[k] = scores.get(k, 0) * 0.005

    # ---- pool by frequency
    def eligible(key, lx: Lexeme) -> bool:
        if not lx.glosses:
            return False
        if lx.lemma[:1].isupper() or any(ch.isdigit() for ch in lx.lemma) or " " in lx.lemma:
            return False
        if len(lx.lemma) == 1 and lx.pos not in SINGLE_LETTER_OK:
            return False
        if lx.pos == "verb" and code == "it" and not lx.lemma.endswith(("are", "ere", "ire", "rre")):
            return False   # pronominal verbs (alzarsi, farcela, andarsene) have clitic-laden tables
        if lx.lemma in excluded or f"{lx.lemma}/{lx.pos}" in excluded:
            return False
        return scores.get(key, 0) > 0

    ranked = sorted(lexemes, key=lambda k: (-scores.get(k, 0), k))
    pool = [k for k in ranked if eligible(k, lexemes[k])][: POOL_SIZE[code]]
    selected = list(dict.fromkeys(pool + list(chosen)))
    rank_of = {k: i + 1 for i, k in enumerate(k for k in ranked if scores.get(k, 0) > 0)}

    # ---- aux info
    aux_of: dict[str, list[str]] = {}
    if code == "nl":
        p = cache / "nlwikt-nl-aux.jsonl"
        for line in open(p, encoding="utf-8"):
            e = json.loads(line)
            aux_of[e["word"]] = e["aux"]
        aux_of.update(NL_AUX_OVERRIDES)
    aux_tables = {}
    for a in lang.auxiliaries:
        lx = lexemes.get((a, "verb"))
        if lx and lx.table.get(lang.present):
            aux_tables[a] = lx.table[lang.present]

    glosser = NlGlosser(cache) if code == "it" else None

    # ---- build records (ids assigned in score order so the most frequent homograph gets the base id)
    items: list[dict] = []
    verbs: dict[str, dict] = {}
    for key in sorted(selected, key=lambda k: (-scores.get(k, 0), k)):
        lx = lexemes[key]
        s = chosen.get(key, {})
        tr: dict[str, list[str]] = {}
        tr_src: dict[str, str] = {}
        en = list(s.get("en") or [])
        if en:
            tr["en"], tr_src["en"] = en, "claude"
        elif lx.glosses:
            tr["en"], tr_src["en"] = lx.glosses[:5], "wiktionary"
        if "nl" in translations and code != "nl":
            nl = list(s.get("nl") or [])
            if nl:
                tr["nl"], tr_src["nl"] = nl, "claude"
            elif glosser:
                g, src = glosser.gloss(lx.lemma, lx.pos, tr.get("en", []))
                if g:
                    tr["nl"], tr_src["nl"] = g, src
        if not tr.get("en"):
            continue
        iid = ids.get(lx.lemma, lx.pos)
        rec: dict = {"id": iid, "lemma": lx.lemma, "pos": lx.pos}
        if lx.pos == "noun":
            gender = s.get("gender") or lx.gender
            article = s.get("article") or lang.article_for(lx.lemma, gender)
            if article:
                rec["article"] = article
            if gender:
                rec["gender"] = gender
            if s.get("plural") or lx.plural:
                rec["plural"] = s.get("plural") or lx.plural
        rec["freq"] = rank_of.get(key)
        rec["tr"] = tr
        rec["tr_src"] = tr_src
        tags = sorted(set(s.get("tags") or []))
        if tags:
            rec["tags"] = tags
        if s.get("variants"):
            rec["variants"] = list(s["variants"])
        infl = sorted(lx.inflections - {lx.lemma.lower()})
        if infl:
            rec["inflections"] = infl
        items.append(rec)
        if lx.pos == "verb" and lx.table:
            aux = lx.aux if code == "it" else aux_of.get(lx.lemma, [])
            v = build_verb(lang, lx, aux_tables, aux)
            if v:
                verbs[iid] = {"id": iid, **v}

    # ---- resolve skills -> units
    unit_of: dict[str, str] = {}
    unit_order = [u["id"] for u in course["units"]]
    for unit in course["units"]:
        for skill in unit.get("skills") or []:
            for iid in query.resolve(skill, items, verbs, course["persons"]):
                unit_of.setdefault(iid, unit["id"])
    for rec in items:
        if rec["id"] in unit_of:
            rec["unit"] = unit_of[rec["id"]]
    missing = [r["id"] for r in items if r.get("unit") and any(not r["tr"].get(l) for l in translations)]
    if missing:
        log(f"[{code}] WARNING skill items without all translations ({len(missing)}): {' '.join(missing)}")

    # ---- sentences
    log(f"[{code}] loading tatoeba")
    target, trs = load_tatoeba(code, cache)
    aligner = Aligner(lang, items, verbs)
    item_by_id = {r["id"]: r for r in items}
    skill_items = {iid for iid in unit_of}
    grammar_targets: set[tuple[str, str]] = set()
    for unit in course["units"]:
        for skill in unit.get("skills") or []:
            if "verbs" in skill:
                t = skill["verbs"]["tense"]
                for iid in query.resolve(skill, items, verbs, course["persons"]):
                    grammar_targets.add((iid, t))
    # grammar gating (features.py): a sentence is only selected when its grammar features are
    # allowed at its home skill, and it only counts for an item (verb tense) whose introducing
    # (grammar) skill allows them and knows nearly all its words
    tagger, graph = features.build(course, items, verbs)
    skill_pos = graph.pos
    item_pos = {iid: skill_pos[s] for iid, s in graph.item_skill.items()}
    cands = []
    seen_text = set()
    for sid in sorted(trs):
        text = target[sid]
        low = dedupe_key(text)
        if low in seen_text:
            continue
        seen_text.add(low)
        try:
            toks = tokenize(text, code)
        except ValueError:
            continue
        al = aligner.align(toks)
        words = [t for t in al if t["is_word"]]
        if not words or len(words) > MAX_WORDS:
            continue
        unlinked = 0
        for i, t in enumerate(al):
            if not t["is_word"] or t["lex"]:
                continue
            if t["t"][:1].isdigit():
                continue
            if t["t"][:1].isupper() and i > 0:      # names (Tom, Maria, ...) are fine
                continue
            unlinked += 1
        if unlinked > 1 or unlinked / len(words) > 0.2:
            continue
        touched = {t["lex"] for t in al if t["lex"] in skill_items}
        if not touched:
            continue
        feats = tagger.tag(al)
        if graph.problems(al, feats):
            continue
        # skill position at which each word becomes known (NEVER: pool words, unlinked words)
        known_at = []
        for t in al:
            if not t["is_word"] or (not t["lex"] and (t["t"][:1].isdigit() or t["t"][:1].isupper())):
                continue
            known_at.append(item_pos.get(t["lex"], NEVER) if t["lex"] else NEVER)
        if graph.enforced and known_at.count(NEVER) > MAX_NEVER_KNOWN:
            continue
        vts = set()
        for t in al:
            if t["lex"] and t["form"] and "." in t["form"]:
                tense, person = t["form"].split(".", 1)
                if (t["lex"], tense) in grammar_targets:
                    vts.add((t["lex"], tense, person))

        def usable(skill_id: str | None, limit: int) -> int | None:
            """Unknown words for a learner at skill_id, or None when the sentence doesn't fit."""
            if skill_id is None or (graph.enforced and not feats <= graph.allowed[skill_id]):
                return None
            unknown = sum(1 for k in known_at if k > skill_pos[skill_id])
            return unknown if unknown <= limit or not graph.enforced else None

        ok_items = {i: usable(graph.item_skill.get(i), MAX_UNKNOWN) for i in touched}
        ok_items = {i: u for i, u in ok_items.items() if u is not None}
        ok_vts = {}
        for v, t, p in vts:
            u = usable(graph.grammar_skill(v, t), MAX_UNKNOWN_GRAMMAR)
            if u is not None:
                ok_vts[(v, t, p)] = u
        if not ok_items and not ok_vts:
            continue
        best = min([*ok_items.values(), *ok_vts.values()])
        cands.append((best, unlinked, len(words), sid, al, touched, ok_items, ok_vts))
    cands.sort(key=lambda c: (c[0], c[1], abs(c[2] - 6), c[3]))
    item_count: Counter = Counter()
    vt_count: Counter = Counter()
    vtp_count: Counter = Counter()
    sentences = []
    for _best, unlinked, nw, sid, al, touched, ok_items, ok_vts in cands:
        useful = any(item_count[i] < ITEM_QUOTA for i in ok_items) or any(
            vtp_count[(v, t, p)] < VTP_QUOTA and (vt_count[(v, t)] < VT_QUOTA or vtp_count[(v, t, p)] < VTP_MIN)
            for v, t, p in ok_vts)
        if not useful:
            continue
        for i in ok_items:
            item_count[i] += 1
        for v, t, p in ok_vts:
            vt_count[(v, t)] += 1
            vtp_count[(v, t, p)] += 1
        unit_idx = max(unit_order.index(item_by_id[i]["unit"]) for i in touched)
        tr = trs[sid]
        toks_out = []
        for t in al:
            o: dict = {"t": t["t"]}
            if t["pre"]:
                o["pre"] = t["pre"]
            if not t["is_word"]:
                o["is_word"] = False
            if t["lex"]:
                o["lex"] = t["lex"]
            if t["form"]:
                o["form"] = t["form"]
            toks_out.append(o)
        sentences.append({
            "id": f"s:{sid}",
            "text": target[sid],
            "tr": {l: tr[l][1] for l in sorted(tr)},
            "tr_src": {l: f"tatoeba:{tr[l][0]}" for l in sorted(tr)},
            "src": f"tatoeba:{sid}",
            "unit": unit_order[unit_idx],
            "tokens": toks_out,
        })
    log(f"[{code}] {len(cands)} candidate sentences, {len(sentences)} selected")

    # ---- write
    for kind in ("lexicon", "verbs", "sentences"):
        d = root / kind
        if d.exists():
            for p in d.glob("*.jsonl"):
                p.unlink()
    groups: dict[str, list[dict]] = defaultdict(list)
    for rec in sorted(items, key=lambda r: r["id"]):
        groups[rec.get("unit") or "pool"].append(rec)
    for g, recs in groups.items():
        write_jsonl(root / "lexicon" / f"{g}.jsonl", recs)
    vgroups: dict[str, list[dict]] = defaultdict(list)
    for vid in sorted(verbs):
        u = item_by_id[vid].get("unit") or "pool"
        vgroups[u].append(verbs[vid])
    for g, recs in vgroups.items():
        write_jsonl(root / "verbs" / f"{g}.jsonl", recs)
    sgroups: dict[str, list[dict]] = defaultdict(list)
    for s in sorted(sentences, key=lambda s: int(s["id"][2:])):
        sgroups[s["unit"]].append(s)
    for g, recs in sgroups.items():
        write_jsonl(root / "sentences" / f"{g}.jsonl", recs)
    ids.save()
    log(f"[{code}] wrote {len(items)} items ({len(unit_of)} in skills), {len(verbs)} verbs, "
        f"{len(sentences)} sentences; {ids.added} new ids")
