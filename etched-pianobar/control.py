#!/usr/bin/env python3
"""Normalize existing Pianobar event files into a compact Conky cache."""

import fcntl
import math
import os
import signal
import sys
import time
from pathlib import Path


raw_home = os.environ.get("HOME")
HOME = Path(raw_home).expanduser() if raw_home else Path.home()

PIANOBAR_DIR = HOME / ".config/pianobar"
CACHE_DIR = HOME / ".cache/conky"
CACHE = CACHE_DIR / "pianobar-widget.status"
LOCK = CACHE_DIR / "pianobar-widget.lock"

DURATION_PATH = Path("/tmp/pianobar_duration")
START_PATH = Path("/tmp/pianobar_songstart")

# Override this if your Pianobar executable has a different basename.
PIANOBAR_PROCESS = os.environ.get("PIANOBAR_PROCESS") or "pianobar"

POLL_INTERVAL = 1.0
VALID_STATES = {"playing", "paused", "waiting", "stopped"}

stopping = False


def finite_number(value):
    return isinstance(value, (int, float)) and math.isfinite(value)


def clean(value):
    """Remove characters that could corrupt the cache format."""
    text = str(value if value is not None else "")

    text = text.translate({
        ord("\t"): " ",
        ord("\r"): " ",
        ord("\n"): " ",
        ord("|"): " ",
    })

    text = "".join(
        " " if ord(character) < 32 or ord(character) == 127
        else character
        for character in text
    )

    return " ".join(text.split())[:600]


def read_text(path, limit):
    try:
        return clean(path.read_text(encoding="utf-8", errors="replace")[:limit])
    except OSError:
        return ""


def read_number(path):
    text = read_text(path, 64)

    if not text:
        return None

    try:
        value = float(text)
    except (TypeError, ValueError):
        return None

    return value if math.isfinite(value) else None


def read_fields():
    return {
        "title": read_text(PIANOBAR_DIR / "title", 600),
        "artist": read_text(PIANOBAR_DIR / "artist", 600),
        "album": read_text(PIANOBAR_DIR / "album", 600),
        "duration": read_number(DURATION_PATH),
        "started": read_number(START_PATH),
    }


def pianobar_is_running():
    """Return whether the Pianobar executable is currently running.

    Pianobar leaves its metadata files behind after exiting. Checking the
    process list prevents the previous track from being displayed as active.
    """
    target = PIANOBAR_PROCESS

    if not Path("/proc").is_dir():
        return True

    try:
        for process in Path("/proc").iterdir():
            if not process.name.isdigit():
                continue

            try:
                name = (
                    process / "comm"
                ).read_text(
                    encoding="utf-8",
                    errors="replace",
                ).strip()
            except OSError:
                name = ""

            if name == target:
                return True

            try:
                arguments = (
                    process / "cmdline"
                ).read_bytes().split(b"\0")
            except OSError:
                continue

            for argument in arguments:
                if not argument:
                    continue

                argument_text = argument.decode(
                    "utf-8",
                    errors="replace",
                )

                try:
                    if Path(argument_text).name == target:
                        return True
                except (OSError, ValueError):
                    pass
    except OSError:
        return True

    return False


class Tracker:
    """Track progress and infer playing/paused state from position changes."""

    def __init__(self):
        self.identity = None
        self.last_position = None
        self.same_samples = 0
        self.state = "stopped"
        self.last_line = None

    def update(self, fields):
        title = fields["title"]
        artist = fields["artist"]
        album = fields["album"]
        duration = fields["duration"]
        started = fields["started"]

        output = fields.copy()
        position = None

        if not pianobar_is_running():
            self.identity = None
            self.last_position = None
            self.same_samples = 0
            self.state = "stopped"
            output["position"] = None
            return self.make(output, "stopped")

        if not title and not artist:
            self.identity = None
            self.last_position = None
            self.same_samples = 0
            self.state = "stopped"
            output["position"] = None
            return self.make(output, "stopped")

        if (
            duration is not None
            and duration > 0
            and started is not None
        ):
            position = time.time() - started
            position = max(0.0, min(position, duration))

        output["position"] = position

        identity = (title, artist, album, duration)

        if identity != self.identity:
            self.identity = identity
            self.last_position = position
            self.same_samples = 0
            self.state = "playing" if position is not None else "waiting"

        elif position is None:
            if self.state == "playing":
                self.state = "paused"
            elif self.state not in {"paused", "stopped"}:
                self.state = "waiting"

        else:
            if self.last_position is None:
                self.last_position = position
                self.same_samples = 0
                self.state = "playing"

            else:
                difference = position - self.last_position

                if difference > 0.25 or difference < -1.0:
                    self.last_position = position
                    self.same_samples = 0
                    self.state = "playing"

                else:
                    self.same_samples += 1

                    if self.same_samples >= 3:
                        self.state = "paused"

                    self.last_position = position

        return self.make(output, self.state)

    def make(self, fields, state):
        duration = fields.get("duration")
        position = fields.get("position")

        if not finite_number(duration):
            duration = 0.0

        if not finite_number(position):
            position = 0.0

        state = state if state in VALID_STATES else "stopped"

        if state == "stopped":
            position = 0.0

        return {
            "title": clean(fields.get("title", "")),
            "artist": clean(fields.get("artist", "")),
            "album": clean(fields.get("album", "")),
            "duration": duration,
            "position": position,
            "state": state,
        }

    def publish(self, result):
        line = "|".join((
            result["title"],
            result["artist"],
            result["album"],
            f"{result['duration']:g}",
            f"{result['position']:g}",
            result["state"],
        ))

        if line == self.last_line:
            return

        CACHE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)

        temporary = CACHE.with_name(
            f".{CACHE.name}.{os.getpid()}.tmp"
        )

        with temporary.open("w", encoding="utf-8") as handle:
            handle.write(line + "\n")

        os.chmod(temporary, 0o600)
        os.replace(temporary, CACHE)

        self.last_line = line


def run(once=False):
    tracker = Tracker()

    while not stopping:
        try:
            tracker.publish(tracker.update(read_fields()))
        except Exception:
            try:
                tracker.publish(tracker.make(read_fields(), "stopped"))
            except Exception:
                pass

        if once:
            break

        time.sleep(POLL_INTERVAL)


def acquire_lock():
    CACHE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)

    handle = None

    try:
        handle = LOCK.open("w", encoding="utf-8")
        fcntl.flock(
            handle.fileno(),
            fcntl.LOCK_EX | fcntl.LOCK_NB,
        )
    except (BlockingIOError, OSError):
        if handle is not None:
            try:
                handle.close()
            except Exception:
                pass
        return None

    return handle


def request_stop(_signum, _frame):
    global stopping
    stopping = True


def main():
    global stopping

    once = "--once" in sys.argv[1:]

    os.umask(0o077)

    lock = None if once else acquire_lock()

    if not once and lock is None:
        return 0

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    try:
        run(once)
    finally:
        if lock is not None:
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            except Exception:
                pass

            try:
                lock.close()
            except Exception:
                pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
