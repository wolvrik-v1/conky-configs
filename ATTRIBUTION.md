# Attribution

A single place to record who made what. Only facts I could verify are asserted
here — anything I could not confirm is marked **provenance unknown** rather than
guessed at.

## Fonts

### Bundled

**Ubuntu** — `Ubuntu-R/B/I/BI.ttf` (used by `etched`, `etched-pianobar`,
`etched-weather`)

- © 2010 Canonical Ltd. · design by Dalton Maag
- **Ubuntu Font Licence 1.0** — verbatim text in
  [`etched/fonts/LICENSE-UFL-1.0.txt`](etched/fonts/LICENSE-UFL-1.0.txt)
- UFL 1.0 permits redistribution provided the copyright notice and licence
  travel with the files. Each `.ttf` carries the notice in its `name` table and
  the licence is bundled alongside, so both are satisfied.

### Not bundled

Both fonts below are **linked, not shipped**: neither carries a redistribution
grant, so bundling them in a public repository would be redistribution without
permission.

**DS-Digital** — by Dusit Supasawat (DS-Font, 1998)

- Shareware. Distributors list it as free for personal use; one index records
  `Commercial Use: No`.
- Its files' own `name` table reads:
  `Font Typeface: DS-Digital. Created by Dusit Supasawat , DS-Font 1998. All Rights Reserved`
- Obtain it from the author's listing: <https://www.dafont.com/ds-digital.font>

**HOOGE 05_53 / 05_54 / 05_55** — by Craig Kroeger (eng) & Nikolay Dubina (rus)

- Used by `bionic`'s ring face. Family names in the copies inspected:
  `hooge 05_53`, `hooge 05_54`, `hooge 05_55 Cyr2`.
- Embedded notices, verbatim: `hoog0555_cyr2.ttf` reads
  `Copyright (c) Craig Kroeger (eng) & Nikolay Dubina (rus), 2001. All rights reserved.`;
  the other three files carried **no** copyright notice whatsoever.
- Obtain them from the designer's listing: <https://www.dafont.com/craig-kroeger.d840>
- ⚠️ That page lists the family as **Uni 05_x**. Whether it is the same files
  under a renamed family could not be verified — run `fc-list | grep -i 05_5`
  after installing and adjust the `F_RINGS` constant in `bionic/scripts/bionic.lua`
  if the family name differs.

Widgets reference fonts by family name only, so nothing breaks when a font is
absent — fontconfig substitutes a default face. `bionic` falls back to a plain
monospace dial if HOOGE is missing; `DejaVu Sans Mono` is the closest stand-in.

## Artwork & wallpapers

| File | Theme | Provenance |
| --- | --- | --- |
| `bionic/pix/bg_ORIGINAL-2010.png` | bionic | Original plate from **"Steel Conky by Mucas V2.0"** (2010) |
| `bionic/scripts/rings.lua` | bionic | `v1.0 by wlourf (08.08.2010)` — header preserved verbatim |
| `bionic/wallpapers/skyvictor79-alien-10211544_1920.jpg` | bionic | **skyvictor79**, via [Pixabay](https://pixabay.com) |
| `bionic/wallpapers/bionic.jpg` | bionic | provenance unknown — the author does not recall its source |
| `orrery-brass/wallpapers/ORRERY1.jpg` | orrery-brass | Generated for this theme by the author with Google's image generator |
| `etched/wallpapers/etched-obsidian-dark.png` | etched | provenance unknown — the author does not recall its source |
| `etched/wallpapers/tea-hd-wallpaper.jpg` | etched | provenance unknown — the author does not recall its source |
| `clockwork-alchemist/wallpapers/wallpaper-steampunk3.jpg` | clockwork-alchemist | Generated for this theme by the author with Google's image generator |
| `cyber-deck/wallpapers/Official_Cyberpunk_Control_Tower.jpg` | cyber family | AI-generated cyberpunk control-tower scene obtained from Google's image generator; the author sharpened a local copy for use as the desktop wallpaper |

Of the seven bundled wallpapers: three are AI-generated artwork the author made
for the theme they belong to, one is credited to **skyvictor79** via Pixabay, and
three have no known origin. If you ever trace them, update this table — an
honest "unknown" is better than a guess.

Note on the cyber wallpaper: the file bundled here is the unmodified image as
downloaded. The copy actually set as the desktop background was run through a
sharpening pass locally for on-screen use; the sharpened variant is not included,
since it is a derived edit rather than the source artwork.

## Code

All Lua/Cairo rendering, widget layouts, configuration and packaging in this
repository are original work, except:

- **bionic** reimplements the well centres and sector-ring geometry of the
  original 2010 "Steel Conky" by Mucas / wlourf. The original plate artwork is
  preserved unmodified as `bg_ORIGINAL-2010.png`.

## Screenshots

Captured on Bodhi Linux / Moksha with Conky 1.12.2. Kept at full resolution; they
are not resized for the web.

`cyber-deck/CyberdeckFamily-10-03-2026.png` captures all three Cyber widgets
running at once against the bundled wallpaper, and stands in for separate
per-theme captures of `cyber-deck`, `cyber-radar` and `cyber-atc`.