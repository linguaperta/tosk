"""Sentence tokenizer. Words and punctuation are separate tokens; `pre` keeps the exact whitespace
before each token, so ''.join(pre + t) re-renders the input text exactly.

Italian elision rule: an apostrophe directly between two letters ends the first token and stays
attached to it: "l'acqua" -> ["l'", "acqua"], "dell'uomo" -> ["dell'", "uomo"], "c'è" -> ["c'", "è"],
"un'amica" -> ["un'", "amica"]. A word-final apostrophe is kept on the word only for the known
truncations (po', mo', be', di', fa', va', da', sta', to'); otherwise it is punctuation (a quote).

Dutch: apostrophes inside a word stay in it ("auto's", "zo'n", "m'n"); the clitic forms
"'s", "'t", "'k", "'n" at a word start are word tokens of their own.

Both languages: hyphenated words stay one token ("e-mail"); a run of dots is one token ("...");
every other non-space, non-word character is its own punctuation token.
"""
from __future__ import annotations

import re

APOS = "'’"
IT_TRUNC = {"po", "mo", "be", "di", "fa", "va", "da", "sta", "to", "piè", "ca"}

_L = r"[^\W\d_]"          # a letter
_W = r"\w"

IT_RE = re.compile(
    rf"(?P<ws>\s*)(?:"
    rf"(?P<elided>{_L}+[{APOS}](?={_L}))"
    rf"|(?P<trunc>{_L}+[{APOS}](?!{_W}))"
    rf"|(?P<word>{_W}+(?:[-‐]{_W}+)*)"
    rf"|(?P<dots>\.\.+|…)"
    rf"|(?P<punct>[^\w\s])"
    rf")"
)

NL_RE = re.compile(
    rf"(?P<ws>\s*)(?:"
    rf"(?P<clitic>(?<!{_W})[{APOS}](?:s|t|k|n|m|r)(?!{_W}))"
    rf"|(?P<word>{_W}+(?:[{APOS}\-‐]{_W}+)*)"
    rf"|(?P<dots>\.\.+|…)"
    rf"|(?P<punct>[^\w\s])"
    rf")"
)


def tokenize(text: str, lang: str) -> list[dict]:
    """Return [{'t': str, 'pre': str, 'is_word': bool}]. Trailing whitespace is dropped."""
    rx = IT_RE if lang == "it" else NL_RE
    out: list[dict] = []
    pos = 0
    n = len(text.rstrip())
    while pos < n:
        m = rx.match(text, pos)
        if not m or m.end() == pos:
            raise ValueError(f"tokenizer stuck at {pos} in {text!r}")
        ws = m.group("ws")
        kind = m.lastgroup
        tok = m.group(kind)
        if kind == "trunc":
            base = tok[:-1].lower()
            if base not in IT_TRUNC:
                # not a known truncation: the apostrophe is a closing quote
                tok = tok[:-1]
                kind = "word"
        out.append({"t": tok, "pre": ws, "is_word": kind in ("word", "elided", "trunc", "clitic")})
        pos = m.start() + len(ws) + len(tok)
    return out


def render(tokens: list[dict]) -> str:
    return "".join(t.get("pre", "") + t["t"] for t in tokens)
