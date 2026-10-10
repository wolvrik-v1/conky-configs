-- ############################################################
--  brassviz -- Cairo/Lua Steampunk Sound Visualizer
--  Companion to brasspianobar: same 500x500 brass shell, but the
--  interior belongs to the 12 CAVA rings. No plaques, no marquee,
--  no cover art -- the purpose of this widget is the visualizer.
-- ############################################################

require 'cairo'

-- ======================= PATHS ===============================
local HOME        = os.getenv('HOME') or os.getenv('USERPROFILE') or ''
-- brassviz's OWN feed (0..64). NOT /tmp/cava_vals.txt -- that one is
-- the shared conf's 0..8 range and 9 steps froze 10 of 12 bands.
local VALS_PATH   = '/tmp/brassviz_vals.txt'

-- ======================= DESIGN GRID =========================
local GRID_W = 500
local GRID_H = 500

local BEZ    = 10
local MOD_MX = BEZ + 10
local MOD_W  = GRID_W - 2 * MOD_MX
local MOD_CR = 4

-- Header strip
local HDR_Y, HDR_H = 14, 60

-- Left module: cog dial
local DIAL_X, DIAL_Y, DIAL_W, DIAL_H = 20, 84, 300, 240
local DIAL_CX, DIAL_CY = 168, 204
local DIAL_R          = 92
local ART_R           = 55

-- Ticks confined strictly to the outer perimeter rim
local TICK_MI_FR, TICK_MO_FR = 0.942, 0.990
local TICK_NI_FR, TICK_NO_FR = 0.950, 0.975

-- Right module: metadata
local META_X, META_Y, META_W, META_H = 330, 84, 290, 240
local CNT_LX    = MOD_MX + 14
local CNT_RX    = MOD_MX + MOD_W - 12
local MTX       = META_X + 16
local META_CW   = CNT_RX - MTX


-- ======================= PALETTE (Patinated Antique Brass) ===
local CREAM     = { 0xf2, 0xe8, 0xd4 }  -- Slightly softer, aged parchment cream
-- PALETTE SAMPLED FROM THE WALLPAPER (user: "sample the wallpaper, not the green,
-- the other cogs -- that is the colour I am looking for").
-- Measured off the user's wallpaper, restricted to the ring of bright
-- warm metal that surrounds the portal hole (located by a density map, NOT by
-- eye -- see the session note that automated wallpaper reads have lied before):
--   lit metal  #b6915c (183,145,93)  luma 149.5  hue 34.7deg  sat 0.49
--   body metal #755a38 (118, 90,57)  luma  93.7  hue 32.5deg  sat 0.52
--   shadow     #3e2e19 ( 62,46,26)  luma  48.2
-- The FIRST palette sat at hue 40.7deg / sat 0.58, i.e. gold -- that ~8deg gap is
-- the entire "too yellow" complaint, and no amount of alpha tuning would have
-- fixed it. Everything below is pinned to hue 33deg at the wallpaper's own
-- chroma, while luma is deliberately held at the values the user had ALREADY
-- approved for rim weight: the hue rotates, the silhouette must not.
local BRASS_BRT = { 0xdb, 0xb2, 0x7f }  -- lit metal,  luma 183  hue 33.3  sat 0.42
local BRASS_MID = { 0x9f, 0x7f, 0x58 }  -- body metal, luma 131  hue 32.9  sat 0.45
local COPPER    = { 0xcc, 0x95, 0x52 }  -- hot progress arc, luma 156, same hue family
local PATINA    = { 0x4c, 0x38, 0x22 }  -- dark bronze oxide, wallpaper shadow family
local DARK_IRON = { 0x12, 0x16, 0x1c }  -- Celestial midnight charcoal
local PLATE_BG  = { 0x0a, 0x0d, 0x14 }  -- Module backing fill
local RUST_DIM  = { 0x6b, 0x55, 0x3b }  -- minor graduations, luma 88

local FSANS = 'DejaVu Sans'
local FMONO = 'DejaVu Sans Mono'
local S = 1

-- ONE module-level text-extents object, shared by every measurement on this
-- file. Per-call cairo_text_extents_t:create() is documented leak class #1 in
-- this codebase: lua-cario does not tie that userdata's lifetime to the Lua GC,
-- so every allocation is a permanent leak. Never allocate one per text call.
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
    cairo_arc(cr, x*S, y*S, 2.2*S, 0, 2*math.pi)
    cairo_fill(cr)
    set_c(cr, DARK_IRON, 0.9)
    cairo_set_line_width(cr, 0.7*S)
    cairo_new_path(cr)
    cairo_arc(cr, x*S, y*S, 2.2*S, 0, 2*math.pi)
    cairo_stroke(cr)
end


-- ======================= STARFIELD ==========================
-- Sampled from ORRERY1.jpg (the live left-monitor wallpaper) as it actually
-- appears UNDERNEATH the running brass-orrery, which is what set the target.
-- MEASURE THE STAR CORES, NOT THE BLOB MEAN -- this is the whole ballgame.
-- A blob mean is dominated by the antialiased falloff and reads ~2.3x ground,
-- which reproduces as a perfectly correct and completely INVISIBLE field.
-- Cores (5x5 local maxima) in the portal interior:
--   core luma   p10=49  p50=94  p90=214  p99=251
--   core colour mean (110,116,125), B-R = +15   -> bluish-white
--   blob size   p50 11 px^2 (~1.9 px across), p90 29 px^2 (~3.0 px)
--   density     ~1 star per 224 px^2
-- Push those cores through the orrery plate (alpha 0.48..0.92 over a ground of
-- ~16) and the eye sees: dim 25 (1.6x) | typical 36 (2.2x) | bright 69 (4.3x)
-- | peak 80 (5.0x). The bands below are solved backwards from those four numbers,
-- so the bright tail is ~7x denser than a naive mean-based fit would give.
-- Seeded ONCE and cached, so it is identical every frame (a PRNG reseeded per
-- frame would strobe on a 1 s update).
local STAR_TINT  = { 0xc6, 0xd6, 0xeb }   -- bluish-white
local STAR_AREA  = 224                    -- px^2 per star (measured)
local STAR_ALPHA = { faint = 0.050, dim = 0.105, mid = 0.240, bright = 0.330 }
local STAR_RAD   = { faint = 1.2,  dim = 1.5,  mid = 1.9,  bright = 2.4 }
local STAR_DR    = { faint = 0.7,  dim = 0.7,  mid = 0.7,  bright = 1.0 }
-- cumulative roll cutoffs, matched to the core luma percentiles above
local STAR_CUT   = { 0.42, 0.84, 0.92, 1.01 }
local STAR_BAND  = { 'faint', 'dim', 'mid', 'bright' }

local STAR_TBL, STAR_W, STAR_H = nil, 0, 0

-- Numerical-Recipes LCG. seed stays under 2^32 and seed*1664525 stays under
-- 2^53, so this is exact in a double -- no bitwise ops needed (llua has none).
local function make_rng(seed)
  return function()
    seed = (seed * 1664525 + 1013904223) % 4294967296
    return seed / 4294967296
  end
end

-- deterministic star list, rebuilt only when the window size changes
local function build_stars(w, h)
  local rng = make_rng(0x5EEDB2)
  local n = math.floor((w * h) / STAR_AREA)
  local t = {}
  for i = 1, n do
    -- roll the magnitude band, then the size within it
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

-- Draw the cached stars clipped to a rounded rect (screen px).
-- x/y/w/h are the MODULE rect. The star table is normalised against the WINDOW
-- (STAR_W/STAR_H), so it must be positioned with those -- two earlier bugs came
-- from using the module's w/h here: the size guard (STAR_W ~= w) was then true
-- for every panel, so this function returned early and drew NOTHING, and the
-- fallback (s[1] * w) would have crammed each panel's stars into its corner.
local function starfield(cr, x, y, w, h, r)
  if not STAR_TBL or #STAR_TBL == 0 then return end
  cairo_save(cr)
  rrect(cr, x, y, w, h, r)
  cairo_clip(cr)
  local x1, y1 = x + w, y + h
  for i = 1, #STAR_TBL do
    local s = STAR_TBL[i]
    local sx, sy = s[1] * STAR_W, s[2] * STAR_H
    -- cheap bbox reject before touching cairo
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

-- text_at puts x at the LEFT edge of the glyphs, so anything meant to be
-- centred on cx sat off by half its width. text_c measures with the single
-- module-level TEXT_EXT (never a per-call extents -- that is leak class #1).
local function text_c(cr, cx, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    set_c(cr, col, 1)
    cairo_select_font_face(cr, mono and FMONO or FSANS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    cairo_text_extents(cr, str, TEXT_EXT)
    local w = TEXT_EXT.width + TEXT_EXT.x_bearing
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
    cairo_move_to(cr, (right - (TEXT_EXT.width + TEXT_EXT.x_bearing)) * S, y * S)
    cairo_show_text(cr, str)
end

local function draw_dot(cr, cx, cy, radius, color)
    set_c(cr, color)
    cairo_new_path(cr)
    cairo_arc(cr, cx * S, cy * S, radius * S, 0, 2 * math.pi)
    cairo_fill(cr)
end

local function fit_text(cr, text, max_w, family, size, bold)
    text = tostring(text or '')
    if text == '' or max_w <= 0 then return '' end
    cairo_select_font_face(cr, family,
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    cairo_text_extents(cr, text, TEXT_EXT)
    if TEXT_EXT.width <= max_w * S then return text end
    local chars = {}
    for _, c in utf8.codes(text) do chars[#chars+1] = utf8.char(c) end
    local lo, hi = 0, #chars
    while lo < hi do
        local mid = math.floor((lo + hi + 1)/2)
        local cand = table.concat(chars, '', 1, mid) .. '…'
        cairo_text_extents(cr, cand, TEXT_EXT)
        if TEXT_EXT.width <= max_w * S then lo = mid else hi = mid - 1 end
    end
    local res = table.concat(chars, '', 1, lo)
    if lo < #chars then res = res .. '…' end
    return res
end


local function dial_ticks(cr, cx, cy, r)
    for i = 0, 59 do
        if i ~= 0 then
            local major = (i % 5 == 0)
            local a = (i * 6 - 90) * math.pi / 180
            local rin  = r * (major and TICK_MI_FR or TICK_NI_FR)
            local rout = r * (major and TICK_MO_FR or TICK_NO_FR)
            -- Minor graduations were RUST_DIM @0.50, which composites to luma
            -- ~44 against the plate -- effectively invisible. BRASS_MID @0.75
            -- composites to ~98: clearly legible while staying well under the
            -- majors' ~146, so the 5-minute hierarchy survives.
            set_c(cr, major and BRASS_BRT or BRASS_MID, major and 0.8 or 0.75)
            cairo_set_line_width(cr, (major and 2.0 or 1.1) * S)
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
            cairo_new_path(cr)
            cairo_move_to(cr, cx*S + rin*S*math.cos(a), cy*S + rin*S*math.sin(a))
            cairo_line_to(cr, cx*S + rout*S*math.cos(a), cy*S + rout*S*math.sin(a))
            cairo_stroke(cr)
        end
    end
end




-- Graduation track. The ticks used to sit on bare plate with 10 units of dead
-- space before the bezel, which read as "floating out there". This is the
-- brass-orrery recipe in miniature: hairline rails top and tail the tick band
-- (orrery does exactly this at r319/r336, which is what gives it the railroad-
-- track look), then a recessed machined channel ties the track to the bezel so
-- the outer assembly reads as ONE piece rather than a ring and a rim with
-- nothing connecting them.
--
-- Defined ABOVE conky_main on purpose: a `local function` is only in scope from
-- its declaration down, and calling a helper defined below its caller is the
-- nil-global trap that has already cost this repo two launches.
local function dial_track(cr, cx, cy)
    -- rails bracket the tick band: majors span 214.8..225.7 and, with their
    -- 2.0 round cap, reach 213.8..226.7 -- both essentially touching the rails.
    local TIN_R, TOUT_R = 213.0, 227.5
    -- channel fills the gap from the outer rail to the bezel (236, inner edge 234.9)
    local CIN_R, COUT_R = 228.5, 234.0

    local function rail(rad, c, a, w)
        set_c(cr, c, a)
        cairo_set_line_width(cr, w * S)
        cairo_new_path(cr)
        cairo_arc(cr, cx*S, cy*S, rad*S, 0, 2*math.pi)
        cairo_stroke(cr)
    end

    rail(TIN_R, BRASS_MID, 0.70, 1.0)
    rail(TOUT_R, BRASS_MID, 0.70, 1.0)

    -- channel as a WIDE STROKE: covers exactly CIN..COUT and needs no
    -- cairo_arc_negative, whose presence in this binding is unverified.
    -- Same construction brass_rim already uses for its band.
    set_c(cr, PATINA, 0.42)
    cairo_set_line_width(cr, (COUT_R - CIN_R) * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, ((CIN_R + COUT_R) * 0.5)*S, 0, 2*math.pi)
    cairo_stroke(cr)

    rail(CIN_R + 1.8, BRASS_MID, 0.30, 0.6)
    rail(CIN_R + 3.7, BRASS_MID, 0.22, 0.6)
    rail(COUT_R, BRASS_BRT, 0.60, 1.0)
end

local function dial_bezel(cr, cx, cy, r)
    set_c(cr, BRASS_BRT, 0.95)
    cairo_set_line_width(cr, 2.2 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, r*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

-- Rotating marquee on a free ring: the run tiles itself around the full circle
-- and the whole tiling turns, so the text runs the dial continuously.
--
-- Why tiled rather than one run sliding past a clip: on a circle an angle and
-- that angle plus 2*pi are the SAME point, so the usual "draw it twice, one lap
-- apart, so it wraps seamlessly" trick draws the same pixels twice. Evenly
-- spacing real copies is what actually gives a seamless lap. When the run is
-- short enough that n==1, the single copy still turns a full circle and returns
-- exactly to its start, so there is no wrap jump either.
--
-- Phase comes from the monotonic clock: frames are unevenly spaced and a
-- per-frame accumulator drifts with them.

-- ======================= ROUND INSTRUMENT ======================
-- Circular redesign. The design grid is 500x500 so the instrument exactly fills
-- the window. NOTE the rc asks for 531, not 500: conky's dock window comes out
-- at 0.9416 of the requested size, and 531 * 0.9416 = 500.0 exactly. Measured,
-- not guessed -- do not "simplify" the rc back to 500 or the circle shrinks.
local CX, CY    = 250, 250
local PLATE_R   = 236        -- inner edge of the brass rim
local RIM_MID   = 242.5
local RIM_W     = 11
local RIM_OUT   = 248
local TICK_R    = 228        -- ticks span 228*0.942..228*0.990 = 214.8..225.7, which
                            -- clears the progress track (ends 213). At 218 they
                            -- spanned 205..216 and were ~88% buried inside it.

local function disc_path(cr, cx, cy, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
end

local function paint_round_plate(cr)
    local g = cairo_pattern_create_radial(CX*S, CY*S*0.90, 0, CX*S, CY*S, PLATE_R*S)
    -- GROUND RECOLOURED TO THE ORRERY'S DEEP-SPACE FAMILY. The wallpaper-sampled
    -- stops were blue-dominant -- centre (44,52,68) has B-R = +22 and composited
    -- to luma ~48 over the backing -- which is why these two read "bluer than the
    -- brass-orrery". ORRERY1/SPACE1 is (9,13,18) with B-R = +9 and the orrery
    -- plate reads luma ~11 at centre. Same 3-stop dome geometry and the same
    -- top-biased light source; only the ink changed.
    cairo_pattern_add_color_stop_rgba(g, 0.00, 9/255, 13/255, 18/255, 0.92)
    cairo_pattern_add_color_stop_rgba(g, 0.55, 9/255, 13/255, 18/255, 0.72)
    cairo_pattern_add_color_stop_rgba(g, 1.00, 2/255,  4/255,  6/255, 0.55)
    disc_path(cr, CX*S, CY*S, PLATE_R*S)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)   -- leak discipline: destroy every pattern
end

local function starfield_round(cr, r)
    -- starfield() clips to a rounded rect, and rrect with r = w/2 = h/2 IS a
    -- circle, so handing it R as the corner radius buys a round clip for free.
    -- x/y/w/h/r are all SCREEN PX here, unlike most helpers on this file.
    starfield(cr, (CX - r)*S, (CY - r)*S, 2*r*S, 2*r*S, r*S)
end

local function brass_rim(cr)
    -- The band is a WIDE STROKE centred on RIM_MID rather than an even-odd
    -- annulus: it covers exactly PLATE_R..RIM_OUT and avoids cairo_arc_negative,
    -- whose existence in this binding is unverified.
    set_c(cr, BRASS_MID, 0.95)
    cairo_set_line_width(cr, RIM_W * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, RIM_MID*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- Patina settles on the INNER half of the band: the exposed outer face stays
    -- burnished while the recessed inner face darkens with oxide. Deliberately
    -- NOT green -- the wallpaper's cogs age to dark bronze, not verdigris, and
    -- the user asked for the cogs' colour specifically.
    set_c(cr, PATINA, 0.55)
    cairo_set_line_width(cr, 4.6 * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, (RIM_MID - 2.9)*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- Deterministic patina mottle, so the band reads as aged rather than
    -- repainted. Positions come from the golden angle plus sines, NOT a PRNG:
    -- reseeding per frame would strobe every update_interval, which is exactly
    -- the trap the starfield comment warns about. Every third arc is a lighter
    -- "rub" -- the uneven wear of a piece that gets handled. No
    -- cairo_pattern_create here, so this costs nothing against the leak budget.
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    for i = 1, 16 do
        local a0   = (i * 137.508) * math.pi / 180
        local span = (6 + 11 * math.abs(math.sin(i * 2.7))) * math.pi / 180
        local rr   = RIM_MID + math.sin(i * 1.31) * 2.2
        local rub  = (i % 3 == 0)
        local k    = math.abs(math.sin(i * 0.83))
        set_c(cr, rub and BRASS_BRT or PATINA,
                   rub and (0.07 + 0.09 * k) or (0.13 + 0.17 * k))
        cairo_set_line_width(cr, (1.6 + 1.4 * math.abs(math.sin(i * 1.9))) * S)
        cairo_new_path(cr)
        cairo_arc(cr, CX*S, CY*S, rr*S, a0, a0 + span)
        cairo_stroke(cr)
    end
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)

    -- burnished highlight riding the outer half of the band
    set_c(cr, BRASS_BRT, 0.50)
    cairo_set_line_width(cr, 3.0 * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, (RIM_MID + 2.4)*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- crisp outer edge
    set_c(cr, BRASS_BRT, 0.85)
    cairo_set_line_width(cr, 1.6 * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, RIM_OUT*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- 12 rivets centred in the band
    for i = 0, 11 do
        local a = (i * 30 - 90) * math.pi / 180
        draw_rivet(cr, CX + RIM_MID*math.cos(a), CY + RIM_MID*math.sin(a))
    end
end
-- ======================= BAND FEED ===========================
-- Reads brassviz's own cava feed (0..64). Returns a 12-element array,
-- nil/short/malformed lines -> zeros so a dead feed renders a static
-- instrument instead of crashing mid-draw.
local NRING = 12
local bands = {}
local function read_bands()
    local f = io.open(VALS_PATH, 'r')
    if not f then
        for i = 1, NRING do bands[i] = 0 end
        return bands
    end
    local line = f:read('*l')
    f:close()
    local n = 0
    if line then
        for tok in line:gmatch('%S+') do
            local v = tonumber(tok)
            n = n + 1
            if n > NRING then break end
            if not v or v < 0 then v = 0 end
            if v > 64 then v = 64 end
            bands[n] = v
        end
    end
    for i = n + 1, NRING do bands[i] = 0 end
    return bands
end

-- ======================= RING LAYOUT =========================
-- Bass at the core, treble at the rim: the structure rings must stay clear of
-- the centre plaque (<=79 with its bezel) and of the tick rail (213).

-- Item 3: the user asked to remove every other ring. The structure layer keeps
-- its OWN span rather than skipping alternate indices of PITCH -- doing that
-- would leave the outermost surviving ring at 192 and open a 21-unit dead gap
-- up to the new tick rail at 213, which is the exact defect item 2 exists to
-- close. NRING stays 12 because it is also the cava band count.
local STRUCT_N  = 6
local STRUCT_R0 = 92    -- just outside the plaque bezel (79)
local STRUCT_R1 = 208   -- meets the tick rail at 213
local S_PITCH   = (STRUCT_R1 - STRUCT_R0) / (STRUCT_N - 1)

-- Structure-ring finish. The rings read too dim against the plate (user, twice:
-- "the rings ... need to be brighter"), so they lift off the shadow-family
-- PATINA (luma 59, alpha 0.42 -> composite ~30 over the ground) onto the
-- body-metal colour: same 33deg hue, luma 131, alpha 0.62 -> composite ~85.
-- Tune brightness HERE, one knob per widget; the line width stays untouched
-- because the thinning was itself an approved change.
local RING_COL = BRASS_MID
local RING_A   = 0.70

local function lerp(a, b, t) return a + (b - a) * t end

local function band_color(t)
    -- bass (t=0) reads hot copper, treble (t=1) cools to body brass.
    -- hue stays in the 33deg family; only luma/heat move, per the palette rule.
    return {
        math.floor(lerp(0xcc, 0x9f, t) + 0.5),
        math.floor(lerp(0x95, 0x7f, t) + 0.5),
        math.floor(lerp(0x52, 0x58, t) + 0.5),
    }
end


-- Rings are STRUCTURE only now: static, delicate, always present. The band
-- data lives in the plasma, because concentric data-rings made every loud
-- track a stack of thick brass.
local function draw_structure(cr, cx, cy)
    for j = 1, STRUCT_N do
        set_c(cr, RING_COL, RING_A)
        cairo_set_line_width(cr, 0.9 * S)
        cairo_new_path(cr)
        cairo_arc(cr, cx*S, cy*S, (STRUCT_R0 + (j-1)*S_PITCH)*S, 0, 2*math.pi)
        cairo_stroke(cr)
    end
end

-- The old plasma layer lived here (12 spiralling, off-centre blobs driven by a
-- wall-clock spin) and is gone: it read as decoration, not as data, and its
-- low-alpha outer blobs left a haze across the plate. It is replaced by
-- draw_corona() below -- which needs BEZ_R, so it sits after centre_plaque.
-- Both the old PLAS_IN/PLAS_OUT radii and uptime() (which existed only to
-- drive the spin) went with it.

-- ======================= CENTRE PLAQUE ========================
-- Ties the visualizer to brasspianobar's brass language and gives the
-- innermost ring something to sit against instead of floating in void.
local PLQ_R = 72   -- matches brasspianobar ART_VIS_R
local BEZ_R  = 79   -- matches brasspianobar BEZ_OUT

local function centre_plaque(cr, cx, cy, v)
    -- machined boss: radial dome, lit from upper-left
    local g = cairo_pattern_create_radial(
        (cx - PLQ_R*0.35)*S, (cy - PLQ_R*0.35)*S, 1,
        cx*S, cy*S, PLQ_R*S)
    -- Face colour = the EXACT PLQ_FACE shared by brasspianobar (L481) and
    -- orrery-brass (L823): 0x261e10 -> 0x161107 -> 0x0d0904. All three
    -- plaques now read as one dark brown family (centre luma 33). The
    -- previous stops 0x624d33 -> 0x3d3122 -> 0x241d14 put the centre at
    -- luma 83, a full two steps lighter than its neighbours.
    cairo_pattern_add_color_stop_rgba(g, 0.00, 0x26/255, 0x1e/255, 0x10/255, 0.97)
    cairo_pattern_add_color_stop_rgba(g, 0.55, 0x16/255, 0x11/255, 0x07/255, 0.97)
    cairo_pattern_add_color_stop_rgba(g, 1.00, 0x0d/255, 0x09/255, 0x04/255, 0.97)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, PLQ_R*S, 0, 2*math.pi)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)   -- leak discipline: destroy every pattern

    -- Brass bezel hugging the plaque -- the EXACT recipe from brasspianobar's
    -- album art ring (ART_VIS_R=72 / BEZ_OUT=79), so the two widgets match:
    -- mid band, dark inner seat for depth, bright hairline where metal meets face.
    local bez_mid = (PLQ_R + BEZ_R) * 0.5
    set_c(cr, BRASS_MID, 0.95)
    cairo_set_line_width(cr, (BEZ_R - PLQ_R) * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, bez_mid*S, 0, 2*math.pi)
    cairo_stroke(cr)

    set_c(cr, PATINA, 0.45)
    cairo_set_line_width(cr, 2.2 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, (BEZ_R - 1.6)*S, 0, 2*math.pi)
    cairo_stroke(cr)

    set_c(cr, BRASS_BRT, 0.55)
    cairo_set_line_width(cr, 1.4 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, (PLQ_R + 0.4)*S, 0, 2*math.pi)
    cairo_stroke(cr)


    -- two machining grooves
    for _, rr in ipairs({ PLQ_R - 7, PLQ_R - 11 }) do
        set_c(cr, PATINA, 0.75)
        cairo_set_line_width(cr, 1.0 * S)
        cairo_new_path(cr)
        cairo_arc(cr, cx*S, cy*S, rr*S, 0, 2*math.pi)
        cairo_stroke(cr)
    end

    -- readout: label + the hottest band name, so the plaque earns its space
    text_c(cr, cx, cy - 12, 'SPECTRUM', BRASS_BRT, 11, true, true)
    local names = { 'BASS', 'BASS', 'BASS', 'LOW', 'LOW', 'MID',
                    'MID', 'MID', 'HI', 'HI', 'AIR', 'AIR' }
    local best, bi = -1, 6
    for i = 1, NRING do
        if v[i] > best then best, bi = v[i], i end
    end
    text_c(cr, cx, cy + 8, names[bi], BRASS_MID, 16, true, true)
    -- Percent readout (user, item 4: "very small and hard to read"). It was
    -- RUST_DIM (luma 88) at 9pt, non-bold -- the dimmest, smallest and
    -- thinnest type on the whole widget, on a face that just got darker.
    -- Lift to BRASS_MID (131, +49%), 9 -> 12 (+33%) and bold. Still quieter
    -- than the band name above it (BRASS_MID 16pt) and than SPECTRUM
    -- (BRASS_BRT), so the hierarchy holds.
    text_c(cr, cx, cy + 26, string.format('%d%%', math.floor(best/64*100 + 0.5)),
            BRASS_MID, 12, true, true)
end

-- ======================= SOLAR CORONA =========================
-- Replaces the old plasma: two CENTRED elements derived from the live band
-- feed, both hard-bounded so nothing washes across the plate.
--
--   AURA   hugging the plaque bezel (BEZ_R = 79), swelling with the AVERAGE
--          level. Outer edge = 82 + 40*lvl^0.65, lvl = min(1, 1.30*avg) --
--          82 silent, 122 at full scale -- peak alpha = 0.14 + 0.46*lvl^0.6.
--          Its outer colour stop is fully transparent, so the aura simply
--          ends: no ground haze.
--
--   FLARES one per CAVA band on a FIXED seat 30 deg apart -- no spin, no
--          wobble. Each is a tapered tongue growing out from behind the
--          plaque, tip at 82 + 124*val^0.65 with val = min(1, 1.30*band/64),
--          = 206 at full scale, which is 8.8 units clear of the tick band
--          (214.8). Same gain and coefficient family as the aura, driven by
--          the band's own level instead of the average, so the two read as
--          one light source at two scales.
--
--   EMBERS one resting flame per seat, drawn ONLY while that band is quiet
--          (q = 1 - min(1, band/8), so full at silence, gone by band 8). Tip
--          79 + 26*(0.55 + 0.45*breath), breath = 0.5 + 0.5*sin(up*1.4 + i*0.9)
--          on the wall clock (~4.5 s, phase-offset per seat), alpha
--          (0.05 + 0.09*breath)*q. This is what fills the field at silence,
--          the state the aura/flares simply skip. Emitted through the same
--          tongue() helper as the flares, so the cross-over is seamless.
--
--   PEAKS  one butt-capped brass marker per seat parked at that band's recent
--          maximum: snap up instantly, ease down 42.7 units/s (~1.5 s across
--          the full 0..64 range). Radius = the flare's own tip mapping, so it
--          rides the flame tip like a cap; hidden below level 4. Fixed
--          12-slot table -- nothing accumulates across frames.
--
-- ORDER: this runs BEFORE centre_plaque, so the aura's inner disc and every
-- tongue base are painted over by the plaque and only what reaches past BEZ_R
-- is ever seen. It needs BEZ_R, which is why it is declared after it.
local CORONA_IN   = 79           -- == BEZ_R; bases are hidden by the plaque
local AURA_R0, AURA_R1 = 82, 122 -- aura outer edge, silent .. full scale
local FLARE_MAX   = 206          -- tip ceiling; ticks start at 214.8

local FLARE_SEATS = {}
for i = 1, NRING do
    FLARE_SEATS[i] = (i - 1) * (2 * math.pi / NRING)
end

local FLARE_N = 10   -- tongue samples per side

-- Monotonic wall seconds with sub-second resolution -- drives the ember
-- breath and the peak-hold decay. /proc/uptime is TWO numbers on one line,
-- so tonumber() on the whole line is nil (documented trap): pull the first
-- field first. Closed every call -- no fd held across frames.
local function up_t()
    local f = io.open('/proc/uptime', 'r')
    if not f then return os.time() end
    local s = f:read('*l')
    f:close()
    return tonumber(s and s:match('^(%S+)')) or 0
end

-- PEAK-HOLD state: exactly one slot per band, fixed size 12, never grows.
local peaks   = {}
local last_up = nil

-- One tapered tongue -- shared by the audio flares and the silent-state
-- embers. Wide where it leaves the plaque, a point at the tip: the half-width
-- is converted to an ANGLE (hw/r) at each radius, so the tongue stays a
-- sensible thickness instead of flaring outward -- and it closes across the
-- base, which the plaque then hides. The pattern is created, used, destroyed
-- and the path cleared all inside the helper (PATH-LEAK rule).
local function tongue(cr, cx, cy, ang, tip, a, c, w0)
    local g = cairo_pattern_create_radial(cx*S, cy*S, CORONA_IN*S,
                                          cx*S, cy*S, tip*S)
    cairo_pattern_add_color_stop_rgba(g, 0.00, c[1]/255, c[2]/255, c[3]/255, a)
    cairo_pattern_add_color_stop_rgba(g, 0.55, c[1]/255, c[2]/255, c[3]/255, a*0.45)
    cairo_pattern_add_color_stop_rgba(g, 1.00, c[1]/255, c[2]/255, c[3]/255, 0)
    cairo_set_source(cr, g)
    cairo_new_path(cr)
    for k = 0, FLARE_N do
        local t  = k / FLARE_N
        local r  = CORONA_IN + (tip - CORONA_IN) * t
        local hw = w0 * (1 - t) ^ 0.7
        local aa = ang + hw / r
        local x  = (cx + r * math.cos(aa)) * S
        local y  = (cy + r * math.sin(aa)) * S
        if k == 0 then cairo_move_to(cr, x, y)
        else cairo_line_to(cr, x, y) end
    end
    for k = FLARE_N, 0, -1 do
        local t  = k / FLARE_N
        local r  = CORONA_IN + (tip - CORONA_IN) * t
        local hw = w0 * (1 - t) ^ 0.7
        local aa = ang - hw / r
        cairo_line_to(cr, (cx + r * math.cos(aa)) * S,
                        (cy + r * math.sin(aa)) * S)
    end
    cairo_close_path(cr)
    cairo_fill(cr)
    cairo_pattern_destroy(g)   -- leak discipline: 1 create : 1 destroy
    cairo_new_path(cr)
end

local function draw_corona(cr, cx, cy, v)
    local sum = 0
    for i = 1, NRING do sum = sum + v[i] end
    local avg = sum / (NRING * 64)

    -- Frame time for the decay. First frame (last_up nil) and any stall both
    -- resolve to a sane 0.1 so a resume can't slam every puck to zero.
    local now = up_t()
    local dt  = (last_up and now - last_up) or 0.1
    if dt <= 0 or dt > 2 then dt = 0.1 end
    last_up = now

    -- PEAK-HOLD: snap up instantly, ease down over ~1.5 s across the whole
    -- 0..64 range. Fixed 12-slot table, so nothing accumulates across frames.
    for i = 1, NRING do
        local p = (peaks[i] or 0) - 42.7 * dt
        if v[i] > p then p = v[i] end
        if p < 0 then p = 0 end
        peaks[i] = p
    end

    -- AURA -- a full disc whose 0..CORONA_IN interior is covered by the plaque
    -- drawn on the very next line, leaving only the 79..outer annulus visible.
    -- Silence skips it entirely rather than painting a faint permanent ring.
    -- GAIN (user, 2026-10-07: "a bit more visible and maybe a touch more
    -- sensitive"): the level is lifted 1.30x BEFORE the exponent and the alpha
    -- floor/ceiling move 0.10+0.34 -> 0.14+0.46. Both ceilings are unchanged --
    -- AURA_R1 = 122 and FLARE_MAX = 206 stay hard bounds, so nothing can reach
    -- the tick rail at 214.8 no matter how loud the track is.
    if avg > 0.001 then
        local lvl = math.min(1, avg * 1.30)
        local out_r = AURA_R0 + (AURA_R1 - AURA_R0) * (lvl ^ 0.65)
        local a     = 0.14 + 0.46 * (lvl ^ 0.6)
        local g = cairo_pattern_create_radial(cx*S, cy*S, CORONA_IN*S,
                                              cx*S, cy*S, out_r*S)
        cairo_pattern_add_color_stop_rgba(g, 0.00, COPPER[1]/255, COPPER[2]/255, COPPER[3]/255, a)
        cairo_pattern_add_color_stop_rgba(g, 0.45, COPPER[1]/255, COPPER[2]/255, COPPER[3]/255, a*0.42)
        cairo_pattern_add_color_stop_rgba(g, 1.00, COPPER[1]/255, COPPER[2]/255, COPPER[3]/255, 0)
        cairo_new_path(cr)
        cairo_arc(cr, cx*S, cy*S, out_r*S, 0, 2*math.pi)
        cairo_set_source(cr, g)
        cairo_fill(cr)
        cairo_pattern_destroy(g)   -- leak discipline: 1 create : 1 destroy
        cairo_new_path(cr)
    end

    -- EMBERS -- one resting flame per seat, so a silent ring reads as 12
    -- gently breathing pilots instead of an empty field (user, item 3). Each
    -- fades out exactly as its own flare fades in (full cross-over at band=8),
    -- so a quiet seat hands over to a sounding one with no double image. The
    -- breath runs on the wall clock: ~4.5 s period, phase-offset per seat, so
    -- the 12 never pulse in unison. Fully functional at silence -- no audio
    -- needed -- which is the state the old design simply skipped.
    for i = 1, NRING do
        local q = 1 - math.min(1, v[i] / 8)
        if q > 0.01 then
            local br  = 0.5 + 0.5 * math.sin(now * 1.4 + i * 0.9)
            local tip = CORONA_IN + 26 * (0.55 + 0.45 * br)
            local a   = (0.05 + 0.09 * br) * q
            tongue(cr, cx, cy, FLARE_SEATS[i], tip, a,
                   band_color((i - 1) / (NRING - 1)), 5.0)
        end
    end

    -- FLARES -- one tapered tongue per band.
    for i = 1, NRING do
        local val = math.min(1, (v[i] / 64) * 1.30)   -- same 1.30x gain as the aura
        if val > 0.004 then
            local tip = AURA_R0 + (FLARE_MAX - AURA_R0) * (val ^ 0.65)
            local a   = 0.14 + 0.46 * (val ^ 0.6)
            tongue(cr, cx, cy, FLARE_SEATS[i], tip, a,
                   band_color((i - 1) / (NRING - 1)), 7.0)
        end
    end

    -- PEAK-HOLD pucks -- a short brass marker per seat parked at that band's
    -- recent maximum, easing down over ~1.5 s. It uses the SAME tip mapping
    -- as its flare, so it rides the flame's own tip like a cap. Below level 4
    -- there is nothing worth holding, so it stays hidden. Butt caps, no cap
    -- state left behind for later strokes (CAP-LEAK note in AGENTS).
    for i = 1, NRING do
        local p = peaks[i]
        if p and p >= 4 then
            local val = math.min(1, (p / 64) * 1.30)
            local pr  = AURA_R0 + (FLARE_MAX - AURA_R0) * (val ^ 0.65)
            local ang = FLARE_SEATS[i]
            local w   = math.rad(3.5)
            set_c(cr, band_color((i - 1) / (NRING - 1)), 0.85)
            cairo_set_line_width(cr, 3.0 * S)
            cairo_new_path(cr)
            cairo_arc(cr, cx*S, cy*S, pr*S, ang - w, ang + w)
            cairo_stroke(cr)
            cairo_new_path(cr)
        end
    end
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

    -- Opaque backing, CLIPPED TO THE PLATE DISC. Item 1: "the backgrounds ...
    -- should not be transparent" -- the plate gradient sits at alpha 0.90..0.96,
    -- so with nothing under it the metal bled 4-10% wallpaper through.
    -- The backing must NOT cover the whole window: the plate is a disc of
    -- PLATE_R inside a square window, and a full-rect fill left all four
    -- corners as opaque (10,16,19) black squares (corner distance from centre
    -- is 250*sqrt(2) = 353, far outside the disc). Filling only the disc keeps
    -- the plate opaque while the corners stay CAIRO_OPERATOR_CLEAR'd -- per-pixel
    -- alpha 0 -- so the wallpaper shows through there, as it did before.
    cairo_set_source_rgba(cr, 2/255, 4/255, 6/255, 1.0)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, PLATE_R*S, 0, 2*math.pi)
    cairo_fill(cr)
    -- disc_path() below is built with cairo_new_sub_path(), which APPENDS to the
    -- current path rather than starting one, and this binding does not rely on
    -- cairo_fill() having cleared the path (PATH-LEAK GOTCHA in AGENTS.md). An
    -- uncleared disc here would union with the plate's disc -- same radius, so
    -- harmless today -- but clear it regardless so nothing carries forward.
    cairo_new_path(cr)

    if STAR_W ~= w or STAR_H ~= h then build_stars(w, h) end

    local v = read_bands()

    paint_round_plate(cr)
    starfield_round(cr, PLATE_R - 1)

    draw_structure(cr, CX, CY)
    draw_corona(cr, CX, CY, v)
    centre_plaque(cr, CX, CY, v)
    dial_track(cr, CX, CY)
    dial_ticks(cr, CX, CY, TICK_R)
    dial_bezel(cr, CX, CY, PLATE_R)
    brass_rim(cr)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- ======================= SELF-SPAWN: THE CAVA FEED =================
-- NOTHING else in this system starts the chain. conky-startup.sh
-- launches only the three conkys, there is no autostart/cron/systemd
-- entry for it, and /tmp is tmpfs -- so after every reboot the fifo and
-- the vals file vanish and read_bands(), which is nil-safe BY DESIGN,
-- quietly reports zeros. The widget then renders a perfectly correct
-- but completely STATIC instrument, which is exactly what was reported
-- on 2026-10-07 ("pianobar is running ... nothing happening on the
-- visualizer") after the machine had been rebooted 12 hours earlier.
-- brassviz therefore owns its own feed, the same way clockwidget owns
-- its LED button. Run once at load (this file is loaded per conky
-- start, not per frame), guarded so a second conky never doubles it.
--
-- The path is split across A/B so the literal script path never appears
-- in the spawning shell's own cmdline -- otherwise pgrep -f would match
-- its own caller and we would skip the spawn forever (the self-match
-- trap). The bracket in the pgrep pattern does the same job for the
-- pattern itself.
local function spawn_feed()
    local sh = "HB='" .. (HOME or '') .. "'"
        .. "; S=$HB/.conky/brassviz/scripts"
        .. "; A=cava_brassviz_re; B=ader.sh; C=cava_brassviz.conf"
        .. "; if ! pgrep -f 'cava_brassviz_re[a]der' >/dev/null 2>&1; then"
        .. " setsid \"$S/$A$B\" </dev/null >>\"$HB/.conky/brassviz/reader.log\" 2>&1 & fi"
        .. "; sleep 0.4"
        .. "; if ! pgrep -x cava >/dev/null 2>&1; then"
        .. " setsid cava -p \"$S/$C\" </dev/null >>\"$HB/.conky/brassviz/cava.log\" 2>&1 & fi"
    os.execute(sh)
end

spawn_feed()
