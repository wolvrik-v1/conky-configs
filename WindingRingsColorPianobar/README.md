# WindingRingsColorPianobar

A **pianobar now-playing panel** for Conky — album art, track / artist / album
lines, a live progress bar and elapsed / total times, drawn in a single
Lua/Cairo widget and tinted with the most vibrant colour from your wallpaper.
It is the companion to [WindingRingsColor](../WindingRingsColor) and sits in the
bottom-left corner of the screen, so it does **not** cover the monitor the way
the full-screen clock does.

100% procedural drawing after one cached image conversion — the cover art is the
only raster input, and it is resized locally so the panel stays crisp at any
screen size.

```
┌──────────────────────────────────────────────────┐
│  NOW PLAYING                                     │
│ ──────────────────────────────────────────────── │
│  ┌────────┐   TRACK                               │
│  │        │   Quiet Village (1996 D…               │
│  │  art   │   ARTIST                              │
│  │        │   Martin Denny                        │
│  └────────┘   ALBUM                               │
│               ALBUM   Quiet Village               │
│  PROGRESS                                        │
│  ▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░                  │
│  0:29                                    3:42     │
└──────────────────────────────────────────────────┘
```

## What it shows

| Element | Source |
| --- | --- |
| **Album art** | `~/.config/pianobar/coverArt.jpg`, cached to a 280×280 PNG |
| **TRACK / ARTIST / ALBUM** | the pianobar status bridge (see *Requirements*) |
| **Progress bar** | `position` / `duration` from the same status file |
| **Elapsed / total** | formatted from `position` and `duration`, DS-Digital font |
| **State** | `PLAYING`, `PAUSED`, `WAITING`, `STOPPED` (changes the accent colour) |
| **Accent colour** | most vibrant entry in `~/.cache/wal/colors.json` (pywal), else cyan |

Long text is automatically shortened to fit its column, so titles never spill over
the panel edge.

## Requirements

| Needed for | What you need |
| --- | --- |
| The widget itself | **Conky 1.12.x** with Lua + Cairo support, on **X11** (not Wayland) |
| Playback + metadata | **pianobar** (writes `~/.config/pianobar/{title,artist,album,coverArt.jpg}`) |
| The track/artist/album lines | **Python 3** and the **bundled status bridge** (below) |
| Cover art | **ImageMagick** (`convert`) — one-time resize, then cached |
| Wallpaper accent | Optional **pywal** |
| Fonts | **Ubuntu** (bundled elsewhere in this repo); **DS-Digital** optional (not bundled) |

### The status bridge (required)

Pianobar writes loose event files; Conky needs one tidy line. The bridge bundled in
`scripts/` does that, writing `~/.cache/conky/pianobar-widget.status`:

```
title|artist|album|duration|position|state
```

Start it once and keep it alive:

```sh
~/.conky/WindingRingsColorPianobar/scripts/ensure_bridge.sh
```

`ensure_bridge.sh` starts `scripts/pianobar_control.py` only if it isn't already
running, so it is safe to run as often as you like. The usual setup is a login
autostart entry plus a once-a-minute cron watchdog:

```cron
@reboot  $HOME/.conky/WindingRingsColorPianobar/scripts/ensure_bridge.sh
* * * *  $HOME/.conky/WindingRingsColorPianobar/scripts/ensure_bridge.sh
```

The bridge is flock-guarded, so a second copy exits by itself; it logs to
`~/.cache/conky/pianobar-bridge.log`. **Without it the panel shows *No Music
Playing*.** If you already run `~/.config/pianobar-widget/pianobar_control.py` for
other Conky widgets, that is the same program — one bridge is enough for all of
them, and `ensure_bridge.sh` will detect it and do nothing.

### Wallpaper accent with pywal (optional)

The panel tints itself from the most vibrant colour in `~/.cache/wal/colors.json`.
Generate that palette from any image:

```sh
wal -i ~/Pictures/your-wallpaper.jpg
```

Install `pywal` from your distro (`pywal` on Arch, `python-pywal` on Debian/Ubuntu)
or with `pipx install pywal`. Without it everything still works — the accent is
just the default cyan `#00fff9`. Note that pywal applies the palette desktop-wide,
so your terminal colours change too; this widget only reads the file.

## Install

```sh
mkdir -p ~/.conky && cp -r WindingRingsColorPianobar ~/.conky/WindingRingsColorPianobar
```

Launch:

```sh
conky -d -c ~/.conky/WindingRingsColorPianobar/WindingRingsColorPianobar.conf
```

or use the wrapper:

```sh
~/.conky/WindingRingsColorPianobar/WindingRingsColorPianobar start|stop|restart|status
```

The panel is a 440×270 transparent dock placed at `bottom_left` with `gap_x 45` /
`gap_y 20`. Change `alignment` / `gap_x` / `gap_y` in the `.conf` to move it — this
widget is not full-screen, so it can live wherever you like.

### Fonts

- **Ubuntu** for the header and track / artist / album text (bundled elsewhere in
  this repository under the Ubuntu Font Licence 1.0 — see `ATTRIBUTION.md`).
- **DS-Digital** for the elapsed / total times. It is **not bundled** (shareware;
  see `ATTRIBUTION.md`). If it isn't installed, fontconfig substitutes a default
  face and the widget still runs.

## How the cover art works

`~/.config/pianobar/coverArt.jpg` is resized with ImageMagick to 280×280 and cached
at `~/.cache/conky/windrings_pianobar_cover.png`, then drawn inside a 133×133
frame. The conversion only reruns when the source JPEG's modification time
changes, so it costs nothing between tracks.

## Tuning

All of the panel's controls are the constant block at the top of
`WindingRingsColorPianobar.lua`:

- **Panel size/margins** — `PANEL_WIDTH`, `PANEL_HEIGHT`, `X`, `MARGIN`.
- **Cover position/size** — `COVER_X`, `COVER_Y`, `COVER_SIZE`.
- **Cover cache/locations** — `COVER_JPG`, `COVER_PNG`, `COVER_MARKER`.
- **Status file** — `CACHE_PATH` (and `STATUS_CMD` / `STATUS_PATTERN` if your
  bridge writes a different format).

Window size and placement live in `WindingRingsColorPianobar.conf`
(`minimum_width`, `minimum_height`, `alignment`, `gap_x`, `gap_y`).

## Troubleshooting

- **Nothing draws?** Run in the foreground and watch for Lua errors:
  `conky -c ~/.conky/WindingRingsColorPianobar/WindingRingsColorPianobar.conf`
- **"No Music Playing" but pianobar is running** — the status bridge isn't
  running. Start `~/.config/pianobar-widget/pianobar_control.py` (or run
  `ensure_bridge.sh`) and check `~/.cache/conky/pianobar-widget.status` exists.
- **Cover art is blank** — ImageMagick `convert` is missing, or
  `~/.config/pianobar/coverArt.jpg` doesn't exist yet (pianobar only writes it once
  a track with art is playing).
- **Accent stays cyan** — pywal isn't installed or `~/.cache/wal/colors.json`
  hasn't been generated; regenerate your pywal palette.
- **Times look plain** — DS-Digital isn't installed; harmless.
- **Wrong position** — edit `alignment` / `gap_x` / `gap_y` in the `.conf`; a dock
  window can also ignore `xinerama_head` on multi-monitor setups.

## Licence & credits

- Part of the **WindingRings Color** set, whose shading and palette language follow
  [WindingRingsColor](../WindingRingsColor). That line descends from the 2009
  **Air Clock** and **Ring** widgets by **Alison Pitt (londonali1010)**
  (<http://www.deviantart.com/londonali1010>), released under **CC BY-NC-SA 3.0**.
- Single-file reimplementation 2026 by **Wolvrik** in collaboration with AI
  assistants (Anthropic Claude and opencode Big Pickle).
- Because it derives from that work, **this widget's Lua is shared under
  CC BY-NC-SA 3.0** (attribution, non-commercial, share-alike). The packaging and
  this README are MIT.
- Ubuntu font: © 2010 Canonical Ltd., design by Dalton Maag, UFL 1.0.
- DS-Digital font: © Dusit Supasawat (not bundled).
- Wallpapers: `ParisColorful.jpg` and `IslandWarmEvening.jpg` are bundled as
  supplied by the author; see [`ATTRIBUTION.md`](../ATTRIBUTION.md) for the
  per-file provenance notes.

> The screenshot is a crop of the bottom-left panel from a full desktop capture,
> so it shows the widget and its wallpaper rather than the whole screen.

Tested on Conky 1.12.2 / x86_64 (Bodhi Linux, Moksha desktop).
