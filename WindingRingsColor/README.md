# WindingRingsColor

A full-screen **colourised "Air Clock" desktop** for Conky — the glass Air Clock,
a live date rule, a now-playing line and six **winding S-curve meters**, all in a
single Lua/Cairo widget. It is a modern single-file reimplementation of two classic
2009 widgets by Alison Pitt (**londonali1010**): the **Air Clock** glass face and
the **Ring** meters (here drawn as alternating semicircle "winding" curves).

Where the original [WindingRings](../WindingRings) keeps everything white on
transparent, this variant **samples an accent colour from your wallpaper** (via
the pywal cache) and tints the clock hands and meter arcs with it. It is still
100% procedural Lua/Cairo — no images, no bundled fonts — and it covers the whole
screen (1920×1080 by default) so it sits directly on the desktop.

```
        ╭─────────╮
       │   ✛      │            CPU 11% ▓▓▓▓▓░░░░
       │  glass   │              ░░░░░▓▓▓▓▓ MEM 42%
       │  clock   │            FS /R 16% ...
       ╰─────────╯            (six S-curves alternate down the right side)
   Wednesday, 11 November 2026
   Artist - Title (Album)
```

## ⚠️ Heads-up: it covers the whole monitor

The clock and the rings are **one** Conky window that spans the full screen as a
transparent dock. Because it covers the entire monitor, it can **swallow mouse
events aimed at the desktop** — desktop icons, right-clicks on the wallpaper, and
the desktop itself may stop responding while the widget is running. Ordinary
application windows above it still receive their clicks normally.

If you need the desktop back, stop the widget (see *Install* / the wrapper). If you
only want the widget on one monitor in a multi-monitor setup, set the window size
in `WindingRingsColor.conf` to that monitor's resolution and adjust `alignment` /
`gap_x` / `gap_y`.

**X11 only.** This widget uses Conky's X11/Cairo drawing path (`cairo_xlib`) and a
transparent dock window. It will not work as-is on a Wayland session.

## What it shows

| Element | Source |
| --- | --- |
| **Glass clock** (top-left) | hour / minute / second hands from the system clock |
| **Date** | `%A, %d %B %Y` (e.g. *Wednesday, 11 November 2026*), Santana font |
| **Now playing** | pianobar `artist` / `title` / `album` text files |
| **CPU** | `${cpu cpu0}` |
| **MEM** | `${memperc}` |
| **FS /R · FS /H** | `${fs_used_perc}` for `/` and `/home` |
| **Spd** | wireless bitrate (Mb/s), scaled to `MAX_SPEED` |
| **Qual** | wireless link quality % |

The six meters alternate bulge-right / bulge-left down the right side of the
screen; each is an S-curve arc that fills with its value. Each label is shortened
automatically if it would run into the rings.

### Accent colour

The hands and meter arcs use the most **vibrant** colour found in your wallpaper's
pywal palette:

- read from `~/.cache/wal/colors.json` (`color1` … `color15`), scored by
  saturation plus brightness;
- if pywal isn't installed or hasn't generated a palette, it falls back to a
  bright cyan `#00fff9`.

Nothing breaks without pywal — you just get the default cyan.

> **Bonus: your terminal gets the same colour treatment.** Because pywal generates
> one palette for the whole desktop, setting a wallpaper with pywal also recolours
> your terminal. This widget only *reads* `~/.cache/wal/colors.json` — it never
> writes anything — but if you already like the accent here, you'll probably love
> the matching terminal palette too. (An unexpected side effect the author ended up
> loving.)

## Requirements

- **Conky 1.12.x** with Lua + Cairo support.
- **X11** (not Wayland).
- Optional: **pianobar** for the now-playing line (artist/title/album files in
  `~/.config/pianobar/`).
- Optional: a **wireless interface** for the Spd / Qual meters.
- Optional: **pywal** for wallpaper-matched accent colour.

## Install

```sh
mkdir -p ~/.conky && cp -r WindingRingsColor ~/.conky/WindingRingsColor
```

Launch:

```sh
conky -d -c ~/.conky/WindingRingsColor/WindingRingsColor.conf
```

or use the wrapper:

```sh
~/.conky/WindingRingsColor/WindingRingsColor start|stop|restart|status
```

> **Set the window to your monitor.** `WindingRingsColor.conf` is written for
> 1920×1080. Change `minimum_width`, `maximum_width` and `minimum_height` to your
> resolution before launching, or the widget will be the wrong size.

### Fonts

- **Santana** (© Manfred Klein, 2004 — <https://www.dafont.com/santana.font>) is
  used for the date. It is **not bundled** (redistribution terms are unclear); if
  it isn't installed, fontconfig substitutes a default face and everything still
  runs.
- **Ubuntu** is used for the now-playing line.
- **DejaVu Sans** is used for the meter labels.

## Wallpapers

Two desktop backgrounds are bundled in `wallpapers/`, both 1376×768:

- `ParisColorful.jpg` — the colourful Paris scene used in the screenshot;
- `IslandWarmEvening.jpg` — a warm island view that pairs well with the accent
  sampling.

## Tuning

All of the widget's own controls are the constant block near the top of
`WindingRingsColor.lua`:

- **Clock position/size** — `CLOCK_X`, `CLOCK_Y`, `CLOCK_R`.
- **Date / now-playing position** — `DATE_X`, `DATE_Y`.
- **Meter column** — `RIGHT_MARGIN` (left/right), `TOP_Y` (up/down), `RADIUS`,
  `TRACK_W`.
- **Wireless** — `WIFI` (empty = auto-detect the first wireless interface);
  `MAX_SPEED` = Mb/s that counts as a full speed ring.
- **Filesystems** — `FS_ROOT`, `FS_HOME`.
- **Fonts/sizes** — `DATE_FONT` / `DATE_SIZE`, `NP_FONT` / `NP_SIZE`,
  `LABEL_FONT` / `LABEL_SIZE`; `LABEL_MAX_W`, `LABEL_SHIFT`, `LABEL_MIN_SIZE`
  control how labels shrink and where they sit inside the arcs.

Window size and placement live in `WindingRingsColor.conf` (`minimum_width`,
`maximum_width`, `minimum_height`, `alignment`, `gap_x`, `gap_y`).

## Troubleshooting

- **Nothing draws?** Run in the foreground and watch for Lua errors:
  `conky -c ~/.conky/WindingRingsColor/WindingRingsColor.conf`
- **The desktop / icons won't respond to clicks** — that's the full-screen
  transparent window (see the heads-up above). Stop the widget to get the desktop
  back, or shrink it to one monitor.
- **Spd / Qual sit at zero** — no wireless interface was found; set `WIFI`
  explicitly (e.g. `"wlan0"`).
- **Accent stays cyan** — pywal isn't installed or `~/.cache/wal/colors.json`
  hasn't been generated yet; regenerate your pywal palette.
- **Now playing is empty** — pianobar isn't running, or
  `~/.config/pianobar/{artist,title,album}` don't exist.
- **Date font looks plain** — Santana isn't installed; harmless.
- **Won't move to the other monitor** — some launchers pick the monitor based on
  where the manager was opened; a full-screen dock window often ignores
  `xinerama_head`, so set the window size and gaps for the monitor you want.

## Licence & credits

- Original design: **Alison Pitt (londonali1010)**, 2009 — the *Air Clock* and
  *Ring* widgets (<http://www.deviantart.com/londonali1010>), released under
  **CC BY-NC-SA 3.0**. This file is an independent single-script reimplementation.
- Colourised variant, reimplemented 2026 by **Wolvrik** in collaboration with AI
  assistants (Anthropic Claude and opencode Big Pickle).
- Because it derives from that work, **this widget's Lua is shared under
  CC BY-NC-SA 3.0** (attribution, non-commercial, share-alike). The packaging and
  this README are MIT.
- Santana font: © Manfred Klein, 2004 (not bundled).
- Wallpapers: `ParisColorful.jpg` and `IslandWarmEvening.jpg` are bundled as
  supplied by the author; see [`ATTRIBUTION.md`](../ATTRIBUTION.md) for the
  per-file provenance notes.

Tested on Conky 1.12.2 / x86_64 (Bodhi Linux, Moksha desktop).
