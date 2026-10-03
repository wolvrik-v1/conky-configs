# Fonts

## Bundled here

### Ubuntu — `Ubuntu-R.ttf`, `Ubuntu-B.ttf`, `Ubuntu-I.ttf`, `Ubuntu-BI.ttf`

- Copyright **2010 Canonical Ltd.**
- Licence: **Ubuntu Font Licence 1.0** (full verbatim text in
  [`LICENSE-UFL-1.0.txt`](LICENSE-UFL-1.0.txt))
- Designer: Dalton Maag for Canonical Ltd.

UFL 1.0 explicitly permits the font to be "used, studied, modified and
redistributed freely", **provided** each copy carries the copyright notice and
the licence text. Condition 1 of the licence allows that to be satisfied by
machine-readable metadata inside the font files — every `.ttf` here carries

```
Copyright 2010 Canonical Ltd.  Licensed under the Ubuntu Font Licence 1.0
```

in its `name` table — but the licence is bundled alongside as well, so the
requirement is met twice over.

Install:

```sh
mkdir -p ~/.fonts
cp Ubuntu-*.ttf ~/.fonts/
fc-cache -f
fc-match "Ubuntu:family=Ubuntu"     # should resolve to Ubuntu-R.ttf
```

Ubuntu is the **default** face for the Etched readouts and the face used for
every label, so this is the only font you need for the widget to look right.

---

## Not bundled — obtain it yourself

### DS-Digital — by Dusit Supasawat (DS-Font, 1998)

This font is **deliberately not redistributed here.**

- Licence: **Shareware**. Listed as "Free for personal use" by its
  distributors; one index records `Commercial Use: No`.
- The font files' own embedded `name` table reads:

  ```
  Font Typeface: DS-Digital. Created by Dusit Supasawat , DS-Font 1998.
  All Rights Reserved
  ```

- There is **no redistribution grant** — "All Rights Reserved" is the absence of
  one, not the presence of a permissive licence. Personal use on your own
  machine is fine; shipping the `.ttf` files to other people is not.

Get it from the author's listing on daFont (free download, all four styles):

**<https://www.dafont.com/ds-digital.font>**

Then install it the same way as Ubuntu:

```sh
mkdir -p ~/.fonts
cp DS-DIG*.TTF ~/.fonts/
fc-cache -f
fc-match "DS-Digital:family=DS-Digital"   # -> DS-DIGI.TTF: "DS-Digital" "Normal"
```

Note that a *bare* `fc-match "DS-Digital"` can misleadingly resolve to
`DejaVuSans.ttf`, because fontconfig may treat the hyphen as a style
qualifier. Use the `:family=` form above when you want to confirm the real
font is installed.

### If you skip DS-Digital

The widgets only ever reference fonts **by family name**, so nothing breaks if
DS-Digital is absent — fontconfig substitutes a default face. You simply lose
the original seven-segment look; sizes are tuned per-face, so check the readouts
still fit if you substitute something else.

`etched-pianobar` uses DS-Digital for its elapsed-time clock specifically, and
`etched` can use it for every numeric readout via `NUM_FONT` in `etched.lua`:

```lua
local NUM_FONT = 'Ubuntu'      -- default
-- local NUM_FONT = 'DS-Digital' -- original face; install the font first
```