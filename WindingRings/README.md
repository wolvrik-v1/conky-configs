# WindingRings

A full-screen **glass "Air Clock" + winding meters** desktop for Conky — a modern
single-file Lua/Cairo reimplementation of two classic 2009 widgets by
Alison Pitt (**londonali1010**): the **Air Clock** glass face, and the **Ring**
meters (here drawn as alternating semicircle "winding" S-curves).

100% procedural Lua/Cairo — no images and no bundled fonts. It fills the screen
(1920×1080 by default) and sits directly on the desktop wallpaper.

```
        ╭─────────╮
       │   ✛      │            CPU ▓▓▓▓▓░░░░
       │  glass   │              ░░░░░▓▓▓▓▓ MEM
       │  clock   │            FS /R ...
       ╰─────────╯            (S-curves alternate down the right side)
   Thursday, 15 October 2026
   Artist - Title (Album)
```

## What it shows

| Element | Source |
| --- | --- |
| **Glass clock** (top-left) | hour / minute / second hands from the system clock |
| **Date** | `%A, %d %B %Y` (e.g. *Thursday, 15 October 2026*), Santana font |
| **Now playing** | pianobar `artist` / `title` / `album` files |
| **CPU · MEM** | `${cpu cpu0}` / `${memperc}` |
| **FS /R · FS /H** | `${fs_used_perc}` for `/` and `/home` |
| **Spd** | wireless bitrate (Mb/s), scaled to `MAX_SPEED` |
| **Qual** | wireless link quality % |

The six meters alternate bulge-right / bulge-left down the right side of the
screen; each is an S-curve arc that fills with its value.

## Install

```sh
mkdir -p ~/.conky && cp -r WindingRings ~/.conky/WindingRings
```

Launch:

```sh
conky -d -c ~/.conky/WindingRings/WindingRingsrc
```

or use the wrapper: `~/.conky/WindingRings/WindingRings start|stop|restart|status`.

### Fonts

The date uses **Santana** (© Manfred Klein, 2004 —
https://www.dafont.com/santana.font), the same face the original widget used.
It is **not bundled** here (its redistribution terms are unclear). If Santana
isn't installed, fontconfig substitutes a default face and the widget still runs.

### Wallpaper

`wallpapers/wallhaven-d6pjk3.png` is a bundled desktop background (see credits)
that pairs well with the widget's white-on-transparent styling.

## Tuning

All controls are the constant block at the top of `WindingRings.lua`:

- **Clock position/size** — `CLOCK_X`, `CLOCK_Y`, `CLOCK_R`.
- **Date position** — `DATE_X`, `DATE_Y` (the now-playing line uses `DATE_Y + 38`).
- **Meter column** — `RIGHT_MARGIN` (left/right), `TOP_Y` (up/down), `RADIUS`,
  `TRACK_W`.
- **Wireless** — `WIFI` (empty = auto-detect the first wireless interface);
  `MAX_SPEED` = Mb/s that counts as a full speed ring.
- **Filesystems** — `FS_ROOT`, `FS_HOME`.
- **Fonts/sizes** — `DATE_FONT` / `DATE_SIZE`, `NP_FONT` / `NP_SIZE`,
  `LABEL_FONT` / `LABEL_SIZE`.

The window is sized in `WindingRingsrc` (`minimum_width/height`,
`maximum_width/height`); placement is `alignment` / `gap_x` / `gap_y`.

## Troubleshooting

- **Nothing draws?** Run in the foreground and watch for Lua errors:
  `conky -c ~/.conky/WindingRings/WindingRingsrc`
- **Spd / Qual sit at zero** — no wireless interface found; set `WIFI` explicitly.
- **Date font looks plain** — Santana isn't installed; harmless.
- **Won't move to the other monitor** — some launchers (e.g. ConkyManager) pick
  the monitor based on where the manager itself is opened; a full-screen dock
  window often ignores `xinerama_head`.

## Licence & credits

- Original design: **Alison Pitt (londonali1010)**, 2009 — the *Air Clock* and
  *Ring* widgets (<http://www.deviantart.com/londonali1010>), released under
  **CC BY-NC-SA 3.0**. This file is an independent single-script reimplementation.
- Reimplemented 2026 by **Wolvrik** in collaboration with AI assistants
  (Anthropic Claude and opencode Big Pickle).
- Because it reimplements that work, **this widget's Lua is shared under
  CC BY-NC-SA 3.0** (attribution, non-commercial, share-alike). The packaging and
  this README are MIT.
- Santana font: © Manfred Klein, 2004 (not bundled).
- Wallpaper `wallhaven-d6pjk3.png`: via wallhaven
  (<https://wallhaven.cc/w/d6pjk3>); AI-generated forest/fawn scene, uploaded by
  **Alx**.

Tested on Conky 1.12.2 / x86_64 (Bodhi Linux, Moksha desktop).
