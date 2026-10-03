# Fonts for `bionic`

## HOOGE 05_54 — required, not bundled

`bionic`'s sector-ring dials and numeric readouts are drawn in the **HOOGE
05_54** bitmap face. The font files are **not** bundled here.

**Why:** the fonts carry no redistribution grant. One of them states
`Copyright (c) Craig Kroeger (eng) & Nikolay Dubina (rus), 2001. All rights
reserved.` and the others carry no copyright notice at all. Bundling them in a
public repository would be redistributing them without permission, so — exactly
like DS-Digital in the etched themes — they are linked instead of shipped.

**Where to get them:** the designer's listing at daFont —
<https://www.dafont.com/craig-kroeger.d840> (Craig Kroeger, the "Uni 05_x"
bitmap family, listed free).

### Check the family name after installing

daFont lists these under the name **Uni 05_x**, while the bundled-by-us copies
reported the family names `hooge 05_53`, `hooge 05_54` and `hooge 05_55 Cyr2`.
Whether those are the same files under a renamed family could not be verified,
so check what your system actually reports:

```sh
fc-list | grep -i "05_5"
```

If the family name is `uni 05_54` rather than `hooge 05_54`, edit the one
constant that names it:

```lua
-- scripts/bionic.lua, line ~32
local F_RINGS = 'uni 05_54'   -- was 'hooge 05_54'
```

### If you would rather not install it at all

Nothing breaks. `bionic` names the font by family only, so fontconfig silently
substitutes a default face and the rings redraw in that face. `DejaVu Sans Mono`
— used elsewhere in this collection and shipped with most distributions — is the
closest visual stand-in and needs no download.