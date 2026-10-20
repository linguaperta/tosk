# Brand exploration brief: tosk

You are an illustrator or brand designer making brand art as **hand-written SVG** for **tosk**, a free, open-source language-learning app: a player for community-made "language packs", including personal packs for reading books. The GitHub org is **linguaperta**.

## Story

**Tosk** is short for **Ratatosk**, the red squirrel of Norse myth who runs up and down the world-tree **Yggdrasil**, carrying messages between the eagle in the crown and the dragon Níðhöggr at the roots. That makes him a metaphor for carrying words between languages. In the app, **course paths are branches of Yggdrasil**:
- skills are nodes along branches
- units are boughs
- the trunk is the path upward
- roots are the foundations

The app must also look good on a **black-and-white e-ink reader** (Onyx Boox). Every piece needs a colour version AND a pure black/white version.

## Feedback on the first draft (read it, don't copy it)

- First draft: `C:/Users/timo/Repositories/tosk/docs/brand-sheet.png` (generator: `C:/Users/timo/Repositories/tosk/app/tool/brand/make_brand.py`).
- The owner said it's **"too clearly just a bunch of shapes"**: ellipses and circles stacked together.
- **Tosk's character** is generic and stiff.
- The **icon/logo** isn't distinctive.
- The **tree/map** isn't mythical enough.

So: build forms as **organic, hand-crafted Bézier silhouettes**, not stacked primitive ellipses and circles. Give Tosk real character: a lively, clever, slightly mischievous messenger, a confident or dynamic pose, an expressive eye, the iconic red-squirrel ear tufts, and a huge plume tail. Make the tree feel mythical (an ancient ash, three roots, perhaps hints of the eagle, dragon or well, rune details) while it still works as a course map with skill nodes.

## Deliverables (only in your style folder)

| File | What |
| --- | --- |
| `tosk.svg` + `tosk-mono.svg` | full-body mascot |
| `icon.svg` + `icon-mono.svg` | app icon; must read at 48 px (check by rendering small) |
| `logo.svg` | mark plus a "tosk" wordmark, lowercase |
| `yggdrasil.svg` + `yggdrasil-mono.svg` | the course tree, portrait ~800×1100, ~6–8 skill nodes on branches |
| `branch-tile.svg` + `branch-tile-mono.svg` | a fork of branches between skill nodes, for the map |
| `sheet.html` | presents everything: colour and mono side by side, the icon at 48 and 96 px, the palette as hex swatches |

You may write a Python generator (no dependencies) in your folder, or hand-write the SVG. Keep each SVG under ~300 KB.

## Process (important): iterate visually

Render your sheet to PNG with headless Edge from PowerShell (pick a unique profile name):

```
$p="<your folder, Windows path>"; Start-Process -FilePath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -ArgumentList @("--headless=new","--disable-gpu","--hide-scrollbars","--user-data-dir=$p\edgeprof","--window-size=1400,1800","--screenshot=$p\sheet.png","file:///$($p -replace '\\','/')/sheet.html") -Wait -WindowStyle Hidden
```

Then **look** at `sheet.png` with the Read tool. Critique it honestly like an art director: anatomy and gesture, silhouette, charm, small-size readability, e-ink contrast, and consistency across pieces. Then improve. Do **at least 4** render → critique → improve rounds. At the end, delete the `edgeprof` folder and keep `sheet.png`.

## Rules

- No sub-agents.
- Don't touch anything outside your folder.
- Don't run git.

**Final message:** what you made, the style rationale, the palette (hex), honest weaknesses, and the path to `sheet.png`.
