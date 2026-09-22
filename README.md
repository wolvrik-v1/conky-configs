# Conky Configurations

A collection of handcrafted **Lua/Cairo** Conky themes (modern `conky.config = {...}` /
`conky.text = [[...]]` syntax, tested on **Conky 1.12.2**, Bodhi Linux / Moksha).
Free to use, modify, and share.

> Several of these were built together with AI assistants over many live-tuning
> sessions, from original community designs. Attribution for the source designs
> is noted in each theme's README and preserved in each theme's files.

## Themes

| Theme | Description |
| :--- | :--- |
| **metalsysmonitor** | Full system monitor: title plate with ROOT/HOME half-ring gauges, 4 clock-style CPU speedometer dials with load %, PROCESSES, NETWORK. Cool black-metal finish. |
| **clockwork-alchemist** | Steampunk wall clock: skeleton dial with gear train, brass steam pipes, copper boiler, PSI dial, thermometer, CPU/RAM gauges, six readout plaques. 100% procedural Cairo. |
| **bionic** | Classic "Steel Conky by Mucas V2.0" plate (243x887 artwork) with sector-ring gauges: CPU / MEM / WLAN / TIME / BATTERY / VOLUME. |
| **cyberdeck** | Green-on-black cyberpunk terminal: hex CPU gauges, NET.SCOPE, telemetry, core bars, now-playing marquee, top processes. |
| **adsbradar** | Standalone ADS-B radar scope reading the live `adsb_radar.py` daemon (feed: adsb.lol): rotating sweep, aircraft blips + callsigns. |
| **zenclock** | Minimal dark meditation timer: big digital clock, START/PAUSE/RESET/GOAL buttons (GTK click overlay), gong + 10-minute chimes. |
| **clockwidget** | Interactive analog clock + month calendar (click the LED to flip clock/calendar, auto-returns after 10 s). Original jpope 2010 face, modernised. |
| **clockwidget-orig** | The original jpope face with 12 long light-grey major ticks + 48 minors, hands emanating from the inner date/time/day circle. |
| **etched** | Etched-style stat column (clock, CPU/RAM/temps, disks, network). Ships a DS-Digital face and an Ubuntu-font variant. |
| **alfirk** | Pianobar now-playing widget: 12-bar CAVA spectrum, progress bar, artist/title/album, cover art. |
| **pickle-pianobar** | Minimal pianobar card (cyan accents, no panel): track, artist, album, progress, state dots, album art. |
| **pickle-weather** | Horizontal weather card: NOW panel + details grid + full-width 5-day forecast row. OpenWeather API. |
| **metal-pianobar** | Metal-gauge pianobar now-playing widget. |

## Installation

1. **Install dependencies** (Debian/Ubuntu/Mint):
   ```bash
   sudo apt install conky-all lua5.1 fonts-font-awesome
   ```
   Each theme lists its extra runtime deps (e.g. `cava`, `pianobar`, `pactl`,
   `python3`) in its own README.
2. **Clone this repo**:
   ```bash
   git clone https://github.com/wolvrik-v1/conky-configs.git ~/conky-configs
   # install the ~/.conky-style themes (the clock, monitor and weather/wall widgets)
   cp -r ~/conky-configs/{metalsysmonitor,clockwork-alchemist,bionic,cyberdeck,adsbradar,zenclock,clockwidget,clockwidget-orig,etched,alfirk} ~/.conky/
   # install the ~/.config themes (pianobar players + weather API widget)
   cp -r ~/conky-configs/{pickle-pianobar,pickle-weather,metal-pianobar} ~/.config/
   ```
3. **Run a theme**: read that theme's README (each one has launch + tuning notes).
   Most ship a `./<name>` start/stop/restart wrapper or launch with:
   ```bash
   conky -c ~/.conky/<theme>/<config>
   ```
   *(Tip: create a `.desktop` file in `~/.config/autostart/` to run on login.)*

## Updating this repo (after editing a widget)

```bash
cd ~/conky-configs
./sync.sh --apply    # pull changes from the live widget dirs into the tree
git add .
git commit -m "Update: ..."
git push
```

`sync.sh` only copies the curated widgets from their live install dirs
(`~/.conky`, `~/.config`) into this staging tree — it never deletes anything
live. Runtime logs, backups, session state and API keys are always excluded.

## Fonts

Themes need their bundled `fonts/` installed system-wide or placed in
`~/.local/share/fonts/` and refreshed with `fc-cache -fv`. Fonts used across
the set: **HOOGE 05_54/53**, **DejaVu Sans Mono**, **Comfortaa**, **Ubuntu**,
**DS-Digital**, **feather**, **Material** (all bundled in their theme folders).

## Support

Consider starring ⭐ this repo if you find something useful here.