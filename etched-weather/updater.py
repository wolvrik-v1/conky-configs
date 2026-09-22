#!/usr/bin/env python3
"""Fetch OpenWeather 2.5 data and write a Lua cache for Conky."""

import json
import math
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None


raw_home = os.environ.get("HOME")
HOME = Path(raw_home).expanduser() if raw_home else Path.home()

WIDGET_DIR = HOME / ".config/etched-weather"
CACHE_DIR = HOME / ".cache/conky"

CACHE_PATH = CACHE_DIR / "etched_weather.lua"
ERROR_PATH = CACHE_DIR / "etched_weather.error"
KEY_PATH = WIDGET_DIR / "openweather.key"

LATITUDE = float(os.environ.get("OPENWEATHER_LAT", "40.519444"))
LONGITUDE = float(os.environ.get("OPENWEATHER_LON", "-80.008611"))

CURRENT_URL = "https://api.openweathermap.org/data/2.5/weather"
FORECAST_URL = "https://api.openweathermap.org/data/2.5/forecast"
REQUEST_TIMEOUT = 20


def clean(value):
    text = str(value if value is not None else "")
    text = text.translate({
        ord("\t"): " ",
        ord("\r"): " ",
        ord("\n"): " ",
    })
    text = "".join(
        " " if ord(character) < 32 or ord(character) == 127
        else character
        for character in text
    )
    return " ".join(text.split())[:160]


def finite_number(value):
    if isinstance(value, bool):
        return None

    try:
        value = float(value)
    except (TypeError, ValueError):
        return None

    return value if math.isfinite(value) else None


def read_api_key():
    environment_key = os.environ.get("OPENWEATHER_API_KEY", "").strip()

    if environment_key:
        return environment_key

    key_path = Path(
        os.environ.get("OPENWEATHER_KEY_FILE", str(KEY_PATH))
    ).expanduser()

    try:
        text = key_path.read_text(
            encoding="utf-8",
            errors="replace",
        )
    except OSError:
        return None

    for raw_line in text.splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#"):
            continue

        if "=" in line:
            line = line.split("=", 1)[1].strip()

        line = line.split("#", 1)[0].strip().strip("\"'")

        if line:
            return line

    return None


def lua_quote(value):
    text = str(value)
    output = []

    for character in text:
        code = ord(character)

        if character == "\\":
            output.append("\\\\")
        elif character == '"':
            output.append('\\"')
        elif character == "\n":
            output.append("\\n")
        elif character == "\r":
            output.append("\\r")
        elif character == "\t":
            output.append("\\t")
        elif code < 32 or code == 127:
            output.append("\\%03d" % code)
        else:
            output.append(character)

    return '"' + "".join(output) + '"'


def lua_value(value, indent=""):
    if value is None:
        return "nil"

    if isinstance(value, str):
        return lua_quote(value)

    if isinstance(value, bool):
        return "true" if value else "false"

    if isinstance(value, (int, float)):
        number = finite_number(value)
        return format(number, ".12g") if number is not None else "nil"

    if isinstance(value, list):
        if not value:
            return "{}"

        child_indent = indent + "  "
        lines = ["{"]

        for index, item in enumerate(value, 1):
            lines.append(
                f"{child_indent}[{index}] = "
                f"{lua_value(item, child_indent)},"
            )

        lines.append(indent + "}")
        return "\n".join(lines)

    if isinstance(value, dict):
        if not value:
            return "{}"

        child_indent = indent + "  "
        lines = ["{"]

        for key, item in value.items():
            lines.append(
                f"[{lua_quote(str(key))}] = "
                f"{lua_value(item, child_indent)},"
            )

        lines.append(indent + "}")
        return "\n".join(lines)

    return lua_quote(str(value))


def write_text_atomic(path, text, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_name(
        f".{path.name}.{os.getpid()}.tmp"
    )

    try:
        with temporary.open("w", encoding="utf-8") as handle:
            handle.write(text)

        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except OSError:
            pass


def write_cache(data):
    write_text_atomic(
        CACHE_PATH,
        "return " + lua_value(data) + "\n",
    )


def write_error(message):
    write_text_atomic(
        ERROR_PATH,
        clean(message) + "\n",
    )


def remove_file(path):
    try:
        path.unlink()
    except OSError:
        pass


def empty_current():
    return {
        "temp": None,
        "feels_like": None,
        "humidity": None,
        "pressure": None,
        "wind_speed": None,
        "wind_direction": None,
        "pop": None,
        "sunrise_text": None,
        "sunset_text": None,
        "condition": None,
        "icon_id": None,
    }


def fallback_data(message):
    return {
        "ok": False,
        "updated": time.time(),
        "updated_text": "--:--",
        "location": "PITTSBURGH AREA",
        "units": "imperial",
        "current": empty_current(),
        "daily": [],
        "message": clean(message),
    }


def local_datetime(timestamp, timezone_name="", timezone_offset=None):
    if timezone_name and ZoneInfo is not None:
        try:
            return datetime.fromtimestamp(
                timestamp,
                ZoneInfo(timezone_name),
            )
        except Exception:
            pass

    if timezone_offset is not None:
        try:
            return datetime.fromtimestamp(
                timestamp,
                timezone(timedelta(seconds=float(timezone_offset))),
            )
        except (TypeError, ValueError, OverflowError, OSError):
            pass

    return datetime.fromtimestamp(timestamp)


def format_clock(value, timezone_name="", timezone_offset=None):
    timestamp = finite_number(value)

    if timestamp is None:
        return "--:--"

    try:
        local_time = local_datetime(
            timestamp,
            timezone_name,
            timezone_offset,
        )
    except (OSError, OverflowError, ValueError):
        return "--:--"

    return local_time.strftime("%I:%M %p").lstrip("0")


def now_text(timezone_name="", timezone_offset=None):
    try:
        local_time = local_datetime(
            time.time(),
            timezone_name,
            timezone_offset,
        )
    except (OSError, OverflowError, ValueError):
        local_time = datetime.now()

    return local_time.strftime("%I:%M %p").lstrip("0")


def title_case(value):
    text = clean(value)

    if not text:
        return "Unknown"

    return " ".join(
        word[:1].upper() + word[1:]
        for word in text.split()
    )


def compass_direction(value):
    degrees = finite_number(value)

    if degrees is None:
        return ""

    degrees %= 360.0

    directions = (
        "N",
        "NNE",
        "NE",
        "ENE",
        "E",
        "ESE",
        "SE",
        "SSE",
        "S",
        "SSW",
        "SW",
        "WSW",
        "W",
        "WNW",
        "NW",
        "NNW",
    )

    index = int((degrees + 11.25) // 22.5) % 16
    return directions[index]


def current_from_payload(payload, timezone_name, timezone_offset):
    main = payload.get("main", {})
    wind = payload.get("wind", {})
    sys_data = payload.get("sys", {})
    weather_items = payload.get("weather", [])

    if not isinstance(main, dict):
        main = {}
    if not isinstance(wind, dict):
        wind = {}
    if not isinstance(sys_data, dict):
        sys_data = {}
    if not isinstance(weather_items, list):
        weather_items = []

    first_weather = (
        weather_items[0]
        if weather_items and isinstance(weather_items[0], dict)
        else {}
    )

    wind_degrees = finite_number(wind.get("deg"))

    return {
        "temp": finite_number(main.get("temp")),
        "feels_like": finite_number(main.get("feels_like")),
        "humidity": finite_number(main.get("humidity")),
        "pressure": finite_number(main.get("pressure")),
        "wind_speed": finite_number(wind.get("speed")) or 0.0,
        "wind_direction": compass_direction(wind_degrees),
        "pop": finite_number(payload.get("pop")),
        "sunrise_text": format_clock(
            sys_data.get("sunrise"),
            timezone_name,
            timezone_offset,
        ),
        "sunset_text": format_clock(
            sys_data.get("sunset"),
            timezone_name,
            timezone_offset,
        ),
        "condition": title_case(
            first_weather.get("description")
            or first_weather.get("main")
        ),
        "icon_id": int(
            finite_number(first_weather.get("id")) or 0
        ),
    }


def aggregate_forecast(items, timezone_name, timezone_offset):
    if not isinstance(items, list):
        return []

    groups = {}
    order = []

    try:
        today = local_datetime(
            time.time(),
            timezone_name,
            timezone_offset,
        ).date()
    except Exception:
        today = datetime.now().date()

    for item in items:
        if not isinstance(item, dict):
            continue

        timestamp = finite_number(item.get("dt"))

        if timestamp is None:
            continue

        try:
            local_date = local_datetime(
                timestamp,
                timezone_name,
                timezone_offset,
            ).date()
        except (OSError, OverflowError, ValueError):
            continue

        key = local_date.isoformat()

        if key not in groups:
            groups[key] = {
                "date": local_date,
                "temperatures": [],
                "pop": 0.0,
                "condition": "",
                "icon_id": 0,
            }
            order.append(key)

        group = groups[key]
        main = item.get("main", {})

        if isinstance(main, dict):
            temperature = finite_number(main.get("temp"))

            if temperature is not None:
                group["temperatures"].append(temperature)

        precipitation = finite_number(item.get("pop"))

        if precipitation is not None:
            group["pop"] = max(group["pop"], precipitation)

        weather_items = item.get("weather", [])

        if not isinstance(weather_items, list):
            weather_items = []

        first_weather = (
            weather_items[0]
            if weather_items and isinstance(weather_items[0], dict)
            else {}
        )

        if not group["condition"]:
            group["condition"] = title_case(
                first_weather.get("description")
                or first_weather.get("main")
            )

        icon_id = finite_number(first_weather.get("id"))

        if icon_id is not None:
            group["icon_id"] = int(icon_id)

    daily = []

    for index, key in enumerate(order[:5]):
        group = groups[key]
        temperatures = group["temperatures"]

        if not temperatures:
            continue

        day_label = (
            "Today"
            if group["date"] == today
            else group["date"].strftime("%a")
        )

        daily.append({
            "day": day_label,
            "condition": group["condition"] or "Unknown",
            "icon_id": group["icon_id"],
            "temp_min": min(temperatures),
            "temp_max": max(temperatures),
            "pop": group["pop"],
        })

    return daily


def build_data(current_payload, forecast_payload):
    if not isinstance(current_payload, dict):
        raise ValueError("invalid current-weather response")

    if not isinstance(forecast_payload, dict):
        forecast_payload = {}

    timezone_name = clean(current_payload.get("timezone"))
    timezone_offset = finite_number(current_payload.get("timezone"))

    if timezone_offset is None:
        city = forecast_payload.get("city", {})

        if isinstance(city, dict):
            timezone_offset = finite_number(city.get("timezone"))

    if timezone_offset is None:
        timezone_offset = 0

    current = current_from_payload(
        current_payload,
        timezone_name,
        timezone_offset,
    )

    daily = aggregate_forecast(
        forecast_payload.get("list", []),
        timezone_name,
        timezone_offset,
    )

    if current["pop"] is None:
        current["pop"] = daily[0]["pop"] if daily else 0.0

    location = clean(current_payload.get("name"))

    return {
        "ok": True,
        "updated": time.time(),
        "updated_text": now_text(
            timezone_name,
            timezone_offset,
        ),
        "location": location or "PITTSBURGH AREA",
        "units": "imperial",
        "current": current,
        "daily": daily,
        "message": "",
    }


def fetch_json(url, parameters):
    separator = "&" if "?" in url else "?"
    request_url = url + separator + urllib.parse.urlencode(parameters)

    request = urllib.request.Request(
        request_url,
        headers={
            "Accept": "application/json",
            "User-Agent": "EtchedWeatherConky/1.0",
        },
    )

    with urllib.request.urlopen(
        request,
        timeout=REQUEST_TIMEOUT,
    ) as response:
        payload = json.load(response)

    if isinstance(payload, dict):
        code = payload.get("cod")

        if code not in (None, 200, "200"):
            raise ValueError(f"OpenWeather returned {code}")

    return payload


def describe_error(error):
    if isinstance(error, urllib.error.HTTPError):
        try:
            detail = error.read(256).decode(
                "utf-8",
                errors="replace",
            )
        except Exception:
            detail = ""

        detail = clean(detail)
        suffix = f": {detail}" if detail else ""
        return f"HTTP {error.code}{suffix}"

    if isinstance(error, urllib.error.URLError):
        return "network error"

    return clean(error) or "unknown error"


def main():
    api_key = read_api_key()

    if not api_key:
        message = "OpenWeather API key is missing"
        write_error(message)

        if not CACHE_PATH.exists():
            write_cache(fallback_data(message))

        print(message, file=sys.stderr)
        return 2

    parameters = {
        "lat": f"{LATITUDE:.6f}",
        "lon": f"{LONGITUDE:.6f}",
        "units": "imperial",
        "appid": api_key,
    }

    try:
        current_payload = fetch_json(
            CURRENT_URL,
            parameters,
        )
    except Exception as error:
        message = describe_error(error)
        write_error(message)

        if not CACHE_PATH.exists():
            write_cache(fallback_data(message))

        print(
            f"Current weather update failed: {message}",
            file=sys.stderr,
        )
        return 1

    forecast_payload = {"list": []}
    forecast_error = None

    try:
        forecast_payload = fetch_json(
            FORECAST_URL,
            parameters,
        )
    except Exception as error:
        forecast_error = describe_error(error)

    try:
        data = build_data(current_payload, forecast_payload)
        write_cache(data)
        remove_file(ERROR_PATH)
    except Exception as error:
        message = describe_error(error)
        write_error(message)

        if not CACHE_PATH.exists():
            write_cache(fallback_data(message))

        print(
            f"Weather cache update failed: {message}",
            file=sys.stderr,
        )
        return 1

    if forecast_error:
        print(
            "Current weather updated; forecast unavailable: "
            + forecast_error,
            file=sys.stderr,
        )
    else:
        print("Weather cache updated")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
