-- ############################################################
--  brass-sysmon -- Steampunk brass system monitor
--  Four speedometer dials (CPU / MEM / NET / TEMP) plus a
--  LOAD / UPTIME / NET-split strip inside the shared brass
--  round-plate shell (orrery-brass / brassviz family).
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

-- ONE module-level text-extents object, shared by every measurement on this
-- file. Per-call cairo_text_extents_t:create() is leak class #1 in this
-- codebase -- never allocate one per text call.
local TEXT_EXT = cairo_text_extents_t:create()

-- ======================= HELPERS =============================
local function set_c(cr, c, a)
    cairo_set_source_rgba(cr, c[1]/255, c[2]/255, c[3]/255, a or 1)
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
-- Same measured star field as brassviz / orrery-brass (cores p50 luma 94,
-- ~1 star per 224 px^2). Seeded ONCE and cached, so it is identical every
-- frame -- a PRNG reseeded per frame would strobe.
local STAR_TINT  = { 0xc6, 0xd6, 0xeb }
local STAR_AREA  = 224
local STAR_ALPHA = { faint = 0.050, dim = 0.105, mid = 0.240, bright = 0.330 }
local STAR_RAD   = { faint = 1.2,  dim = 1.5,  mid = 1.9,  bright = 2.4 }
local STAR_DR    = { faint = 0.7,  dim = 0.7,  mid = 0.7,  bright = 1.0 }
local STAR_CUT   = { 0.42, 0.84, 0.92, 1.01 }
local STAR_BAND  = { 'faint', 'dim', 'mid', 'bright' }

local STAR_TBL, STAR_W, STAR_H = nil, 0, 0

-- Numerical-Recipes LCG: exact in a double, no bitwise ops (llua has none).
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

local function text_right(cr, right, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    set_c(cr, col, 1)
    cairo_select_font_face(cr, mono and FMONO or FSANS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    cairo_text_extents(cr, str, TEXT_EXT)
    cairo_move_to(cr, right * S - (TEXT_EXT.width + TEXT_EXT.x_bearing), y * S)
    cairo_show_text(cr, str)
end

-- Curved text riding the top arc: every glyph is rotated tangent to the
-- circle at baseline radius `r` (grid), span centred on 12 o'clock.
-- Caps grow OUTWARD from the baseline (TEXT-ON-RING: cap adds 0.73*size
-- to r), so callers pass r = safe - 0.73*size; safe = 116 leaves ~3.4
-- units inside the tick track at 119. Shrinks 0.5/step to minsz, then
-- trims with an ellipsis. UTF-8 safe (accents, '…').
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
-- Family shell, scaled 0.56 from the brassviz 500-grid.
-- The rc asks for 332; the dock adds ~8px, so the window lands at 340.
local CX, CY    = 140, 140
local PLATE_R   = 132        -- inner edge of the brass rim
local RIM_MID   = 135.5
local RIM_W     = 7
local RIM_OUT   = 139        -- leaves 1 grid unit to the window edge
local TICK_R    = 128        -- ticks span 128*0.942..128*0.990 = 120.6..126.7
local TICK_MI_FR, TICK_MO_FR = 0.942, 0.990
local TICK_NI_FR, TICK_NO_FR = 0.950, 0.975

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

-- hairline rail / groove helper (defined above its callers -- nil-global trap)
local function rail(cr, cx, cy, rad, c, a, w)
    set_c(cr, c, a)
    cairo_set_line_width(cr, w * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, rad*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

-- Graduation track: rails bracket the tick band, a recessed machined channel
-- ties the track to the bezel so the outer assembly reads as ONE piece.
local function dial_track(cr, cx, cy)
    local TIN_R, TOUT_R = 119.0, 127.5   -- ticks span 119.9..127.4 with caps
    local CIN_R, COUT_R = 128.0, 131.2   -- channel to the bezel (131.25)

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

local function dial_bezel(cr, cx, cy, r)
    set_c(cr, BRASS_BRT, 0.95)
    cairo_set_line_width(cr, 1.5 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, r*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

local function brass_rim(cr)
    -- band as a WIDE STROKE centred on RIM_MID (covers PLATE_R..RIM_OUT)
    set_c(cr, BRASS_MID, 0.95)
    cairo_set_line_width(cr, RIM_W * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, RIM_MID*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- patina on the inner half of the band (dark bronze, not verdigris)
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

-- ======================= SPEEDOMETER DIALS ===================
-- Sweep 135deg -> 405deg: a 270 deg speedometer with the gap at the bottom.
local GA0    = 135 * math.pi / 180
local GA1    = 405 * math.pi / 180
local GSWEEP = GA1 - GA0

-- Speedometer scale, ~10% smaller than the first pass: the dials used to
-- leave only 3 units between their rim and the strip, which read as
-- crowded. The separate outer hairline ring is GONE -- bezel band is now
-- the dial's outer boundary (one less concentric ring per dial).
local GR       = 23      -- track / value arc centreline
local GW_W     = 5       -- arc stroke width
local WELL_R   = 20
local TIN_MAJ, TOUT_MAJ = 26.0, 28.8
local TIN_MIN, TOUT_MIN = 27.0, 28.6
local BEZ_BAND_R = 31    -- band spans 29.5..32.5; dial outer reach = seat + 32.5

local function gauge_well(cr, cx, cy)
    local g = cairo_pattern_create_radial(cx*S, (cy - 7)*S, 1, cx*S, cy*S, WELL_R*S)
    cairo_pattern_add_color_stop_rgba(g, 0.00, 0x14/255, 0x18/255, 0x1f/255, 0.97)
    cairo_pattern_add_color_stop_rgba(g, 0.70, 0x0c/255, 0x0f/255, 0x14/255, 0.97)
    cairo_pattern_add_color_stop_rgba(g, 1.00, 0x05/255, 0x06/255, 0x09/255, 0.97)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, WELL_R*S, 0, 2*math.pi)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)   -- leak discipline: 1 create : 1 destroy
    cairo_new_path(cr)
end

local function gauge(cr, cx, cy, frac, val, lab)
    if not frac or frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end

    gauge_well(cr, cx, cy)

    -- track (full sweep, dim body brass)
    set_c(cr, BRASS_MID, 0.32)
    cairo_set_line_width(cr, GW_W * S)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, GR*S, GA0, GA1)
    cairo_stroke(cr)

    -- graduations: minor every 5%, major every 25%
    for i = 0, 20 do
        local major = (i % 5 == 0)
        local a  = GA0 + GSWEEP * (i / 20)
        local ri = major and TIN_MAJ or TIN_MIN
        local ro = major and TOUT_MAJ or TOUT_MIN
        set_c(cr, major and BRASS_MID or RUST_DIM, major and 0.85 or 0.7)
        cairo_set_line_width(cr, (major and 1.4 or 0.8) * S)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_new_path(cr)
        cairo_move_to(cr, cx*S + ri*S*math.cos(a), cy*S + ri*S*math.sin(a))
        cairo_line_to(cr, cx*S + ro*S*math.cos(a), cy*S + ro*S*math.sin(a))
        cairo_stroke(cr)
    end
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)   -- CAP-LEAK reset

    -- value arc (skip a hairline when idle)
    if frac > 0.004 then
        set_c(cr, COPPER, 0.95)
        cairo_set_line_width(cr, GW_W * S)
        cairo_new_path(cr)
        cairo_arc(cr, cx*S, cy*S, GR*S, GA0, GA0 + GSWEEP * frac)
        cairo_stroke(cr)
    end

    -- bezel band (dial's outer boundary)
    set_c(cr, BRASS_MID, 0.95)
    cairo_set_line_width(cr, 3.0 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, BEZ_BAND_R*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- readout: value over label ('100 deg C' at 11pt is ~33 units wide --
    -- inside the well's 20-unit half-width, clear of the arc inner 20.5)
    text_c(cr, cx, cy - 1, val, CREAM, 11, true, true)
    text_c(cr, cx, cy + 10, lab, BRASS_MID, 7.5, true, true)
end

-- ======================= LOAD / UPTIME / NET STRIP ===========
local STRIP_X, STRIP_Y, STRIP_W, STRIP_H, STRIP_R = 32, 130, 216, 20, 4

local function strip_plate(cr)
    local g = cairo_pattern_create_linear(STRIP_X*S, STRIP_Y*S,
                                          STRIP_X*S, (STRIP_Y + STRIP_H)*S)
    cairo_pattern_add_color_stop_rgba(g, 0.00, 0x26/255, 0x1e/255, 0x10/255, 0.97)
    cairo_pattern_add_color_stop_rgba(g, 1.00, 0x0d/255, 0x09/255, 0x04/255, 0.97)
    rrect(cr, STRIP_X*S, STRIP_Y*S, STRIP_W*S, STRIP_H*S, STRIP_R*S)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)   -- leak discipline: 1 create : 1 destroy
    cairo_new_path(cr)

    rrect(cr, STRIP_X*S, STRIP_Y*S, STRIP_W*S, STRIP_H*S, STRIP_R*S)
    set_c(cr, BRASS_MID, 0.9)
    cairo_set_line_width(cr, 1.3 * S)
    cairo_stroke(cr)
    cairo_new_path(cr)
end

-- ======================= DATA READERS ========================
-- All readers are nil-safe: a missing /proc file renders the last known
-- value (or a neutral one), never a crash mid-draw. Every io.open is
-- closed inside the same call -- no fd is held across frames.
local E = { cpu = nil, mem = nil, down = nil, up = nil, temp = nil }

local function ema(key, v, a)
    local prev = E[key]
    if v == nil then return prev end
    if prev == nil then E[key] = v else E[key] = prev + a * (v - prev) end
    return E[key]
end

local function clamp01(v)
    if not v then return 0 end
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

-- /proc/uptime is TWO numbers on one line: tonumber() on the whole line is
-- nil (documented trap) -- pull the first field first.
local function up_t()
    local f = io.open('/proc/uptime', 'r')
    if not f then return os.time() end
    local s = f:read('*l')
    f:close()
    return tonumber(s and s:match('^(%S+)')) or 0
end

local p_cpu, p_didle = nil, nil

local function read_cpu()
    local f = io.open('/proc/stat', 'r')
    if not f then return E.cpu or 0 end
    local l = f:read('*l')
    f:close()
    if not l then return E.cpu or 0 end
    local vals = {}
    for n in l:gmatch('%d+') do vals[#vals + 1] = tonumber(n) end
    local tot = 0
    for i = 1, #vals do tot = tot + vals[i] end
    local didle = (vals[4] or 0) + (vals[5] or 0)   -- idle + iowait
    if tot > 0 and p_cpu then
        local dt, di = tot - p_cpu, didle - p_didle
        p_cpu, p_didle = tot, didle
        if dt > 0 then
            return ema('cpu', clamp01(1 - di / dt), 0.40)
        end
    else
        p_cpu, p_didle = tot, didle
    end
    return E.cpu or 0
end

local function read_mem()
    local f = io.open('/proc/meminfo', 'r')
    if not f then return E.mem or 0 end
    local tot, av, mf, bf, ch
    for l in f:lines() do
        local v = l:match('^MemTotal:%s+(%d+)')    if v then tot = tonumber(v) end
        local v = l:match('^MemAvailable:%s+(%d+)') if v then av  = tonumber(v) end
        local v = l:match('^MemFree:%s+(%d+)')      if v then mf  = tonumber(v) end
        local v = l:match('^Buffers:%s+(%d+)')      if v then bf  = tonumber(v) end
        local v = l:match('^Cached:%s+(%d+)')       if v then ch  = tonumber(v) end
        if tot and av then break end
    end
    f:close()
    if not tot or tot <= 0 then return E.mem or 0 end
    if not av then av = (mf or 0) + (bf or 0) + (ch or 0) end
    if av > tot then av = tot end
    return ema('mem', clamp01(1 - av / tot), 0.50)
end

local p_up, p_rx, p_tx = nil, nil, nil

local function read_net()
    local f = io.open('/proc/net/dev', 'r')
    if not f then return E.down or 0, E.up or 0 end
    local rx, tx, n = 0, 0, 0
    for l in f:lines() do
        n = n + 1
        if n > 2 then
            local name, rest = l:match('^%s*([^:]+):%s*(.+)$')
            if name and name ~= 'lo' then
                local r, t = rest:match(
                    '^(%d+)%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)')
                if r then
                    rx = rx + tonumber(r)
                    tx = tx + tonumber(t)
                end
            end
        end
    end
    f:close()
    local now = up_t()
    if p_up then
        local dt = now - p_up
        local drx, dtx = rx - p_rx, tx - p_tx
        p_rx, p_tx, p_up = rx, tx, now
        -- dt floor from /proc/uptime's 10 ms print resolution; ceiling so a
        -- suspend/stall can't turn one stale sample into a huge fake rate.
        if dt >= 0.01 and dt <= 10 and drx >= 0 and dtx >= 0 then
            ema('down', drx / dt, 0.45)
            ema('up',   dtx / dt, 0.45)
        end
    else
        p_rx, p_tx, p_up = rx, tx, now
    end
    return E.down or 0, E.up or 0
end

local function read_temp()
    local best = nil
    for z = 0, 9 do
        local f = io.open(string.format(
            '/sys/class/thermal/thermal_zone%d/temp', z), 'r')
        if f then
            local s = f:read('*l')
            f:close()
            local v = tonumber(s)
            if v then
                if v > 1000 then v = v / 1000 end       -- mC -> C
                if v >= 1 and v <= 115 and (not best or v > best) then
                    best = v
                end
            end
        end
    end
    if not best then return E.temp end
    return ema('temp', best, 0.30)
end

local function read_load()
    local f = io.open('/proc/loadavg', 'r')
    if not f then return nil end
    local s = f:read('*l')
    f:close()
    return tonumber(s and s:match('^(%S+)'))
end

-- 1000-based rate formatting, max 4 glyphs so the dial readout can never
-- outgrow the well (999K / 9.9M / 999M / 9.9G).
local function fmt_rate(b)
    if b >= 1e9 then
        local v = b / 1e9
        return string.format(v < 10 and '%.1fG' or '%.0fG', v)
    elseif b >= 1e6 then
        local v = b / 1e6
        return string.format(v < 10 and '%.1fM' or '%.0fM', v)
    elseif b >= 1e3 then
        return string.format('%.0fK', b / 1e3)
    end
    -- b is always a float (bytes/sec from a delta ratio): Lua 5.3+ rejects
    -- '%d' with a non-integer, so round first.
    return string.format('%dB', math.floor(b + 0.5))
end

local function fmt_up(s)
    local d = math.floor(s / 86400)
    local h = math.floor((s % 86400) / 3600)
    local m = math.floor((s % 3600) / 60)
    if d > 0 then return string.format('%dd%02dh', d, h) end
    if h > 0 then return string.format('%dh%02dm', h, m) end
    return string.format('%dm', m)
end

-- log-scale: 1 KB -> 0, 100 MB -> 1 (5 decades from 1e3 to 1e8)
local function net_frac(b)
    if not b or b < 1024 then return 0 end
    return clamp01((math.log(b) / math.log(10) - 3) / 5)
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

    -- Opaque backing CLIPPED TO THE PLATE DISC, so the four window corners
    -- stay per-pixel transparent and the wallpaper shows through there.
    cairo_set_source_rgba(cr, 2/255, 4/255, 6/255, 1.0)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, PLATE_R*S, 0, 2*math.pi)
    cairo_fill(cr)
    cairo_new_path(cr)

    if STAR_W ~= w or STAR_H ~= h then build_stars(w, h) end

    -- one read per subsystem per frame (update_interval 0.5)
    local cpu       = read_cpu()
    local mem       = read_mem()
    local dn, upl  = read_net()
    local temp      = read_temp()
    local load      = read_load()
    local upt       = up_t()
    local total     = dn + upl

    paint_round_plate(cr)
    starfield_round(cr, PLATE_R - 1)
    dial_track(cr, CX, CY)
    dial_ticks(cr, CX, CY, TICK_R)
    dial_bezel(cr, CX, CY, PLATE_R)
    brass_rim(cr)

    -- four speedometer seats: top-left CPU, top-right MEM,
    -- bottom-left NET, bottom-right TEMP (each dial reaches only 106.7
    -- units from the plate centre, clear of the rail at 119)
    gauge(cr,  90,  90, cpu,
          string.format('%d%%', math.floor(cpu * 100 + 0.5)), 'CPU')
    gauge(cr, 190,  90, mem,
          string.format('%d%%', math.floor(mem * 100 + 0.5)), 'MEM')
    gauge(cr,  90, 190, net_frac(total), fmt_rate(total), 'NET')
    gauge(cr, 190, 190, temp and clamp01(temp / 100) or 0,
          temp and string.format('%d°C', math.floor(temp + 0.5)) or '--', 'TEMP')

    strip_plate(cr)
    -- baselines centred in the 20-unit strip (9pt cap ~6.6 -> 143.5)
    text_at(cr, STRIP_X + 10, STRIP_Y + 13.5,
            string.format('LOAD %.2f', load or 0), BRASS_BRT, 9, true, true)
    text_right(cr, STRIP_X + STRIP_W - 10, STRIP_Y + 13.5,
               'UP ' .. fmt_up(upt), BRASS_BRT, 9, true, true)
    text_c(cr, STRIP_X + STRIP_W / 2, STRIP_Y + 13,
           string.format('NET %s↓ %s↑', fmt_rate(dn), fmt_rate(upl)),
           BRASS_MID, 8.5, true, false)

    -- title: curved on the top arc (parity with brass-lyrics header),
    -- 12.5 bold at r106.5 -- cap tip ~115.6, clear of the tick rail
    -- (120.6) and of the dial bands (reach ~106.7 at ±45°; the ±29°
    -- span keeps every glyph >3 units off them).
    arc_text_top(cr, CX, CY, 'SYSTEM MONITOR', BRASS_BRT, 12.5, 106.5, true, 144 * math.pi / 180, 9)
    text_c(cr, CX, 250, 'MK.I', RUST_DIM, 7.5, false, false)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
