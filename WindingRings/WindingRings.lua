--[[
  WindingRings -- glass "Air Clock" + date + winding S-curve meters
  ----------------------------------------------------------------------------
  Modern single-file Lua/Cairo reimplementation of two classic 2009 Conky
  widgets by Alison Pitt (londonali1010):

    * the "Air Clock" glass clock face (inspired by KDE 4.3's Air clock)
    * the "Ring" widget, here drawn as alternating semicircle "winding" meters

  Original designs and widget framework (c) 2009 Alison Pitt / londonali1010
  (http://www.deviantart.com/londonali1010), released under CC BY-NC-SA 3.0.
  This file is an independent reimplementation in a single script, with a
  live date rule, now-playing text and text labels; reimplemented 2026 with
  an AI assistant (Claude).

  Font: the date uses "Santana" (c) Manfred Klein, 2004 -- the same font the
  original widget used. If Santana is not installed, fontconfig substitutes a
  default face and the widget still runs.
]]

require 'cairo'
pcall(require, 'cairo_xlib')   -- needed on newer Conky builds, harmless on older

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------
-- Wireless interface used by the Spd / Qual meters. If left empty it is
-- auto-detected (the first interface with a /sys/class/net/*/wireless node);
-- hardcode it, e.g. "wlan0", if detection picks the wrong one.
local WIFI       = ""
local MAX_SPEED  = 300          -- Mb/s that counts as a "full" speed ring
local PIANOBAR_DIR = (os.getenv("HOME") or "") .. "/.config/pianobar/"  -- artist/title/album files
local NP_FONT    = "Ubuntu"
local NP_SIZE    = 15
local FS_ROOT    = "/"
local FS_HOME    = "/home"

local DATE_FMT   = "%A, %d %B %Y"
local DATE_FONT  = "Santana"   -- Santana is the original font.
local DATE_SIZE  = 38
local LABEL_FONT = "DejaVu Sans"
local LABEL_SIZE = 15
local LABEL_MAX_W    = 100      -- labels wider than this (px) shrink to fit
local LABEL_SHIFT    = 14       -- px labels sit away from the arc they are inside (raise for more gap)
local LABEL_MIN_SIZE = 10       -- ...but never below this font size

-- clock position/size (top-left of screen)
local CLOCK_X, CLOCK_Y, CLOCK_R = 113, 140, 95  -- The middle number adjusts the vertical position (higher number moves the clock lower, lower number raises clock higher. 110 was the original number in this version of the conky.

-- date text position
local DATE_X, DATE_Y = 230, 134  -- The date and now-playing text use DATE_Y separately, so they won't follow the clock. If you want them to line up with the lower clock, raise DATE_Y by the same amount.

-- winding meters: distance of the S-curve centreline from the right edge,
-- and the top of the first arc
local RIGHT_MARGIN = 81  -- Moves left and right (original 81)
local TOP_Y        = 140 -- Moves up and down (original 108)
local RADIUS       = 49.5
local TRACK_W      = 9
------------------------------------------------------------

-- auto-detect the wireless interface (first one with a /wireless node) when
-- WIFI is left empty above
local function detect_wifi()
    local p = io.popen("ls -d /sys/class/net/*/wireless 2>/dev/null")
    if not p then return "" end
    local iface = ""
    for line in p:lines() do
        iface = line:match("([^/]+)/wireless$") or ""
        if iface ~= "" then break end
    end
    p:close()
    return iface
end
if WIFI == "" then WIFI = detect_wifi() end

local PI = math.pi

-- one shared text-extents object for every text call in this file; per-call
-- cairo_text_extents_t:create() is leak class #1 in conky's lua-cairo
local TEXT_EXT = cairo_text_extents_t:create()

local function num(s)
    return tonumber(string.match(s or "", "[%d%.]+")) or 0
end

local function parse(s) return conky_parse(s) end

local function clamp(v) return math.max(0, math.min(1, v)) end

---------------------------- clock ---------------------------
local function draw_clock(cr)
    local cx, cy, R = CLOCK_X, CLOCK_Y, CLOCK_R

    -- outer glass ring
    cairo_arc(cr, cx, cy, R, 0, 2 * PI)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.20)
    cairo_fill_preserve(cr)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.55)
    cairo_set_line_width(cr, 2)
    cairo_stroke(cr)

    -- inner face with soft radial highlight
    local face = cairo_pattern_create_radial(cx - 20, cy - 25, 5, cx, cy, R * 0.80)
    cairo_pattern_add_color_stop_rgba(face, 0, 1, 1, 1, 0.50)
    cairo_pattern_add_color_stop_rgba(face, 1, 1, 1, 1, 0.22)
    cairo_arc(cr, cx, cy, R * 0.80, 0, 2 * PI)
    cairo_set_source(cr, face)
    cairo_fill_preserve(cr)
    cairo_pattern_destroy(face)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.45)
    cairo_set_line_width(cr, 1)
    cairo_stroke(cr)

    -- hands
    local t = os.date("*t")
    local sec  = t.sec
    local min  = t.min + sec / 60
    local hour = (t.hour % 12) + min / 60

    local function hand(angle, len, tail, width, r, g, b, a)
        local ax = math.sin(angle)
        local ay = -math.cos(angle)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_set_line_width(cr, width)
        cairo_set_source_rgba(cr, r, g, b, a)
        cairo_move_to(cr, cx - ax * tail, cy - ay * tail)
        cairo_line_to(cr, cx + ax * len,  cy + ay * len)
        cairo_stroke(cr)
    end

    hand(hour / 12 * 2 * PI, R * 0.50, 6, 4, 0.22, 0.22, 0.22, 0.9)
    hand(min  / 60 * 2 * PI, R * 0.70, 8, 3, 0.22, 0.22, 0.22, 0.9)
    hand(sec  / 60 * 2 * PI, R * 0.78, 12, 1, 0.35, 0.35, 0.35, 0.9)

    -- centre pin
    cairo_arc(cr, cx, cy, 3, 0, 2 * PI)
    cairo_set_source_rgba(cr, 0.22, 0.22, 0.22, 1)
    cairo_fill(cr)
end

----------------------------- date ---------------------------
local function draw_date(cr)
    local text = os.date(DATE_FMT)

    cairo_select_font_face(cr, DATE_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, DATE_SIZE)

    local ext = TEXT_EXT
    cairo_text_extents(cr, text, ext)

    -- soft shadow
    cairo_set_source_rgba(cr, 0, 0, 0, 0.35)
    cairo_move_to(cr, DATE_X + 1.5, DATE_Y + 1.5)
    cairo_show_text(cr, text)

    -- text
    cairo_set_source_rgba(cr, 1, 1, 1, 1)
    cairo_move_to(cr, DATE_X, DATE_Y)
    cairo_show_text(cr, text)

    -- the date line underneath
    local y = DATE_Y + 12
    local x2 = DATE_X + ext.x_advance + 14
    cairo_set_line_width(cr, 2)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
    cairo_set_source_rgba(cr, 0, 0, 0, 0.30)
    cairo_move_to(cr, DATE_X + 1, y + 1)
    cairo_line_to(cr, x2 + 1, y + 1)
    cairo_stroke(cr)
    cairo_set_source_rgba(cr, 1, 1, 1, 1)
    cairo_move_to(cr, DATE_X, y)
    cairo_line_to(cr, x2, y)
    cairo_stroke(cr)
end

------------------------- now playing ------------------------
local function read_line(name)
    local f = io.open(PIANOBAR_DIR .. name, "r")
    if not f then return "" end
    local s = f:read("*l") or ""
    f:close()
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function draw_nowplaying(cr)
    local artist = read_line("artist")
    local title  = read_line("title")
    local album  = read_line("album")
    if title == "" then return end

    local text = artist .. " - " .. title
    if album ~= "" then text = text .. " (" .. album .. ")" end

    local x, y = DATE_X + 4, DATE_Y + 38
    cairo_select_font_face(cr, NP_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, NP_SIZE)

    cairo_set_source_rgba(cr, 0, 0, 0, 0.35)
    cairo_move_to(cr, x + 1, y + 1)
    cairo_show_text(cr, text)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.95)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, text)
end

------------------------- winding meters ---------------------
-- side: 1 = bulges right, -1 = bulges left
local function arc_path(cr, cx, cy, side, frac)
    cairo_new_path(cr)   -- drop the leftover text point, or a stray line is drawn to the arc start
    if side == 1 then
        cairo_arc(cr, cx, cy, RADIUS, -PI / 2, -PI / 2 + PI * frac)
    else
        cairo_arc_negative(cr, cx, cy, RADIUS, -PI / 2, -PI / 2 - PI * frac)
    end
end

local function draw_segment(cr, cx, cy, side, frac, label)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
    cairo_set_line_width(cr, TRACK_W)

    -- track
    arc_path(cr, cx, cy, side, 1)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.28)
    cairo_stroke(cr)

    -- value
    if frac > 0 then
        arc_path(cr, cx, cy, side, frac)
        cairo_set_source_rgba(cr, 1, 1, 1, 0.92)
        cairo_stroke(cr)
    end

    -- label, centred inside the S
    cairo_select_font_face(cr, LABEL_FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    local size = LABEL_SIZE
    local ext = TEXT_EXT
    cairo_set_font_size(cr, size)
    cairo_text_extents(cr, label, ext)
    -- shrink long labels (e.g. "Spd 867 Mb/s") so they stay clear of the rings
    if ext.x_advance > LABEL_MAX_W then
        size = math.max(LABEL_MIN_SIZE, size * LABEL_MAX_W / ext.x_advance)
        cairo_set_font_size(cr, size)
        cairo_text_extents(cr, label, ext)
    end
    -- push the label away from the side the arc bulges toward
    local tx = cx - side * LABEL_SHIFT - ext.x_advance / 2
    local ty = cy + ext.height / 2
    cairo_set_source_rgba(cr, 0, 0, 0, 0.35)
    cairo_move_to(cr, tx + 1, ty + 1)
    cairo_show_text(cr, label)
    cairo_set_source_rgba(cr, 1, 1, 1, 0.85)
    cairo_move_to(cr, tx, ty)
    cairo_show_text(cr, label)
end

local function draw_winding(cr, w)
    local jx = w - RIGHT_MARGIN

    local cpu  = num(parse("${cpu cpu0}"))
    local mem  = num(parse("${memperc}"))
    local fsr  = num(parse("${fs_used_perc " .. FS_ROOT .. "}"))
    local fsh  = num(parse("${fs_used_perc " .. FS_HOME .. "}"))
    local spd  = num(parse("${wireless_bitrate " .. WIFI .. "}"))
    local qual = num(parse("${wireless_link_qual_perc " .. WIFI .. "}"))

    local items = {
        { "CPU "  .. string.format("%d%%", cpu),  cpu / 100 },
        { "MEM "  .. string.format("%d%%", mem),  mem / 100 },
        { "FS /R " .. string.format("%d%%", fsr), fsr / 100 },
        { "FS /H " .. string.format("%d%%", fsh), fsh / 100 },
        { "Spd "  .. string.format("%d Mb/s", spd), spd / MAX_SPEED },
        { "Qual " .. string.format("%d%%", qual), qual / 100 },
    }

    for i, it in ipairs(items) do
        local cy = TOP_Y + RADIUS + (i - 1) * (2 * RADIUS)
        local side = (i % 2 == 1) and 1 or -1
        draw_segment(cr, jx, cy, side, clamp(it[2]), it[1])
    end
end

------------------------------ main --------------------------
function conky_main()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, conky_window.width,
                                         conky_window.height)
    local cr = cairo_create(cs)

    draw_clock(cr)
    draw_date(cr)
    draw_nowplaying(cr)
    draw_winding(cr, conky_window.width)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
