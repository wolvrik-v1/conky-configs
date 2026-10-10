-- ############################################################
--  brasspianobar -- Cairo/Lua Steampunk Renderer (Patinated Edition)
-- ############################################################

require 'cairo'

-- ======================= OPTIONS =============================
local TRANSPARENT_BG = false  -- Change to false to instantly restore backing plate

-- ======================= PATHS ===============================
local HOME        = os.getenv('HOME') or os.getenv('USERPROFILE') or ''
local XDG_CACHE   = os.getenv('XDG_CACHE_HOME') or (HOME .. '/.cache')
local XDG_CONFIG  = os.getenv('XDG_CONFIG_HOME') or (HOME .. '/.config')

local CACHE_PATH  = XDG_CACHE .. '/conky/pianobar-widget.status'
local COVER_JPG   = XDG_CONFIG .. '/pianobar/coverArt.jpg'
local COVER_PNG   = XDG_CACHE .. '/conky/brass_pianobar_cover.png'
local COVER_MARKER = COVER_PNG .. '.mtime'

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
-- Measured off the brass-family wallpaper (ORRERY1), restricted to the ring of bright
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

-- ======================= BACKING PLATE =======================
local function paint_plate(cr, w, h)
    local b = BEZ * S
    rrect(cr, 0, 0, w, h, 6)
    set_c(cr, DARK_IRON, 0.85)
    cairo_fill(cr)
    
    local pw, ph = w - 2*b, h - 2*b
    local g = cairo_pattern_create_radial(w/2, h*0.35, 0, w/2, h*0.35, math.max(w,h)*0.75)
    cairo_pattern_add_color_stop_rgba(g, 0.00, 52/255, 60/255, 74/255, 0.80)
    cairo_pattern_add_color_stop_rgba(g, 0.50, 32/255, 38/255, 48/255, 0.85)
    cairo_pattern_add_color_stop_rgba(g, 1.00, 18/255, 22/255, 28/255, 0.90)
    rrect(cr, b, b, pw, ph, 4)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)

    -- Outer brass border frame (patinated)
    set_c(cr, BRASS_MID, 0.85)
    cairo_set_line_width(cr, 2 * S)
    rrect(cr, b, b, pw, ph, 4)
    cairo_stroke(cr)

    -- Corner reinforcement plates & rivets
    local corner_size = 18 * S
    set_c(cr, BRASS_BRT, 0.35)
    cairo_rectangle(cr, b, b, corner_size, 4*S)
    cairo_rectangle(cr, b, b, 4*S, corner_size)
    cairo_rectangle(cr, w - b - corner_size, b, corner_size, 4*S)
    cairo_rectangle(cr, w - b - 4*S, b, 4*S, corner_size)
    cairo_rectangle(cr, b, h - b - 4*S, corner_size, 4*S)
    cairo_rectangle(cr, b, h - b - corner_size, 4*S, corner_size)
    cairo_rectangle(cr, w - b - corner_size, h - b - 4*S, corner_size, 4*S)
    cairo_rectangle(cr, w - b - 4*S, h - b - corner_size, 4*S, corner_size)
    cairo_fill(cr)

    draw_rivet(cr, b + 10, b + 10)
    draw_rivet(cr, w - b - 10, b + 10)
    draw_rivet(cr, b + 10, h - b - 10)
    draw_rivet(cr, w - b - 10, h - b - 10)
end

-- ======================= MODULE SECTION ======================
local function paint_module(cr, mx, my, mw, mh, corner_r)
    local r = corner_r * S
    rrect(cr, mx, my, mw, mh, r)
    set_c(cr, PLATE_BG, 0.88)
    cairo_fill(cr)

    -- deep-space starfield, clipped to this panel (see STARFIELD notes above)
    starfield(cr, mx, my, mw, mh, r)

    set_c(cr, BRASS_MID, 0.6)
    cairo_set_line_width(cr, 1.2 * S)
    rrect(cr, mx, my, mw, mh, r)
    cairo_stroke(cr)
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

-- ==================== COG GEAR DIAL ==========================
local GSECTIONS = {
    { 1.00, { 0x18, 0x1c, 0x24 } },
    { 0.91, { 0x24, 0x2b, 0x36 } },
    { 0.76, { 0x35, 0x32, 0x2c } },
    { 0.69, { 0x2a, 0x26, 0x22 } },
    { 0.64, { 0x14, 0x16, 0x1a } },
    { 0.60, { 0x8c, 0x6e, 0x3f } },
    { 0.46, { 0x20, 0x1e, 0x1c } },
}

local function dial_well(cr, cx, cy, r)
    for _, sec in ipairs(GSECTIONS) do
        set_c(cr, sec[2], 1)
        cairo_new_path(cr)
        cairo_arc(cr, cx*S, cy*S, r*S*sec[1], 0, 2*math.pi)
        cairo_fill(cr)
    end
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

-- Graduation track. The ticks sat on bare plate with 10 units of dead space
-- before the bezel, which read as "floating out there". This is the
-- brass-orrery recipe in miniature: hairline rails top and tail the tick band
-- (orrery does exactly this at r319/r336, which is what gives it the railroad-
-- track look), then a recessed machined channel ties the track to the bezel so
-- the outer assembly reads as ONE piece rather than a ring and a rim with
-- nothing connecting them.
--
-- The "progress track (ends 213)" in the TICK_R comment above is vestigial --
-- those numbers were ported from orrery-brass's plaque geometry and nothing is
-- drawn anywhere near r213 in this file, so there was no ring for the ticks to
-- attach to. Verified by grep: no radius constant in 195..215 exists here.
--
-- Defined ABOVE conky_draw_now_playing on purpose: a `local function` is only
-- in scope from its declaration down, and calling a helper defined below its
-- caller is the nil-global trap that has already cost this repo two launches.
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

-- ===================== STAGE 3: HUD PLAQUES =========================
-- Four annular-sector plaques at 12/3/6/9, ported from orrery-brass's
-- hud_plate/arc_text/arc_span so the two widgets share one visual language.
--
-- Ported from the FIXED orrery-brass version, deliberately NOT from the
-- quarantined cyber orrery. That one calls cairo_text_extents_t:create() per
-- glyph at six call sites, which is leak class #1 in this codebase (documented
-- in AGENTS.md): lua-cario does not tie that userdata's lifetime to the Lua GC,
-- so every glyph of every frame leaks. These use the single module-level
-- TEXT_EXT declared at the top of this file. Do not "simplify" them into
-- per-glyph :create() calls.
--
-- Plaque geometry, chosen against the radial budget already spent:
--    79 .. 100    air between the art bezel and the plate lip
--   100 .. 176    plate face
--   176 .. 207    air before the progress track at 206.8
local DEG = math.pi / 180

-- Plaque band. RI is anchored OUTWARD: raising it shrinks the plaques from
-- their inner (bottom) edge while RO stays put, so the plates stop covering so
-- much of the dial and vacate a clean inner annulus for the roaming rings.
-- Band height held at 44 and the whole band pushed OUT, rather than the inner
-- edge alone being raised. Measured room: the tick band starts at r214.8 and the
-- progress track ends at 209.8, so r194 still leaves ~16 units of clearance
-- while giving the roaming rings a much bigger share of the inner dial.
local PLAQUE_RI   = 150
local PLAQUE_RO   = 194
local PLQ_INT_D   = 3.2          -- lip band thickness, radial
local PLQ_LIP_D   = 1.8 * DEG    -- lip band, angular
local PLQ_OUT_R   = 176          -- outer text line
local PLQ_IN_R    = 158          -- inner text line

-- Free roaming rings, inside the plaques. Two rings, not one: radius alone
-- identifies the field, so neither title nor album needs a separator, a short
-- field never pads the other, and they can drift at different rates instead of
-- moving in lockstep like one ticker.
--
-- BOTH radii are set by the STRUCTURE rings, not by taste: the text must sit
-- ON a ring with clear air under it, never have one slice through its middle.
-- Measured off the render at S=1 (ink bands, 1-unit polar scan):
--   album 103 -> ink 99.2..106.8, structure ring 1 at 96.0  -> 3.2 gap  CORRECT
--   title 118 -> ink 113.3..122.8, structure ring 2 at 117.6 -> through its middle
-- so the title moved out to give it the SAME 3.2 gap over ring 2 that the album
-- has over ring 1 (user: "the bottom of the text should sit on top of the ring
-- it is currently running through"). 120.8 inner edge + half the 9.5 cap = 125.5.
-- New band 120.8..130.3; ring 3 at 139.2 stays clear (124..137 measured empty).
local ROAM_TITLE_R = 125.5
local ROAM_ALBUM_R = 103
local ROAM_RATE    = 0.30        -- rad/s, one lap ~21s
local ROAM_GAP     = 0.55        -- rad of empty ring between repeats

-- Fixed half-widths in degrees. The plates no longer size themselves to
-- their contents: the long fields roam, so the plates hold short fixed
-- readouts and a constant width is what keeps them visually calm.
local PLQ_HW = { n12 = 30, n3 = 34, n6 = 26, n9 = 26 }



-- Monotonic sub-second clock for the marquee. /proc/uptime is the house source
-- (os.clock is CPU time and drifts; os.time has 1 s resolution, which at a
-- 0.2 s update_interval makes the scroll teleport). It is monotonic, so it also
-- cannot jump backwards when NTP steps the wall clock.
-- The %S+ match is mandatory: the line is "162255.92 401764.08", two numbers,
-- and a bare tonumber() on the whole line returns nil -- which silently froze
-- the whole dial once before (see AGENTS.md, the /proc/uptime trap).
local function mono_now()
    local f = io.open('/proc/uptime', 'r')
    if not f then return 0 end
    local v = tonumber(f:read('*l'):match('^(%S+)'))
    f:close()
    return v or 0
end

-- Padding around the measured text, in degrees. LIP_D matches the plate lip so
-- the glyphs never touch the frame; PAD keeps the two plates visually separate.

-- dark bronze face + brass frame. Same construction as orrery-brass's plaque:
-- a lighter outer lip, a much darker inner face for the text to sit on, a
-- bright arc on the outer edge, a dimmer one on the inner.
local PLQ_LIP = {
    { 0.00, { 0x4a, 0x3a, 0x1e }, 0.97 },
    { 0.50, { 0x2a, 0x21, 0x10 }, 0.97 },
    { 0.95, { 0x5e, 0x4c, 0x28 }, 0.97 },
    { 1.00, { 0x6e, 0x59, 0x30 }, 0.97 },
}
local PLQ_FACE = {
    { 0.00, { 0x26, 0x1e, 0x10 }, 0.97 },
    { 0.55, { 0x16, 0x11, 0x07 }, 0.97 },
    { 1.00, { 0x0d, 0x09, 0x04 }, 0.97 },
}

-- Fill the CURRENT PATH with a radial gradient between r0 and r1, then destroy
-- the pattern. Stops are {offset, {r,g,b} as 0-255 ints, alpha}. This is the
-- one place plaque gradients are made so there is a single destroy site to
-- audit; paint_round_plate predates this helper and builds its own inline.
local function radial_fill(cr, cx, cy, r0, r1, stops)
    local g = cairo_pattern_create_radial(cx*S, cy*S, r0*S, cx*S, cy*S, r1*S)
    for _, st in ipairs(stops) do
        local c = st[2]
        cairo_pattern_add_color_stop_rgba(g, st[1], c[1]/255, c[2]/255, c[3]/255, st[3])
    end
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)
end

local function seg_reverse_arc(cr, cx, cy, r, a1, a2, n)
    for i = 1, n do
        local a = a1 + (a2 - a1) * i / n
        cairo_line_to(cr, cx + math.cos(a)*r, cy + math.sin(a)*r)
    end
end

-- Annular sector from t0..t1, measured clockwise from 12 o'clock like every
-- other angle on this widget.
local function ring_sector_sq(cr, cx, cy, ri, ro, t0, t1)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, ro*S, t0 - math.pi/2, t1 - math.pi/2)
    cairo_line_to(cr, cx*S + math.sin(t1)*ri*S, cy*S - math.cos(t1)*ri*S)
    seg_reverse_arc(cr, cx*S, cy*S, ri*S, t1 - math.pi/2, t0 - math.pi/2, 16)
    cairo_close_path(cr)
end

-- dark plate + brass frame + two corner glints
local function hud_plate(cr, cx, cy, riw, row, t0, t1)
    local r0, r1 = riw - PLQ_INT_D, row + PLQ_INT_D
    local a0, a1 = t0 - PLQ_LIP_D, t1 + PLQ_LIP_D

    ring_sector_sq(cr, cx, cy, r0, r1, a0, a1)
    radial_fill(cr, cx, cy, r0, r1, PLQ_LIP)

    set_c(cr, BRASS_BRT, 0.75)
    cairo_set_line_width(cr, 0.8*S)
    cairo_new_path(cr); cairo_arc(cr, cx*S, cy*S, r1*S, a0 - math.pi/2, a1 - math.pi/2)
    cairo_stroke(cr)

    set_c(cr, RUST_DIM, 0.70)
    cairo_set_line_width(cr, 0.7*S)
    cairo_new_path(cr); cairo_arc(cr, cx*S, cy*S, r0*S, a0 - math.pi/2, a1 - math.pi/2)
    cairo_stroke(cr)

    -- inner face, darker, so the text has a ground to sit on
    ring_sector_sq(cr, cx, cy, riw, row, t0, t1)
    radial_fill(cr, cx, cy, riw, row, PLQ_FACE)

    set_c(cr, BRASS_MID, 0.70)
    cairo_set_line_width(cr, 0.7*S)
    cairo_new_path(cr); cairo_arc(cr, cx*S, cy*S, row*S, t0 - math.pi/2, t1 - math.pi/2)
    cairo_stroke(cr)

    set_c(cr, RUST_DIM, 0.60)
    cairo_set_line_width(cr, 0.7*S)
    cairo_new_path(cr); cairo_arc(cr, cx*S, cy*S, riw*S, t0 - math.pi/2, t1 - math.pi/2)
    cairo_stroke(cr)

    -- glints centred in the lip band, tracking the lip rather than a fixed offset
    local rmid = (r0 + r1) / 2
    for _, ga in ipairs({ a0 + PLQ_LIP_D*0.55, a1 - PLQ_LIP_D*0.55 }) do
        local bx = cx*S + math.sin(ga)*rmid*S
        local by = cy*S - math.cos(ga)*rmid*S
        set_c(cr, BRASS_BRT, 0.85)
        cairo_new_path(cr); cairo_arc(cr, bx, by, 1.5*S, 0, 2*math.pi); cairo_fill(cr)
    end
end

-- angular width of a set of strings, in radians, using the shared TEXT_EXT
-- Split a string into UTF-8 CODEPOINTS, never into bytes.
--
-- Byte-wise `str:sub(i, i)` hands cairo half of a multi-byte character.
-- cairo_text_extents() then reports CAIRO_STATUS_INVALID_UTF8 (measured here as
-- cairo_status() == 8, "input string not valid UTF-8"), and that status is
-- PERMANENT for the context: every draw call after it becomes a silent no-op,
-- and no Lua error is raised -- so the log stays clean while rings, plaques,
-- bezel and rim all disappear together. One accented track title was enough.
local function glyphs(str)
    local t = {}
    for _, c in utf8.codes(str) do t[#t+1] = utf8.char(c) end
    return t
end

local function arc_span(cr, rad, segs)
    local total = 0
    for _, sg in ipairs(segs) do
        cairo_select_font_face(cr, FMONO, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, sg.size*S)
        for _, g in ipairs(glyphs(sg.str)) do
            cairo_text_extents(cr, g, TEXT_EXT)
            total = total + TEXT_EXT.x_advance
        end
    end
    return total / (rad*S)
end

-- Per-glyph text along a circle, each glyph rotated to the ring with its INK
-- BOX centred (y0 = -beary - h/2). Centring the ink in the glyph's own rotated
-- space IS radial centring at every angle, so this idiom needs no cos(a)
-- baseline fudge -- see AGENTS.md TEXT-ON-A-RING. The naive alternative
-- (cairo_move_to straight to the anchor) is what produces the ragged
-- angle-dependent labels this widget must not have.
local function arc_text(cr, cx, cy, rad, ang_center, segs, rot_off, ang_off)
    rot_off = rot_off or 0
    local chars = {}
    for _, sg in ipairs(segs) do
        cairo_select_font_face(cr, FMONO, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, sg.size*S)
        for _, g in ipairs(glyphs(sg.str)) do
            cairo_text_extents(cr, g, TEXT_EXT)
            chars[#chars+1] = {
                ch = g, adv = TEXT_EXT.x_advance,
                bearx = TEXT_EXT.x_bearing, w = TEXT_EXT.width,
                h = TEXT_EXT.height, beary = TEXT_EXT.y_bearing, sg = sg,
            }
        end
    end

    local total = 0
    for _, cc in ipairs(chars) do total = total + cc.adv end

    local dir = (rot_off == 0) and 1 or -1
    -- ang_off slides the whole run along the arc, which is how the 12:00 title
    -- marquees without losing the ring curvature the glyphs sit on.
    local a = ang_center + (ang_off or 0) - dir * (total/(rad*S)) / 2
    for _, cc in ipairs(chars) do
        a = a + dir * (cc.adv/(rad*S)) / 2
        local px = cx + math.sin(a)*rad*S
        local py = cy - math.cos(a)*rad*S
        cairo_save(cr)
        cairo_translate(cr, px, py)
        cairo_rotate(cr, a + rot_off)
        cairo_select_font_face(cr, FMONO, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, cc.sg.size*S)
        local x0 = -cc.bearx - cc.w/2
        local y0 = -cc.beary - cc.h/2
        if cc.sg.lip then                      -- engraved: dark lip, then body
            cairo_set_source_rgba(cr, cc.sg.lip[1]/255, cc.sg.lip[2]/255, cc.sg.lip[3]/255,
                                  cc.sg.lipA or 0.7)
            cairo_move_to(cr, x0 + (cc.sg.depth or 1.1)*S, y0 + (cc.sg.depth or 1.1)*S)
            cairo_show_text(cr, cc.ch)
            set_c(cr, cc.sg.body, cc.sg.bodyA or 0.9)
        end
        cairo_move_to(cr, x0, y0)
        cairo_show_text(cr, cc.ch)
        cairo_restore(cr)
        a = a + dir * (cc.adv/(rad*S)) / 2
    end
end

-- Shrink to fit, then hard-truncate. Song titles are unbounded, so a fixed
-- plate width has to degrade gracefully instead of running over its neighbours.
-- Returns the string and the size actually used.
local PLQ_MIN_SZ = 6.5
local function fit_span(cr, str, rad, size, max_deg)
    if str == nil or str == '' then return '', size end
    local want = max_deg * DEG
    local g = glyphs(str)
    -- Truncate by whole CODEPOINTS. The old `str:sub(1, #str - 1)` removed one
    -- byte at a time, so it could cut a multi-byte character in half and leave
    -- invalid UTF-8 at the tail -- which poisons the context, see glyphs().
    while size > PLQ_MIN_SZ
        and arc_span(cr, rad, { {str=table.concat(g), size=size} }) > want do
        size = size - 0.5
    end
    while #g > 1 and arc_span(cr, rad, { {str=table.concat(g), size=size} }) > want do
        g[#g] = nil
    end
    return table.concat(g), size
end

local PLAQUE_BODY = BRASS_BRT
local PLAQUE_SUB  = BRASS_MID

local function file_exists(path)
    local h = io.open(path, 'rb')
    if h then h:close(); return true end
    return false
end

local function shell_quote(v)
    return "'" .. tostring(v):gsub("'", "'\\''") .. "'"
end

local function file_mtime(path)
    local h = io.popen('stat -c %Y ' .. "'" .. path .. "'" .. ' 2>/dev/null')
    if not h then return 0 end
    local v = tonumber(h:read('*a') or '') or 0
    h:close()
    return v
end

local function draw_cover_image(cr, cx, cy, img_r)
    local jpg_mtime = file_mtime(COVER_JPG)
    if jpg_mtime > 0 then
        local marker_h = io.open(COVER_MARKER, 'r')
        local marker_v = marker_h and marker_h:read('*l') or ''
        if marker_h then marker_h:close() end
        if marker_v ~= tostring(jpg_mtime) or not file_exists(COVER_PNG) then
            os.remove(COVER_PNG)
            local sz = math.floor(img_r * 2 + 0.5)
            local cmd = string.format(
                'convert %s -resize %dx%d^ -gravity center -extent %dx%d %s 2>/dev/null',
                shell_quote(COVER_JPG), sz, sz, sz, sz, shell_quote(COVER_PNG)
            )
            os.execute(cmd)
            if file_exists(COVER_PNG) then
                local mh = io.open(COVER_MARKER, 'w')
                if mh then mh:write(tostring(jpg_mtime)); mh:close() end
            else
                os.remove(COVER_MARKER)
            end
        end
    else
        os.remove(COVER_PNG)
        os.remove(COVER_MARKER)
    end

    if file_exists(COVER_PNG) then
        local ok, img = pcall(cairo_image_surface_create_from_png, COVER_PNG)
        if ok and img then
            local iw = cairo_image_surface_get_width(img)
            local ih = cairo_image_surface_get_height(img)
            if iw > 0 and ih > 0 then
                cairo_save(cr)
                cairo_new_path(cr)
                cairo_arc(cr, cx*S, cy*S, img_r*S, 0, 2*math.pi)
                cairo_clip(cr)
                cairo_translate(cr, cx*S - img_r*S, cy*S - img_r*S)
                cairo_scale(cr, (img_r*2*S)/iw, (img_r*2*S)/ih)
                cairo_set_source_surface(cr, img, 0, 0)
                cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BILINEAR)
                cairo_paint(cr)
                cairo_restore(cr)
            end
            cairo_surface_destroy(img)
            return true
        end
    end
    return false
end

local function draw_cover_placeholder(cr, cx, cy, r)
    cairo_set_source_rgba(cr, 0.08, 0.10, 0.13, 1.00)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, r*S, 0, 2*math.pi)
    cairo_fill(cr)
    set_c(cr, BRASS_MID, 0.6)
    cairo_set_line_width(cr, 1.5 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, r*0.5*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

-- ==================== CACHE PARSING ==========================
local STATUS_PATTERN = '^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$'

local function clean(v)
    v = tostring(v or ''):gsub('[\t\r\n|]', ' '):gsub('%s+', ' ')
    return v:sub(1, 600)
end

local function read_cache()
    local h = io.open(CACHE_PATH, 'r')
    if not h then return nil end
    local line = h:read('*l') or ''
    h:close()
    return line
end

local function parse_status(line)
    local title, artist, album, dur, pos, state = line:match(STATUS_PATTERN)
    if not title then return nil end
    dur, pos = tonumber(dur) or 0, tonumber(pos) or 0
    state = clean(state):lower()
    local active = state ~= 'stopped' and (title ~= '' or artist ~= '')
    return { title=clean(title), artist=clean(artist), album=clean(album), duration=dur, position=pos, state=state, active=active }
end

local function get_data()
    local line = read_cache()
    if not line or line == '' then return { title='', artist='', album='', duration=0, position=0, state='stopped', active=false } end
    return parse_status(line) or { title='', artist='', album='', duration=0, position=0, state='stopped', active=false }
end

local function format_time(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format('%d:%02d', math.floor(sec/60), sec%60)
end

-- cx/cy are PARAMETERS, not the CX/CY locals. Those are declared ~120 lines
-- further down, and Lua locals only scope downward, so referencing them from
-- here silently resolves to a nil GLOBAL. That is the same failure as the
-- "helper defined below its caller" trap in AGENTS.md, just inverted -- and it
-- is why dial_bezel/dial_ticks on this file take (cx, cy) as arguments. First
-- draft of this function read `local cx, cy = CX, CY` and threw
-- "attempt to perform arithmetic on a nil value (local 'cx')" on every frame,
-- which drew NOTHING and still left a correct-looking dial on screen.

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
local function roam(cr, cx, cy, rad, segs, now, key)
    if segs == nil then return end
    local span = arc_span(cr, rad, segs)
    if span <= 0 then return end
    local n = math.max(1, math.floor(2*math.pi / (span + ROAM_GAP)))
    local step = 2*math.pi / n
    -- Stagger the two rings so they never sit mirror-symmetric, which reads as
    -- a mistake rather than as two independent fields.
    local ph = (now*ROAM_RATE + (tonumber(key) or 0)*1.7) % step
    for i = 0, n - 1 do
        arc_text(cr, cx, cy, rad, ph + i*step, segs, 0, 0)
    end
end
local function hud_readout(cr, cx, cy, d)
    local now = mono_now()

    -- Two free roaming rings, unclipped, carrying the two unbounded fields.
    -- They live inside the plaques now, so nothing is ever truncated and no
    -- plate has to grow to fit a title.
    roam(cr, cx, cy, ROAM_TITLE_R, {
        { str = (d.title or ''):upper(), size = 13, body = BRASS_BRT, bodyA = 0.95,
          lip = { 0x24, 0x1a, 0x0a }, lipA = 0.75, depth = 1.2 },
    }, now, '0')
    roam(cr, cx, cy, ROAM_ALBUM_R, {
        { str = (d.album or ''):upper(), size = 10.5, body = BRASS_MID, bodyA = 0.85,
          lip = { 0x1a, 0x12, 0x06 }, lipA = 0.7, depth = 1.0 },
    }, now, '1')

    -- Artist is the one long field still pinned to a plate. It is kept because
    -- it is the one line that identifies who is playing, and truncating it is
    -- worse than letting the plate hold a smaller size.
    local ar = (d.artist or ''):upper()

    -- 12:00 -- clock over date. Fixed width, so it never needs to move.
    local tdate = os.date('%H:%M')
    local ddate = os.date('%a %d/%m')
    hud_plate(cr, cx, cy, PLAQUE_RI, PLAQUE_RO, -PLQ_HW.n12*DEG, PLQ_HW.n12*DEG)
    arc_text(cr, cx, cy, PLQ_OUT_R, 0, {
        { str = tdate, size = 17, body = COPPER, bodyA = 0.95,
          lip = { 0x2a, 0x1e, 0x0c }, lipA = 0.8, depth = 1.2 },
    })
    arc_text(cr, cx, cy, PLQ_IN_R, 0, {
        { str = ddate, size = 10.5, body = PLAQUE_SUB, bodyA = 0.85,
          lip = { 0x1a, 0x12, 0x06 }, lipA = 0.7, depth = 1.0 },
    })

    -- 3:00 -- artist over transport state.
    local st = (d.state or ''):upper()
    hud_plate(cr, cx, cy, PLAQUE_RI, PLAQUE_RO,
              math.pi/2 - PLQ_HW.n3*DEG, math.pi/2 + PLQ_HW.n3*DEG)
    -- fit_span returns TWO values (str, size). Capturing only the first put the
    -- STRING into the size field, which is what produced
    -- "attempt to perform arithmetic on a string value (field 'size')".
    local art, ars = fit_span(cr, ar, PLQ_OUT_R, 12, 2*(PLQ_HW.n3 - 4))
    arc_text(cr, cx, cy, PLQ_OUT_R, math.pi/2, {
        { str = art, size = ars, body = PLAQUE_BODY, bodyA = 0.92,
          lip = { 0x2a, 0x1e, 0x0c }, lipA = 0.8, depth = 1.2 },
    })
    arc_text(cr, cx, cy, PLQ_IN_R, math.pi/2, {
        { str = st, size = 9.5, body = PLAQUE_SUB, bodyA = 0.8,
          lip = { 0x1a, 0x12, 0x06 }, lipA = 0.7, depth = 1.0 },
    })

    -- 6:00 -- elapsed over total. rot_off pi flips the glyphs upright; without
    -- it a 6 o'clock label renders upside down, because rot_off also reverses
    -- the advance direction so the text still reads left-to-right.
    local el = d.active and format_time(d.position) or '--:--'
    local tt = d.duration > 0 and format_time(d.duration) or '--:--'
    hud_plate(cr, cx, cy, PLAQUE_RI, PLAQUE_RO,
              math.pi - PLQ_HW.n6*DEG, math.pi + PLQ_HW.n6*DEG)
    arc_text(cr, cx, cy, PLQ_OUT_R, math.pi, {
        { str = el, size = 17, body = COPPER, bodyA = 0.95,
          lip = { 0x2a, 0x1e, 0x0c }, lipA = 0.8, depth = 1.2 },
    }, math.pi)
    arc_text(cr, cx, cy, PLQ_IN_R, math.pi, {
        { str = 'OF ' .. tt, size = 10.5, body = PLAQUE_SUB, bodyA = 0.85,
          lip = { 0x1a, 0x12, 0x06 }, lipA = 0.7, depth = 1.0 },
    }, math.pi)

    -- 9:00 -- remaining over a label.
    local rem = d.active and format_time(math.max(0, d.duration - d.position)) or '--:--'
    hud_plate(cr, cx, cy, PLAQUE_RI, PLAQUE_RO,
              3*math.pi/2 - PLQ_HW.n9*DEG, 3*math.pi/2 + PLQ_HW.n9*DEG)
    arc_text(cr, cx, cy, PLQ_OUT_R, 3*math.pi/2, {
        { str = rem, size = 17, body = COPPER, bodyA = 0.95,
          lip = { 0x2a, 0x1e, 0x0c }, lipA = 0.8, depth = 1.2 },
    }, math.pi)
    arc_text(cr, cx, cy, PLQ_IN_R, 3*math.pi/2, {
        { str = 'LEFT', size = 9.5, body = PLAQUE_SUB, bodyA = 0.8,
          lip = { 0x1a, 0x12, 0x06 }, lipA = 0.7, depth = 1.0 },
    }, math.pi)
end
-- ===================== STAGE 2: CENTRE =============================
-- Album art is the centre, ringed. It stands where orrery-brass puts its sun:
-- the one body everything else is read against.
--
-- There is no gear train here, and that is deliberate. An earlier version had a
-- 34-tooth cog, a satellite pinion meshing with it, and a chain to drive the
-- progress arc. Two things killed it. The satellite's arc pitch (2*pi*Rp/N) was
-- 25% off its main cog's, so those teeth could never actually interleave no
-- matter what the phase offset said. And the whole assembly wanted ~93 units of
-- the upper annulus -- the same annulus the song title has to use. "Fixing" it
-- meant inventing linkage to justify parts the widget does not need. A music
-- widget is not an orrery; borrowing the vocabulary is the point, not the
-- mechanism.
--
-- Radial budget, concentric rather than guessed:
--     0  ..  72   album art
--    72  ..  79   brass bezel band
--    79  .. 110   free -- graduation band and text live out here
--   110  .. 203   free -- Stage 3's text field
local ART_VIS_R = 72
local BEZ_OUT   = 79
--
-- There used to be a 34-tooth cog here, plus a satellite pinion meshing with it
-- and a chain to drive the progress arc. All of that is gone. It was two
-- mistakes wearing a mechanism: the satellite's arc pitch was 25% off its main
-- cog so the teeth could never actually interleave, and the whole assembly
-- needed ~93 units of the upper annulus that the text has to use. Mechanically
-- "fixing" it would have meant inventing linkage to justify parts the widget
-- does not need.
--
-- What replaces it is the orrery's actual centre: one body, ringed. Album art
-- stands where the sun stands -- it is the thing everything else is read
-- against -- and it gets the same vocabulary the sun gets: a bezel, a dark inner
-- edge for depth, and a bright hairline where metal meets image. That is the
-- whole trick to looking like it belongs beside orrery-brass without pretending
-- to be a solar system.
local function draw_center_stack(cr, cx, cy)
    if not draw_cover_image(cr, cx, cy, ART_VIS_R) then
        draw_cover_placeholder(cr, cx, cy, ART_VIS_R)
    end

    -- brass bezel hugging the art: mid band, dark inner edge for depth, and a
    -- bright hairline where the bezel meets the picture
    local bez_mid = (ART_VIS_R + BEZ_OUT) * 0.5
    set_c(cr, BRASS_MID, 0.95)
    cairo_set_line_width(cr, (BEZ_OUT - ART_VIS_R) * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx * S, cy * S, bez_mid * S, 0, 2 * math.pi)
    cairo_stroke(cr)

    set_c(cr, PATINA, 0.45)
    cairo_set_line_width(cr, 2.2 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx * S, cy * S, (BEZ_OUT - 1.6) * S, 0, 2 * math.pi)
    cairo_stroke(cr)

    set_c(cr, BRASS_BRT, 0.55)
    cairo_set_line_width(cr, 1.4 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx * S, cy * S, (ART_VIS_R + 0.4) * S, 0, 2 * math.pi)
    cairo_stroke(cr)
end

-- ===================== MAIN DRAW =============================
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

-- ---------------------------------------------------------------------------
-- Plaque mounting band + structure rings
--
-- Ported from the brass orrery. Both are drawn BEFORE hud_readout (see
-- conky_draw_now_playing below), so the four bolted plaques paint over them:
-- they pass BEHIND the plates and show only in the gaps between the seats.
-- That was the user's call -- "pass behind the plaques".
--
-- The two do not overlap: the band spans 168.9..175.1 (after slimming, see
-- BAND_W), the rings sit at 160.4 and 182.2. So the order between them is not
-- load-bearing -- the band is a substrate and substrates go underneath, but
-- nothing here depends on it.
-- ---------------------------------------------------------------------------

-- MOUNTING BAND: the orrery's bezel-band recipe, proportionally scaled to this
-- widget's plaques, so the plaque bolts attach to something real.
--
-- Orrery proportions: the plates span r292..r332 (40 units) and the band is
-- r307..r317 (10 units) -- 25% of the plate width, centred on it. This widget
-- INHERITED that 25% ratio (50.4 * 0.25 = 12.6 wide, r165.7..178.3), and the
-- user asked for it "much thinner": ratio halved to 12.5%, 6.3 units,
-- r168.85..175.15. Centred at 172 -- exactly where hud_plate puts its two bolt
-- glints (`rmid = (r0 + r1) / 2`) -- so slimming it symmetrically keeps the
-- bolts on the strap: a 1.5-radius glint spans 170.5..173.5, still 1.6 clear
-- inside each rail. Derived from the plaque constants rather than typed, so it
-- stays in step if the plaques are ever re-proportioned. Side effect worth
-- knowing: the flanking structure rings gain clearance, 160.4/182.2 now sit
-- 8.45 and 7.05 out instead of 4.9 and 3.5.
local PLQ_PLATE_IN  = PLAQUE_RI - PLQ_INT_D
local PLQ_PLATE_OUT = PLAQUE_RO + PLQ_INT_D
local BAND_C        = (PLQ_PLATE_IN + PLQ_PLATE_OUT) * 0.5        -- 172, the bolt line
local BAND_W        = (PLQ_PLATE_OUT - PLQ_PLATE_IN) * 0.125       -- 6.3, was 0.25 (orrery's ratio)
local BAND_IN       = BAND_C - BAND_W * 0.5                        -- 168.85
local BAND_OUT      = BAND_C + BAND_W * 0.5                        -- 175.15

local function mount_ring(cr, cx, cy)
    cairo_set_line_width(cr, (BAND_OUT - BAND_IN) * S)

    -- THE FILL IS THE WHOLE FIX. A bare hairline cannot exceed its own luma
    -- over near-black, so alpha tuning never makes a band like this read -- it
    -- needs a GROUND, with only the edge rails on top. The ground is a WIDE
    -- STROKE (centred on (IN+OUT)/2, line width OUT-IN), which covers exactly
    -- IN..OUT and needs no cairo_arc_negative, whose presence in this binding
    -- is unverified. Same construction brass_rim and dial_track use.
    -- NO GROOVES, deliberately: at this width they are simply not visible
    -- ("it won't be grooved because you can't see the grooves anyway").

    -- Gradient ground. The pattern is destroyed immediately after
    -- cairo_set_source: cairo takes its own reference, so this is required
    -- bookkeeping, not decoration -- an un-destroyed pattern leaks ~5 GB/hour
    -- in this binding even with a per-frame cairo_destroy (LEAK / STABILITY).
    local g = cairo_pattern_create_radial(cx*S, cy*S, BAND_IN*S,
                                          cx*S, cy*S, BAND_OUT*S)
    for _, st in ipairs({
        { 0.00, RUST_DIM, 0.98 },
        { 0.42, BRASS_MID, 0.98 },
        { 0.58, BRASS_MID, 0.98 },
        { 1.00, RUST_DIM, 0.98 },
    }) do
        local c = st[2]
        cairo_pattern_add_color_stop_rgba(g, st[1],
            c[1]/255, c[2]/255, c[3]/255, st[3])
    end
    cairo_set_source(cr, g)
    cairo_pattern_destroy(g)

    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, BAND_C*S, 0, 2*math.pi)
    cairo_stroke(cr)

    -- edge rails: crisp ends on the ground, widths and alphas verbatim from
    -- the orrery (inner 0.85/0.9, outer 0.90/1.0)
    local function rail(rad, a, w)
        set_c(cr, BRASS_MID, a)
        cairo_set_line_width(cr, w * S)
        cairo_new_path(cr)
        cairo_arc(cr, cx*S, cy*S, rad*S, 0, 2*math.pi)
        cairo_stroke(cr)
    end
    rail(BAND_IN,  0.85, 0.9)
    rail(BAND_OUT, 0.90, 1.0)
    cairo_new_path(cr)   -- cairo_stroke() does NOT clear the path here
end

-- STRUCTURE RINGS: six static, delicate circles that read as instrument
-- structure rather than data -- same count, width and alpha as brassviz
-- (PATINA @0.42, 0.9 units), but the span is re-pitched for THIS widget's
-- geometry. brassviz's 96..208 would put ring 1 on the cog dial rim
-- (DIAL_R = 92) and ring 6 straight through the progress track at
-- 206.8..209.8. Measured clearances at 96..204, pitch 21.6:
--
--    96.0  just outside the cog (92)         3.6
--   117.6  centred in the roam-text gap       3.2 in from album, 2.0 to title
--   139.2  free annulus                      --
--   160.4  above the mounting band (165.7)    4.9
--   182.2  below the mounting band (178.3)    3.5
--   204.0  above the progress track (206.8)   2.4
--
-- The two rings at 160.4 and 182.2 fall inside the plaque annulus, so they are
-- hidden behind the plates and appear only between the seats -- intended.
local STRUCT_N  = 6
local STRUCT_R0 = 96
local STRUCT_R1 = 204
local S_PITCH   = (STRUCT_R1 - STRUCT_R0) / (STRUCT_N - 1)

-- Structure-ring finish. The rings read too dim against the plate (user, twice:
-- "the rings ... need to be brighter"), so they lift off the shadow-family
-- PATINA (luma 59, alpha 0.42 -> composite ~30 over the ground) onto the
-- body-metal colour: same 33deg hue, luma 131, alpha 0.62 -> composite ~85.
-- Tune brightness HERE, one knob per widget; the line width stays untouched
-- because the thinning was itself an approved change.
local RING_COL = BRASS_MID
local RING_A   = 0.70

local function draw_structure(cr, cx, cy)
    for j = 1, STRUCT_N do
        set_c(cr, RING_COL, RING_A)
        cairo_set_line_width(cr, 0.6 * S)
        cairo_new_path(cr)
        cairo_arc(cr, cx*S, cy*S, (STRUCT_R0 + (j-1)*S_PITCH)*S, 0, 2*math.pi)
        cairo_stroke(cr)
    end
    -- cairo_stroke() does NOT clear the current path in this binding
    -- (PATH-LEAK GOTCHA); leave nothing for draw_center_stack to inherit.
    cairo_new_path(cr)
end

function conky_draw_now_playing()
    if conky_window == nil then return end
    local w = conky_window.width
    local h = conky_window.height
    -- GUARD: on the first hook call width/height can be 0, which would make S=0
    -- and any step derived from it an infinite loop. Do not remove.
    if w < 8 or h < 8 then return end
    S = w / GRID_W

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, w, h)
    local cr = cairo_create(cs)
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
    -- NOTE: no cairo_set_antialias here. CAIRO_ANTIALIAS_BEST does NOT exist in
    -- conky's lua-cairo (only DEFAULT/NONE/GRAY/SUBPIXEL), so asking for it is a
    -- silent no-op. Cairo already antialiases; GRAY is byte-identical to DEFAULT.

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

    local d = get_data()

    -- ---- concentric skeleton ----
    paint_round_plate(cr)
    starfield_round(cr, PLATE_R - 1)

    -- mounting band + structure rings: UNDER the plaques, so hud_readout below
    -- paints its four bolted plates across them and they show only in the gaps
    mount_ring(cr, CX, CY)
    draw_structure(cr, CX, CY)

    draw_center_stack(cr, CX, CY)

    dial_track(cr, CX, CY)
    dial_ticks(cr, CX, CY, TICK_R)
    hud_readout(cr, CX, CY, d)
    dial_bezel(cr, CX, CY, PLATE_R)
    brass_rim(cr)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
