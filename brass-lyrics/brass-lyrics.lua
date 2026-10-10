-- ############################################################
--  brass-lyrics -- Steampunk brass lyrics display
--  Round brass shell (orrery-brass / brass-sysmon family) with a
--  STRAIGHT-LINE karaoke readout in the dial's core: PREV / ACTIVE /
--  NEXT ride centred rows (long active lines wrap onto a second row)
--  while a copper sweep traces the graduated dial channel as the
--  song plays. The ring nest is framing only. Driven by the pianobar
--  status position + an LRCLIB LRC cache.
--  Grid 280x280 -- the rc asks for 332 so the dock lands at ~340.
-- ############################################################

require 'cairo'

-- ======================= DESIGN GRID =========================
local GRID_W = 280
local GRID_H = 280

-- ======================= PALETTE (Patinated Antique Brass) ===
local CREAM     = { 0xf2, 0xe8, 0xd4 }
local BRASS_BRT = { 0xdb, 0xb2, 0x7f }
local BRASS_MID = { 0x9f, 0x7f, 0x58 }
local COPPER    = { 0xcc, 0x95, 0x52 }
local PATINA    = { 0x4c, 0x38, 0x22 }
local DARK_IRON = { 0x12, 0x16, 0x1c }
local RUST_DIM  = { 0x6b, 0x55, 0x3b }

local FSANS = 'DejaVu Sans'
local FMONO = 'DejaVu Sans Mono'
local S = 1

-- ONE module-level text-extents object, shared by every measurement in
-- this file. Per-call cairo_text_extents_t:create() is leak class #1 in
-- this codebase -- never allocate one per text call.
local TEXT_EXT = cairo_text_extents_t:create()

-- ======================= PATHS (user-agnostic) ===============
local HOME       = os.getenv('HOME') or ''
local CACHE_DIR  = HOME .. '/.cache/conky'
local STATUS_PATH = CACHE_DIR .. '/pianobar-widget.status'
local META_PATH    = CACHE_DIR .. '/brass-lyrics.meta'
local LRC_PATH     = CACHE_DIR .. '/brass-lyrics.lrc'

-- ======================= HELPERS =============================
local function set_c(cr, c, a)
    cairo_set_source_rgba(cr, c[1]/255, c[2]/255, c[3]/255, a or 1)
end

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function rrect(cr, x, y, w, h, r)
    if r > w/2 then r = w/2 end
    if r > h/2 then r = h/2 end
    cairo_new_sub_path(cr)
    cairo_arc(cr, x+w-r, y+r,    r, -math.pi/2, 0)
    cairo_arc(cr, x+w-r, y+h-r, r, 0,          math.pi/2)
    cairo_arc(cr, x+r,   y+h-r, r, math.pi/2,  math.pi)
    cairo_arc(cr, x+r,   y+r,    r, math.pi,    3*math.pi/2)
    cairo_close_path(cr)
end

local function draw_rivet(cr, x, y)
    set_c(cr, BRASS_BRT, 0.85)
    cairo_new_path(cr)
    cairo_arc(cr, x*S, y*S, 1.5*S, 0, 2*math.pi)
    cairo_fill(cr)
    set_c(cr, DARK_IRON, 0.9)
    cairo_set_line_width(cr, 0.45*S)
    cairo_new_path(cr)
    cairo_arc(cr, x*S, y*S, 1.5*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

-- ======================= STARFIELD ==========================
-- Same measured star field as brass-sysmon / brassviz / orrery-brass.
-- Seeded ONCE and cached, so it is identical every frame.
local STAR_TINT  = { 0xc6, 0xd6, 0xeb }
local STAR_AREA  = 224
local STAR_ALPHA = { faint = 0.050, dim = 0.105, mid = 0.240, bright = 0.330 }
local STAR_RAD   = { faint = 1.2,  dim = 1.5,  mid = 1.9,  bright = 2.4 }
local STAR_DR    = { faint = 0.7,  dim = 0.7,  mid = 0.7,  bright = 1.0 }
local STAR_CUT   = { 0.42, 0.84, 0.92, 1.01 }
local STAR_BAND  = { 'faint', 'dim', 'mid', 'bright' }

local STAR_TBL, STAR_W, STAR_H = nil, 0, 0

-- Numerical-Recipes LCG: exact in a double, no bitwise ops.
local function make_rng(seed)
  return function()
    seed = (seed * 1664525 + 1013904223) % 4294967296
    return seed / 4294967296
  end
end

local function build_stars(w, h)
  local rng = make_rng(0x5EEDB2)
  local n = math.floor((w * h) / STAR_AREA)
  local t = {}
  for i = 1, n do
    local roll = rng()
    local b = 4
    for k = 1, 4 do
      if roll < STAR_CUT[k] then b = k break end
    end
    local name = STAR_BAND[b]
    t[i] = { rng(), rng(),
             STAR_RAD[name] + rng() * STAR_DR[name],
             STAR_ALPHA[name] }
  end
  STAR_TBL, STAR_W, STAR_H = t, w, h
end

local function starfield(cr, x, y, w, h, r)
  if not STAR_TBL or #STAR_TBL == 0 then return end
  cairo_save(cr)
  rrect(cr, x, y, w, h, r)
  cairo_clip(cr)
  local x1, y1 = x + w, y + h
  for i = 1, #STAR_TBL do
    local s = STAR_TBL[i]
    local sx, sy = s[1] * STAR_W, s[2] * STAR_H
    if sx > x - 4 and sx < x1 + 4 and sy > y - 4 and sy < y1 + 4 then
      cairo_set_source_rgba(cr, STAR_TINT[1]/255, STAR_TINT[2]/255,
                            STAR_TINT[3]/255, s[4])
      cairo_arc(cr, sx, sy, s[3], 0, 2 * math.pi)
      cairo_fill(cr)
    end
  end
  cairo_restore(cr)
end

-- ======================= TEXT ================================
local function text_at(cr, x, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    set_c(cr, col, 1)
    cairo_select_font_face(cr, mono and FMONO or FSANS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    cairo_move_to(cr, x * S, y * S)
    cairo_show_text(cr, str)
end

local function text_c(cr, cx, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    set_c(cr, col, 1)
    cairo_select_font_face(cr, mono and FMONO or FSANS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    cairo_text_extents(cr, str, TEXT_EXT)
    local w = (TEXT_EXT.width + TEXT_EXT.x_bearing) / S   -- px -> grid units
    cairo_move_to(cr, (cx - w/2) * S, y * S)
    cairo_show_text(cr, str)
end

-- Centered text that shrinks to fit `maxw` (down to `minsz`), then trims
-- with an ellipsis as a last resort. Keeps long track titles / lyric lines
-- inside the round plate at every seat.
local function fit_c(cr, cx, y, str, col, size, maxw, mono, bold, minsz)
    if not str or str == '' then return end
    minsz = minsz or 7
    local s = str

    local function measure(sz, txt)
        cairo_select_font_face(cr, mono and FMONO or FSANS,
                               CAIRO_FONT_SLANT_NORMAL,
                               bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, sz * S)
        cairo_text_extents(cr, txt, TEXT_EXT)
        return (TEXT_EXT.width + TEXT_EXT.x_bearing) / S   -- px -> grid units
    end

    while size > minsz and measure(size, s) > maxw do
        size = size - 0.5
    end
    if measure(size, s) > maxw then
        while #s > 1 do
            s = s:sub(1, #s - 1):gsub('%s+$', '')
            s = s:gsub('…$', '') .. '…'
            if measure(size, s) <= maxw then break end
        end
    end

    set_c(cr, col, 1)
    local w = measure(size, s)
    cairo_move_to(cr, (cx - w/2) * S, y * S)
    cairo_show_text(cr, s)
end

-- Fixed-size word wrap for the karaoke wheel. Each lyric line renders at its
-- normal size (NEVER shrinks -- a line's point size is constant while its
-- neighbors differ, so the face stays steady as you follow). Long lines wrap
-- onto further physical lines up to `maxlines` (2 for neighbours, 3 for the
-- active line); anything beyond the cap is folded onto the tail line and that
-- tail ellipsized. Returns an array of physical lines.
local function wrap_text(cr, str, size, maxw, mono, bold, maxlines)
    maxlines = maxlines or 2
    local UTF8 = '[%z\1-\127\194-\244][\128-\191]*'
    local function measure(sz, txt)
        cairo_select_font_face(cr, mono and FMONO or FSANS,
                               CAIRO_FONT_SLANT_NORMAL,
                               bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, sz * S)
        cairo_text_extents(cr, txt, TEXT_EXT)
        return (TEXT_EXT.width + TEXT_EXT.x_bearing) / S   -- px -> grid units
    end

    if measure(size, str) <= maxw then return { str } end

    local words = {}
    for w in str:gmatch('%S+') do words[#words + 1] = w end

    -- Trim `txt` down until `txt..'…'` fits maxw, then add the ellipsis.
    local function ellipsize(txt)
        local s = txt
        while #s > 1 and measure(size, s .. '…') > maxw do
            s = s:gsub('%s+$', '')
            s = s:gsub(UTF8 .. '$', '')
        end
        return s .. '…'
    end

    local out = {}          -- physical lines
    local cur = ''
    for wi = 1, #words do
        local w = words[wi]
        local t = (cur == '') and w or (cur .. ' ' .. w)
        if measure(size, t) <= maxw then
            cur = t
        elseif cur == '' then
            cur = w                          -- single word wider than maxw
        else
            out[#out + 1] = cur              -- current line is full
            if #out == maxlines then         -- cap reached: this is the last line
                local tail = {}
                for j = wi, #words do tail[#tail + 1] = words[j] end
                out[#out] = ellipsize(cur .. ' ' .. table.concat(tail, ' '))
                return out
            end
            cur = w
        end
    end
    if cur ~= '' then out[#out + 1] = cur end
    return out
end

-- Draw a wrapped line set centred on `cx`, the WHOLE block centred vertically
-- on `y` (so 1/2/3-line blocks all pivot on the same point), each physical
-- line centred on its own baseline, stepping down by `step` grid per line.
-- `alpha` fades the whole block (used by the slide transition).
local function draw_wrapped(cr, cx, y, lines, col, size, mono, bold, step, alpha)
    local function measure(sz, txt)
        cairo_select_font_face(cr, mono and FMONO or FSANS,
                               CAIRO_FONT_SLANT_NORMAL,
                               bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, sz * S)
        cairo_text_extents(cr, txt, TEXT_EXT)
        return (TEXT_EXT.width + TEXT_EXT.x_bearing) / S
    end
    alpha = alpha or 1
    local y0 = y - (#lines - 1) * step / 2
    for i = 1, #lines do
        set_c(cr, col, alpha)
        local w = measure(size, lines[i])
        cairo_move_to(cr, (cx - w/2) * S, (y0 + (i - 1) * step) * S)
        cairo_show_text(cr, lines[i])
    end
end

-- Curved text riding the top arc: every glyph is rotated tangent to the
-- circle at baseline radius `r` (grid), span centred on 12 o'clock.
-- Caps grow OUTWARD from the baseline (TEXT-ON-RING: cap adds 0.73*size
-- to r), so callers pass r = safe - 0.73*size; safe = 116 leaves ~3.4
-- units inside the tick track at 119. Shrinks 0.5/step to minsz, then
-- trims with an ellipsis. UTF-8 safe (accents, '…', '♪' in titles).
local function arc_text_top(cr, cx, cy, str, col, size, r, bold, maxang, minsz)
    if not str or str == '' then return end
    minsz = minsz or 7
    local MAX = maxang or (144 * math.pi / 180)
    local R = r * S
    local UTF8 = '[%z\1-\127\194-\244][\128-\191]*'
    local s = str

    local function select(sz)
        cairo_select_font_face(cr, FSANS, CAIRO_FONT_SLANT_NORMAL,
                               bold and CAIRO_FONT_WEIGHT_BOLD
                                     or CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, sz * S)
    end

    local function span(sz, txt)
        select(sz)
        local total = 0
        for ch in txt:gmatch(UTF8) do
            cairo_text_extents(cr, ch, TEXT_EXT)
            total = total + TEXT_EXT.x_advance / R
        end
        return total
    end

    while size > minsz and span(size, s) > MAX do
        size = size - 0.5
    end
    if span(size, s) > MAX then
        while #s > 1 do
            s = s:gsub('%s+$', '')
            if s:sub(-3) == '…' then        -- drop old ellipsis + one char
                s = s:sub(1, -4)
                s = s:gsub(UTF8 .. '$', '')
            else
                s = s:gsub(UTF8 .. '$', '')
            end
            if s == '' then s = '…' break end
            s = s .. '…'
            if span(size, s) <= MAX then break end
        end
    end

    set_c(cr, col, 1)
    select(size)
    local a = -span(size, s) / 2
    for ch in s:gmatch(UTF8) do
        cairo_text_extents(cr, ch, TEXT_EXT)
        local da  = TEXT_EXT.x_advance / R
        local ink = TEXT_EXT.x_bearing + TEXT_EXT.width / 2
        cairo_save(cr)
        cairo_translate(cr, cx * S, cy * S)
        cairo_rotate(cr, a + da / 2)
        cairo_move_to(cr, -ink, -R)
        cairo_show_text(cr, ch)
        cairo_restore(cr)
        a = a + da
    end
end

-- ======================= ROUND SHELL =========================
-- Family shell, identical to brass-sysmon (scaled from brassviz 500-grid).
local CX, CY    = 140, 140
local PLATE_R   = 132        -- inner edge of the brass rim
local RIM_MID   = 135.5
local RIM_W     = 7
local RIM_OUT   = 139        -- leaves 1 grid unit to the window edge
local TICK_R    = 128
local TICK_MI_FR, TICK_MO_FR = 0.942, 0.990
local TICK_NI_FR, TICK_NO_FR = 0.950, 0.975

-- Lyric arc wheel (same hub as the header arcs, so all text shares one axis).
-- Radii chosen so the ink bands never overlap on the axis (cap = 0.73*size):
--   artist ink  92..99.7     (header, fixed — OUTER of the lyric nest)
--   prev ink    78..84.6     (outer ring - highest up the dial)
--   ACTIVE ink  64..72.8     (the bright ring under it)
--   cont. line  50..58.8     (active continuation ring)
--   next ink    36..42.6     (inner ring - lowest)
-- Each band sits in a recessed CHANNEL: a pair of faint rails at
-- r-1.2 .. r+cap+1.2 so the text is visibly centred between two rings.
-- Budgets are RADIANS of arc at that ring's radius (= glyph advance / R).
local W_R_PREV   = 78     -- framing ring nest radii (decoration only now)
local W_R_ACT    = 64
local W_R_ACT2   = 50
local W_R_NXT    = 36
local SWEEP_R    = 118    -- copper song-progress ring in the clear band
                          -- between the title arc (outer edge ~115.6) and
                          -- the tick track (inner edge ~120.6)
local SWEEP_W    = 2.6

-- Header arc radii. Title + artist are moved TOGETHER as one unit (same 4-unit
-- inward shift) so the 14.5-grid gap between them never changes; pulled in
-- from 106.5 / 92 to open the gap to the tick track / copper sweep.
local HDR_TITLE_R  = 102.5
local HDR_ARTIST_R = 88

local function paint_round_plate(cr)
    local g = cairo_pattern_create_radial(CX*S, CY*S*0.90, 0, CX*S, CY*S, PLATE_R*S)
    cairo_pattern_add_color_stop_rgba(g, 0.00, 9/255, 13/255, 18/255, 0.92)
    cairo_pattern_add_color_stop_rgba(g, 0.55, 9/255, 13/255, 18/255, 0.72)
    cairo_pattern_add_color_stop_rgba(g, 1.00, 2/255,  4/255,  6/255, 0.55)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, PLATE_R*S, 0, 2*math.pi)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)   -- leak discipline: destroy every pattern
    cairo_new_path(cr)
end

local function starfield_round(cr, r)
    starfield(cr, (CX - r)*S, (CY - r)*S, 2*r*S, 2*r*S, r*S)
end

local function rail(cr, cx, cy, rad, c, a, w)
    set_c(cr, c, a)
    cairo_set_line_width(cr, w * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, rad*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

local function dial_track(cr, cx, cy)
    local TIN_R, TOUT_R = 119.0, 127.5
    local CIN_R, COUT_R = 128.0, 131.2

    rail(cr, cx, cy, TIN_R,  BRASS_MID, 0.70, 0.6)
    rail(cr, cx, cy, TOUT_R, BRASS_MID, 0.70, 0.6)

    -- channel as a WIDE STROKE: covers exactly CIN..COUT, no cairo_arc_negative
    set_c(cr, PATINA, 0.42)
    cairo_set_line_width(cr, (COUT_R - CIN_R) * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, ((CIN_R + COUT_R) * 0.5)*S, 0, 2*math.pi)
    cairo_stroke(cr)

    rail(cr, cx, cy, CIN_R + 1.0, BRASS_MID, 0.30, 0.35)
    rail(cr, cx, cy, CIN_R + 2.1, BRASS_MID, 0.22, 0.35)
    rail(cr, cx, cy, COUT_R,      BRASS_BRT, 0.60, 0.6)
end

local function dial_ticks(cr, cx, cy, r)
    for i = 1, 59 do
        local major = (i % 5 == 0)
        local a = (i * 6 - 90) * math.pi / 180
        local rin  = r * (major and TICK_MI_FR or TICK_NI_FR)
        local rout = r * (major and TICK_MO_FR or TICK_NO_FR)
        set_c(cr, major and BRASS_BRT or BRASS_MID, major and 0.8 or 0.75)
        cairo_set_line_width(cr, (major and 1.4 or 0.75) * S)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_new_path(cr)
        cairo_move_to(cr, cx*S + rin*S*math.cos(a), cy*S + rin*S*math.sin(a))
        cairo_line_to(cr, cx*S + rout*S*math.cos(a), cy*S + rout*S*math.sin(a))
        cairo_stroke(cr)
    end
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)   -- CAP-LEAK reset
end

-- Copper song-progress ring: a faint full PATINA track plus a COPPER sweep
-- that advances clockwise from 12 o'clock as the song plays. Lives in the
-- choice band (fixed width wide-stroke, no cairo_arc_negative), and carries a
-- bright tip bead so the endpoint reads at a glance. Fills the dial's outer
-- band together with the field rings (see outer_field).
local function song_sweep(cr, cx, cy, frac)
    local W = SWEEP_W
    set_c(cr, BRASS_MID, 0.55)
    cairo_set_line_width(cr, (W - 1.0) * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, SWEEP_R*S, 0, 2*math.pi)
    cairo_stroke(cr)
    cairo_new_path(cr)
    if frac and frac > 0 then
        set_c(cr, COPPER, 1.0)
        cairo_set_line_width(cr, W * S)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_arc(cr, cx*S, cy*S, SWEEP_R*S, -math.pi/2, -math.pi/2 + 2*math.pi*frac)
        cairo_stroke(cr)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
        cairo_new_path(cr)
        -- tip bead
        local t = -math.pi/2 + 2*math.pi*frac
        set_c(cr, COPPER, 0.95)
        cairo_arc(cr, cx*S + SWEEP_R*S*math.cos(t),
                      cy*S + SWEEP_R*S*math.sin(t), 1.9*S, 0, 2*math.pi)
        cairo_fill(cr)
        cairo_new_path(cr)
    end
end

-- Framing ring nest in the dial core — pure decoration now that the lyric
-- text is straight rows, so every channel is uniformly faint. Each band gets
-- a PAIR of rails, one inside (r-1.2) and one outside (r + 0.73*size + 1.2),
-- so the annulus reads as graduated instrument metal. Full circles: drawn in
-- the shell, UNDER the header arcs and lyric rows.
local function lyric_rings(cr, cx, cy)
    local bands = {
        { W_R_PREV,  9,  PATINA,    0.16, 0.6 },
        { W_R_ACT2,  12, PATINA,    0.16, 0.6 },
        { W_R_NXT,   9,  PATINA,    0.16, 0.6 },
        { W_R_ACT,   12, PATINA,    0.16, 0.6 },
    }
    for _, t in ipairs(bands) do
        local rin  = t[1] - 1.2
        local rout = t[1] + 0.73 * t[2] + 1.2
        set_c(cr, t[3], t[4])
        cairo_set_line_width(cr, t[5] * S)
        for _, rr in ipairs({ rin, rout }) do
            cairo_new_path(cr)
            cairo_arc(cr, cx*S, cy*S, rr*S, 0, 2*math.pi)
            cairo_stroke(cr)
            cairo_new_path(cr)
        end
    end
end

-- Faint machined field rings filling the dial's outer band between the lyric
-- nest (prev channel outer ~86) and the copper sweep (r118). Three whisper
-- rings so the annulus reads as graduated instrument metal instead of empty
-- sky; the header arcs overpaint them at the top.
local function outer_field(cr, cx, cy)
    local rings = {
        { 102, 0.10, 1.2 },
        { 108, 0.15, 0.9 },
        { 114, 0.10, 1.2 },
    }
    for _, t in ipairs(rings) do
        set_c(cr, PATINA, t[2])
        cairo_set_line_width(cr, t[3] * S)
        cairo_new_path(cr)
        cairo_arc(cr, cx*S, cy*S, t[1]*S, 0, 2*math.pi)
        cairo_stroke(cr)
        cairo_new_path(cr)
    end
end

local function dial_bezel(cr, cx, cy, r)
    set_c(cr, BRASS_BRT, 0.95)
    cairo_set_line_width(cr, 1.5 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, r*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

local function brass_rim(cr)
    set_c(cr, BRASS_MID, 0.95)
    cairo_set_line_width(cr, RIM_W * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, RIM_MID*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- patina on the inner half of the band
    set_c(cr, PATINA, 0.55)
    cairo_set_line_width(cr, 2.6 * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, (RIM_MID - 1.6)*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- deterministic mottle (golden angle + sines, never a per-frame PRNG)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    for i = 1, 16 do
        local a0   = (i * 137.508) * math.pi / 180
        local span = (6 + 11 * math.abs(math.sin(i * 2.7))) * math.pi / 180
        local rr   = RIM_MID + math.sin(i * 1.31) * 1.2
        local rub  = (i % 3 == 0)
        local k    = math.abs(math.sin(i * 0.83))
        set_c(cr, rub and BRASS_BRT or PATINA,
                   rub and (0.07 + 0.09 * k) or (0.13 + 0.17 * k))
        cairo_set_line_width(cr, (0.9 + 0.78 * math.abs(math.sin(i * 1.9))) * S)
        cairo_new_path(cr)
        cairo_arc(cr, CX*S, CY*S, rr*S, a0, a0 + span)
        cairo_stroke(cr)
    end
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)

    -- burnished highlight on the outer half of the band
    set_c(cr, BRASS_BRT, 0.50)
    cairo_set_line_width(cr, 1.7 * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, (RIM_MID + 1.3)*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- crisp outer edge
    set_c(cr, BRASS_BRT, 0.85)
    cairo_set_line_width(cr, 0.9 * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, RIM_OUT*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- 12 rivets centred in the band
    for i = 0, 11 do
        local a = (i * 30 - 90) * math.pi / 180
        draw_rivet(cr, CX + RIM_MID*math.cos(a), CY + RIM_MID*math.sin(a))
    end
end

-- ======================= DATA ================================
local function read_file(p)
    local f = io.open(p, 'r')
    if not f then return nil end
    local d = f:read('*a')
    f:close()
    return d
end

-- status: title|artist|album|duration|position|state
local function read_status()
    local d = read_file(STATUS_PATH)
    if not d then return nil end
    local p = {}
    local i = 1
    for field in d:gmatch('([^|\r\n]+)') do
        p[i] = field
        i = i + 1
    end
    if i - 1 < 6 then return nil end
    return { title  = p[1],
             artist = p[2],
             album  = p[3],
             duration = tonumber(p[4]) or 0,
             position = tonumber(p[5]) or 0,
             state  = p[6] }
end

-- meta: key=value lines written by fetch_lyrics.py
local function read_meta()
    local d = read_file(META_PATH)
    if not d then return nil end
    local m = {}
    for line in d:gmatch('[^\r\n]+') do
        local k, v = line:match('^([%w_]+)=(.*)$')
        if k then m[k] = v end
    end
    return m
end

-- LRC: "[mm:ss.xx]text" tags, possibly several per line, unsorted.
local function parse_lrc(txt)
    local out = {}
    for raw in txt:gmatch('[^\r\n]+') do
        local rest = raw
        local times = {}
        while true do
            local sp, ep, hh, mm, ss = rest:find('^%[(%d+):(%d+)%.(%d+)%]')
            if not sp then break end
            table.insert(times, tonumber(hh) * 60 + tonumber(mm) +
                                tonumber(ss) / (10 ^ #ss))
            rest = rest:sub(ep + 1)
        end
        if #times > 0 and rest:find('%S') then
            local text = rest:gsub('^%s+', ''):gsub('%s+$', '')
            for i = 1, #times do
                out[#out + 1] = { times[i], text }
            end
        end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

local function fmt_time(s)
    s = math.max(0, math.floor(s or 0))
    return string.format('%d:%02d', math.floor(s / 60), s % 60)
end

-- parsed-LRC cache: re-parse only when the file content changes
local LRC_TXT, LRC_TBL = nil, {}

-- Stall diagnostics: detect a conky draw-loop pause (whole-widget freeze that
-- later "jumps forward"). The status position is wall-clock derived, so any
-- large gap between a frame's internal clock and the previous frame's means
-- the draw loop itself was blocked (compositor/mainloop hiccup), NOT the data.
-- Logs only when a gap > STALL_GAP occurs while a track is playing -- zero
-- per-frame writes in the normal path.
local STALL_GAP = 3.0
local stall_last_wall = nil
local function mono_now()
    local f = io.open('/proc/uptime', 'r')
    if not f then return os.time() end
    local v = tonumber((f:read('*l') or ''):match('^(%S+)'))
    f:close()
    return v or os.time()
end
-- ---- lyric slide transition state ---------------------------
-- On every lyric advance the outgoing line rises out of view while the
-- incoming line rises from the preview slot into the centre. No permanent
-- PREV row is spent -- the past only exists for the ~0.4s of the slide.
local SLIDE_DUR = 0.40
local LY = { idx = nil, txt = '', from = '', t0 = -1e9 }

local function stall_check(is_playing)
    if not is_playing then stall_last_wall = nil return end
    local now = mono_now()   -- monotonic, sub-second (see CLOCK GOTCHA)
    if stall_last_wall and now - stall_last_wall > STALL_GAP then
        local pos = ''
        local f = io.open(STATUS_PATH, 'r')
        if f then pos = (f:read('*l') or ''):match('|([%d.]+)|') or ''; f:close() end
        local g = io.open('/tmp/opencode/brass-lyrics-stall.log', 'a')
        if g then
            g:write(string.format('%s draw-stall %.1fs (status pos=%s)\n',
                                  os.date('%Y-%m-%d %H:%M:%S'),
                                  now - stall_last_wall, pos))
            g:close()
        end
    end
    stall_last_wall = now
end

-- ======================= MAIN DRAW ============================
function conky_main()
    if conky_window == nil then return end
    local w = conky_window.width
    local h = conky_window.height
    -- GUARD: first hook call can report 0x0, which makes S=0 and turns any
    -- S-derived step into an infinite loop. Do not remove.
    if w < 8 or h < 8 then return end
    S = w / GRID_W

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, w, h)
    local cr = cairo_create(cs)
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

    -- Opaque backing CLIPPED TO THE PLATE DISC: corners stay transparent.
    cairo_set_source_rgba(cr, 2/255, 4/255, 6/255, 1.0)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, PLATE_R*S, 0, 2*math.pi)
    cairo_fill(cr)
    cairo_new_path(cr)

    if STAR_W ~= w or STAR_H ~= h then build_stars(w, h) end

    -- ---- data (one small read each per frame) ----------------
    local st   = read_status()
    stall_check(st and st.state == 'playing')
    local meta = read_meta()
    local lrc  = read_file(LRC_PATH) or ''
    if lrc ~= LRC_TXT then
        LRC_TXT = lrc
        LRC_TBL = parse_lrc(lrc)
    end
    local frac = st and st.duration > 0 and clamp01(st.position / st.duration) or 0

    local mode
    if not st then
        mode = 'offline'
    elseif not meta or meta.title ~= st.title or meta.artist ~= st.artist then
        mode = 'fetching'
    elseif meta.found == '0' or (meta.found == '1' and #LRC_TBL == 0) then
        mode = 'none'
    elseif meta.found ~= '1' then
        mode = 'fetching'   -- found=-1: fetcher still retrying after a net fail
    else
        mode = 'ok'
    end

    -- ---- shell ----------------------------------------------
    paint_round_plate(cr)
    starfield_round(cr, PLATE_R - 1)
    dial_track(cr, CX, CY)
    dial_ticks(cr, CX, CY, TICK_R)
    lyric_rings(cr, CX, CY)
    outer_field(cr, CX, CY)
    song_sweep(cr, CX, CY, frac)
    dial_bezel(cr, CX, CY, PLATE_R)
    brass_rim(cr)

    -- ---- header ---------------------------------------------
    -- Curved title/artist riding the top arc (title inside, artist below).
    -- The engraved separator is gone: the artist arc now occupies its line.
    -- maxang kept tight (112/90 deg) so long titles hug the top instead of
    -- dipping their ends down toward the lyric nest; long ones ellipsize.
    if st then
        arc_text_top(cr, CX, CY, st.title,     CREAM,     12.5, HDR_TITLE_R, true,  112 * math.pi / 180, 9)
        if st.artist ~= '' then
            arc_text_top(cr, CX, CY, st.artist, BRASS_MID, 10.5, HDR_ARTIST_R, false,  90 * math.pi / 180, 8)
        end
    else
        arc_text_top(cr, CX, CY, 'BRASS LYRICS', BRASS_BRT, 12.5, HDR_TITLE_R, true, 112 * math.pi / 180, 9)
    end

    -- ---- body ------------------------------------------------
    if mode == 'offline' then
        text_c(cr, CX, 140, 'PIANOBAR OFFLINE', BRASS_MID, 12, false, true)
        text_c(cr, CX, 157, 'waiting for a track', RUST_DIM, 9.5, false, false)

    elseif mode == 'fetching' then
        text_c(cr, CX, 140, 'FETCHING LYRICS', BRASS_MID, 11.5, false, true)
        fit_c(cr, CX, 157, st.title, RUST_DIM, 9.5, 165, false, false, 7.5)

    elseif mode == 'none' then
        text_c(cr, CX, 136, 'NO LYRICS FOUND', BRASS_MID, 11.5, false, true)
        fit_c(cr, CX, 153, st.title, RUST_DIM, 9.5, 165, false, false, 7.5)

    else -- mode == 'ok': the current lyric lives in the dial's core.
        -- Only the ACTIVE line (wrapped across up to four rows) and a faint
        -- NEXT preview are drawn. On each advance the outgoing line slides UP
        -- out of view while the incoming line rises from the preview slot into
        -- the centre -- so context is kept without spending a permanent row on
        -- the past. The copper sweep at r118 passes BEHIND the text.
        local n   = #LRC_TBL
        local pos = st.position
        local cur = 0
        for i = 1, n do
            if LRC_TBL[i][1] <= pos then cur = i else break end
        end
        if cur < 1 then cur = 1 end          -- before the first tag: show line 1

        local MAXW      = 180          -- widest row, centred; clear of ticks
        local CUR_SIZE  = 13
        local PRE_SIZE  = 10
        local PRE_ALPHA = 0.80         -- preview brightness
        local ROW_STEP  = 16
        local CUR_CY    = 128          -- centre of the active block
        local PRE_CY    = 198          -- centre of the preview block
        local SLIDE_D   = PRE_CY - CUR_CY

        -- advance detection + slide clock (one monotonic read per frame)
        local nowm   = mono_now()
        local curTxt = LRC_TBL[cur][2]
        if LY.idx ~= cur then
            LY.from = LY.txt or ''
            LY.t0   = nowm
            LY.idx  = cur
        end
        LY.txt = curTxt
        local prog = clamp01((nowm - LY.t0) / SLIDE_DUR)

        local nxtTxt = (cur < n) and LRC_TBL[cur + 1][2] or ''

        if prog < 1.0 and LY.from ~= '' then
            -- outgoing line rises out of view and fades
            local ol = wrap_text(cr, LY.from, CUR_SIZE, MAXW, false, true, 4)
            draw_wrapped(cr, CX, CUR_CY - SLIDE_D * prog, ol,
                         CREAM, CUR_SIZE, false, true, ROW_STEP, 1 - prog)
            -- incoming line rises from the preview slot, growing to full size
            local isz = PRE_SIZE + (CUR_SIZE - PRE_SIZE) * prog
            local il  = wrap_text(cr, curTxt, isz, MAXW, false, true, 4)
                draw_wrapped(cr, CX, CUR_CY + SLIDE_D * (1 - prog), il,
                             CREAM, isz, false, true, ROW_STEP, PRE_ALPHA + (1 - PRE_ALPHA) * prog)
            -- preview fades in below
            if nxtTxt ~= '' then
                local nl = wrap_text(cr, nxtTxt, PRE_SIZE, MAXW, false, false, 2)
                draw_wrapped(cr, CX, PRE_CY, nl,
                             BRASS_MID, PRE_SIZE, false, false, ROW_STEP, PRE_ALPHA * prog)
            end
        else
            local cl = wrap_text(cr, curTxt, CUR_SIZE, MAXW, false, true, 4)
            draw_wrapped(cr, CX, CUR_CY, cl, CREAM, CUR_SIZE, false, true, ROW_STEP, 1)
            if nxtTxt ~= '' then
                local nl = wrap_text(cr, nxtTxt, PRE_SIZE, MAXW, false, false, 2)
                draw_wrapped(cr, CX, PRE_CY, nl,
                             BRASS_MID, PRE_SIZE, false, false, ROW_STEP, PRE_ALPHA)
            end
        end
    end

    -- ---- state (pianobar present) -----------------------------
    if st then
        text_c(cr, CX, 226,
               fmt_time(st.position) .. ' / ' .. fmt_time(st.duration),
               BRASS_MID, 10, true, false)

        local playing = (st.state == 'playing')
        text_c(cr, CX, 240, playing and '♪ PLAYING' or 'PAUSED',
               playing and COPPER or BRASS_MID, 10, false, true)
    end

    text_c(cr, CX, 252, 'LRCLIB · MK.I', RUST_DIM, 6.5, false, false)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- ======================= FETCHER SPAWN ========================
-- Run once at load. The path is assembled INSIDE the shell from split
-- variables ("$S/$A$B") so the literal '.../fetch_lyrics.py' never
-- appears contiguously in THIS shell's cmdline -- otherwise the pgrep
-- guard would self-match its own parent and the fetcher would never
-- start (documented clockwidget/spawn_button trick).
local function spawn_fetcher()
    if HOME == '' then return end
    local dir = HOME .. '/.conky/brass-lyrics'
    os.execute(
        "S='" .. dir .. "'; A=fetch_; B=lyrics.py; " ..
        "pgrep -f 'brass-lyrics/fetch_ly[r]ics' >/dev/null 2>&1 || " ..
        "setsid python3 \"$S/$A$B\" </dev/null >>\"$S/fetch.log\" 2>&1 &")
end
spawn_fetcher()
