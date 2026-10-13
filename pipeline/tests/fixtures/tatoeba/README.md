Hand-written stand-ins for the Tatoeba per-language exports (same TSV layout), used only by the
offline importer test. `conftest.py` compresses them into `*.tsv.bz2` in a temporary cache.
Links files: `ita-eng_links.tsv`, `ita-nld_links.tsv` (target id, translation id).

`../cache/` holds a small excerpt of the kaikki.org (Wiktionary, CC BY-SA 4.0) dumps and the first
3000 lines of hermitdave/FrequencyWords `it_50k.txt` (CC BY-SA 4.0), filtered by `fetch.py`.
