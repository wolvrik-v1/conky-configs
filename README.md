# Conky Configurations

A collection of handcrafted **Lua/Cairo** Conky themes (modern `conky.config = {...}` /
`conky.text = [[...]]` syntax, tested on **Conky 1.12.2**, Bodhi Linux / Moksha).
Free to use, modify, and share.

> Several of these were built together with AI assistants over many live-tuning
> sessions, from original community designs. Attribution for the source designs
> is noted in each theme's README and preserved in each theme's files.

## Themes

The themes are organised into **families** that share a visual language. The
metal family is a cool black-metal gauge style; the etched family is a minimal
Etched-style stat/player/weather set; the cyber family is green-on-black
terminal. Classics keep their original brand names.

| Theme | Description |
| :--- | :--- |
| **metal-sysmon** | Full system monitor: title plate with ROOT/HOME half-ring gauges, 4 clock-style CPU speedometer dials with load %, PROCESSES, NETWORK. Cool black-metal finish. |
| **metal-clock** | The original jpope 2010 clock face with 12 long light-grey major ticks + 48 minors, hands emanating from the inner date/time/day circle. |
| **metal-pianobar** | Metal-gauge pianobar now-playing widget. |
| **etched** | Etched-style stat column (clock, CPU/RAM/temps, disks, network) with an Ubuntu-font face. |
| **etched-pianobar** | Minimal pianobar card (cyan accents, no panel): track, artist, album, progress, state dots, album art. |
| **etched-weather** | Horizontal weather card: NOW panel + details grid + full-width 5-day forecast row. OpenWeather API. |
| **cyber-deck** | Green-on-black cyberpunk terminal: hex CPU gauges, NET.SCOPE, telemetry, core bars, now-playing marquee, top processes. |
| **cyber-radar** | Standalone ADS-B radar scope reading the live `adsb_radar.py` daemon (feed: adsb.lol): rotating sweep, aircraft blips + callsigns. |
| **clockwidget** | Interactive analog clock + month calendar (click the LED to flip clock/calendar, auto-returns after 10 s). Original jpope 2010 face, modernised. |
| **clockwork-alchemist** | Steampunk wall clock: skeleton dial with gear train, brass steam pipes, copper boiler, PSI dial, thermometer, CPU/RAM gauges, six readout plaques. 100% procedural Cairo. |
| **bionic** | Classic "Steel Conky by Mucas V2.0" plate (243x887 artwork) with sector-ring gauges: CPU / MEM / WLAN / TIME / BATTERY / VOLUME. |

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
   # install the ~/.conky-style themes (clocks, monitors, radar and the cyber deck)
   cp -r ~/conky-configs/{metal-sysmon,metal-clock,clockwidget,clockwork-alchemist,bionic,cyber-deck,cyber-radar,etched} ~/.conky/
   # install the ~/.config themes (pianobar players + weather API widget)
   cp -r ~/conky-configs/{metal-pianobar,etched-pianobar,etched-weather} ~/.config/
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
the set: **HOOGE 05_54/53**, **DejaVu Sans Mono**, **Ubuntu**, **DS-Digital**
(all bundled in their theme folders).

## Support

Consider starring ⭐ this repo if you find something useful here.