-- ############################################################
--  MetalSysMonitor -- Cairo/Lua renderer (v6: square, dark bezel)
--  A system-monitor panel in the style of the jpope conky
--  clockwidget: a dark translucent outer bezel frame around a
--  warm-grey brushed-metal plate with three instrument sections
--  (thin contour lines, square corners), DejaVu typefaces.
--
--  Layout (230×1040 design grid):
--    Module 1: title "Bodhi 7.0" + STORAGE arc + ROOT / HOME + UPTIME
--    Module 2: 4× CPU speedometer gauges (clock-face style)
--    Module 3: NETWORK block (ESSID / signal bar / UP / DOWN / IP)
--
--  conky.text is empty; every label and value is drawn here
--  via conky_parse().  All geometry is on the design grid and
--  scales with the window.
-- ############################################################

require 'cairo'

-- ======================= USER OPTIONS =========================
local TITLE = 'Bodhi 7.0'
local WDEV  = 'wlan0'
for line in io.lines('/proc/net/wireless') do
    local name = line:match('^%s*([%w]+):%s+')
    if name then WDEV = name break end
end

local DW    = 230                          -- design grid width
local DH    = 1115                         -- design grid height

-- OUTER BEZEL + MODULE LAYOUT (sections on the backing plate)
-- All values are on the 230×1040 design grid.
local BEZ    = 10                          -- outer bezel width (dark translucent frame)
local MOD_MX = BEZ + 10                    -- module left margin (= 24)
local MOD_W  = DW - 2 * MOD_MX            -- module width (= 182)
local MOD_CR = 0                           -- module corner radius (square)

-- Module 1: title + storage plate (rings + % inside)
local M1_Y, M1_H = 20, 150

-- Module 2: CPU gauges
local M2_Y, M2_H = 185, 595

-- Module 3: top processes
local M3_Y, M3_H = 795, 130

-- Module 4: network
local M4_Y, M4_H = 940, 145

-- STORAGE: raised half-circle plate with two CONCENTRIC half-ring gauges
-- (ROOT outer, HOME inner) sharing the plate centre — fills the plate width
-- and keeps the bands close together. (labels/values below the plate and
-- UPTIME were removed 2026-09-12 per user; resized to concentric 2026-09-13)
local PL_CX, PL_CY     = 115, 148        -- plate centre (dome; flat bottom at PL_CY)
local PL_R             = 86              -- plate radius (apex at PL_CY-PL_R)
local R_CY             = 148             -- BOTH half-rings share the plate centre y
local R1_R             = 78              -- ROOT (outer) half-ring radius
local R2_R             = 50              -- HOME (inner) half-ring radius
local R1_TX            = 85              -- ROOT pct baseline: mid gap between rings (12 o'clock)
local R2_TX            = 126             -- HOME pct baseline: inside inner disk

-- CPU gauges (centred in module 2)
local CPU_CX    = 115                      -- gauge centre x (module centre)
local CPU_R     = 60                       -- gauge radius (grid)
local CPU_CYS   = { 260, 404, 548, 692 }  -- gauge centre y's (144 apart)

-- PROCESSES block (inside module 3)
local PRC_HDR_Y = 817                    -- "PROCESSES" header
local PRC_ROW_Y = 843                    -- first process row baseline
local PRC_ROW_DY = 24                    -- row spacing

-- NETWORK block (inside module 4)
local NET_HDR_Y  = 962                    -- "NETWORK" header
local NET_ESSID  = 980                    -- ESSID row
local NET_BAR    = 995                    -- signal bar y
local NET_UP     = 1015                   -- UP row
local NET_DOWN   = 1035                   -- DOWN row
local NET_IP     = 1055                   -- IP row

-- Content margins (relative to module edges)
local CNT_LX  = MOD_MX + 10              -- left text x  (= 30)
local CNT_RX  = MOD_MX + MOD_W - 10      -- right text x (= 200)
local MOD_CX  = MOD_MX + MOD_W / 2       -- module centre x (= 115)

-- palette
local WHITE  = { 0xf2, 0xf5, 0xf7 }
local TXT    = { 0xe8, 0xec, 0xef }
local GREY   = { 0x9a, 0xa4, 0xac }
local DARK   = { 0x2a, 0x2d, 0x31 }
local DISC   = { 0x14, 0x14, 0x16 }
local ARCCOL = { 0xbb, 0xbb, 0xbb }
local BLUE   = { 0x3a, 0x8f, 0xd6 }
local RED    = { 0xff, 0x3b, 0x30 }

-- clock-face gauge colours (same as the clockwidget-orig face)
local TICKMAJOR = { 0x9e, 0xa6, 0xb0 }    -- 12 long light-grey major ticks
local TICKMINOR = { 0x6e, 0x77, 0x81 }    -- 48 short minor ticks
local HANDCOL   = { 0xcf, 0xd6, 0xdc }    -- needle (bright grey-white)
-- concentric sections, largest → smallest (last colour wins centre)
local GSECTIONS = {
    { 1.00, { 0x14, 0x14, 0x16 } },
    { 0.91, { 0x2e, 0x2e, 0x2e } },
    { 0.76, { 0x52, 0x52, 0x52 } },
    { 0.69, { 0x56, 0x56, 0x55 } },
    { 0.64, { 0x14, 0x14, 0x16 } },
    { 0.60, { 0x6c, 0x6b, 0x6a } },
    { 0.46, { 0x43, 0x43, 0x43 } },
}
-- needle geometry (as fractions of the gauge radius)
local NEEDLE_IN   = 0.46                   -- base at inner-circle edge
local NEEDLE_TIP  = 0.88                   -- tip near the rim

local S = 1

-- ======================== HELPERS ===========================
local function set_c(cr, c, a)
    cairo_set_source_rgba(cr, c[1]/255, c[2]/255, c[3]/255, a or 1)
end

local function rrect(cr, x, y, w, h, r)
    if r > w/2 then r = w/2 end
    if r > h/2 then r = h/2 end
    cairo_new_sub_path(cr)
    cairo_arc(cr, x+w-r, y+r,   r, -math.pi/2, 0)
    cairo_arc(cr, x+w-r, y+h-r, r, 0,          math.pi/2)
    cairo_arc(cr, x+r,   y+h-r, r, math.pi/2,  math.pi)
    cairo_arc(cr, x+r,   y+r,   r, math.pi,    3*math.pi/2)
    cairo_close_path(cr)
end

-- ======================== BACKING PLATE =====================
-- Dark translucent outer bezel frame (square corners) around a
-- warm-grey convex metal plate -- matches the clockwidget's
-- translucent-dark backdrop edge look.
local function contour_line(cr, x, y, w, h, r, lc, la, dc, da, lw)
    if r < 0.5 then
        -- Square corners: light top+left corner, dark right+bottom corner
        set_c(cr, lc, la)
        cairo_set_line_width(cr, lw)
        cairo_move_to(cr, x, y + h)
        cairo_line_to(cr, x, y)
        cairo_line_to(cr, x + w, y)
        cairo_stroke(cr)
        set_c(cr, dc, da)
        cairo_move_to(cr, x + w, y)
        cairo_line_to(cr, x + w, y + h)
        cairo_line_to(cr, x, y + h)
        cairo_stroke(cr)
        return
    end
    -- Light: left edge + top-left corner + top edge + top-right corner
    set_c(cr, lc, la)
    cairo_set_line_width(cr, lw)
    cairo_move_to(cr, x, y + h - r)
    cairo_line_to(cr, x, y + r)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cairo_line_to(cr, x + w - r, y)
    cairo_arc(cr, x + w - r, y + r, r, 3 * math.pi / 2, 2 * math.pi)
    cairo_stroke(cr)
    -- Dark: right edge + bottom-right corner + bottom edge + bottom-left corner
    set_c(cr, dc, da)
    cairo_move_to(cr, x + w, y + r)
    cairo_line_to(cr, x + w, y + h - r)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_line_to(cr, x + r, y + h)
    cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
    cairo_stroke(cr)
end

local function paint_plate(cr, w, h)
    local b = BEZ * S
    -- Dark translucent bezel frame filling the window (square corners)
    rrect(cr, 0, 0, w, h, 0)
    set_c(cr, { 0x14, 0x14, 0x16 }, 0.55)
    cairo_fill(cr)
    -- Metal plate inset by the bezel width (square corners)
    local pw, ph = w - 2*b, h - 2*b
    local g = cairo_pattern_create_radial(w/2, h*0.35, 0, w/2, h*0.35, math.max(w,h)*0.75)
    cairo_pattern_add_color_stop_rgb(g, 0.00, 74/255, 76/255, 79/255)
    cairo_pattern_add_color_stop_rgb(g, 0.30, 62/255, 64/255, 67/255)
    cairo_pattern_add_color_stop_rgb(g, 0.55, 52/255, 54/255, 57/255)
    cairo_pattern_add_color_stop_rgb(g, 0.80, 43/255, 45/255, 48/255)
    cairo_pattern_add_color_stop_rgb(g, 1.00, 36/255, 37/255, 40/255)
    rrect(cr, b, b, pw, ph, 0)
    cairo_set_source(cr, g)
    cairo_fill_preserve(cr)
    cairo_pattern_destroy(g)
    -- Subtle highlight overlay (bright top-left, dark bottom-right), clipped to plate
    local lg = cairo_pattern_create_linear(0, 0, w, h)
    cairo_pattern_add_color_stop_rgba(lg, 0.00, 1, 1, 1, 0.08)
    cairo_pattern_add_color_stop_rgba(lg, 0.50, 1, 1, 1, 0.01)
    cairo_pattern_add_color_stop_rgba(lg, 1.00, 0, 0, 0, 0.05)
    cairo_set_source(cr, lg)
    cairo_fill(cr)
    cairo_pattern_destroy(lg)
    -- Machined seam between bezel and plate (light top/left, dark bottom/right)
    contour_line(cr, b, b, pw, ph, 0, { 0x9c, 0x9e, 0xa1 }, 0.55, { 0x05, 0x05, 0x07 }, 0.55, 1.5 * S)
end

-- ======================== MODULE SECTION ====================
-- Nearly-flat section recessed into the plate and delimited by
-- a thin contour line around it (the mockup's 'thin line' look).
local function paint_module(cr, mx, my, mw, mh, corner_r)
    local r  = corner_r * S

    -- Very subtle drop shadow (panel still reads slightly raised)
    rrect(cr, mx + 1.5*S, my + 2*S, mw, mh, r)
    set_c(cr, { 0, 0, 0 }, 0.10)
    cairo_fill(cr)

    -- Section fill: convex dome, highlight biased up so it bulges visibly
    local ci = 2 * S
    local ir = corner_r * S
    local ix, iy, iw, ih = mx + ci, my + ci, mw - 2*ci, mh - 2*ci
    local g = cairo_pattern_create_radial(
        ix + iw/2, iy + ih*0.28, 0,
        ix + iw/2, iy + ih*0.28, math.max(iw, ih)*0.72)
    cairo_pattern_add_color_stop_rgb(g, 0.00, 58/255, 60/255, 63/255)
    cairo_pattern_add_color_stop_rgb(g, 0.50, 48/255, 50/255, 53/255)
    cairo_pattern_add_color_stop_rgb(g, 0.85, 38/255, 39/255, 42/255)
    cairo_pattern_add_color_stop_rgb(g, 1.00, 30/255, 31/255, 34/255)
    rrect(cr, ix, iy, iw, ih, ir)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)

    -- Thin contour line around the section (beveled: light top/left, dark bottom/right)
    contour_line(cr, ix, iy, iw, ih, ir, { 0xaa, 0xac, 0xaf }, 0.45, { 0x12, 0x12, 0x14 }, 0.45, 1.3 * S)
end

-- ======================== TEXT ===========================
local FSANS = 'DejaVu Sans'
local FMONO = 'DejaVu Sans Mono'

local function text_at(cr, x, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    set_c(cr, col, 1)
    cairo_select_font_face(cr, mono and FMONO or FSANS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, str)
end

local function text_cx(cr, cx, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    set_c(cr, col, 1)
    cairo_select_font_face(cr, mono and FMONO or FSANS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, str, ext)
    cairo_move_to(cr, cx - (ext.width/2 + ext.x_bearing), y)
    cairo_show_text(cr, str)
end

local function text_right(cr, right, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    set_c(cr, col, 1)
    cairo_select_font_face(cr, mono and FMONO or FSANS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, str, ext)
    cairo_move_to(cr, right - (ext.width + ext.x_bearing), y)
    cairo_show_text(cr, str)
end

-- ==================== STORAGE ARC ========================
local function storage_arc(cr, cx, cy, r, frac)
    set_c(cr, DARK, 1)
    cairo_set_line_width(cr, 14 * S)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
    cairo_arc(cr, cx, cy, r, math.pi, 2*math.pi)
    cairo_stroke(cr)
    if frac > 0 then
        set_c(cr, ARCCOL, 1)
        cairo_set_line_width(cr, 14 * S)
        cairo_arc(cr, cx, cy, r, math.pi, math.pi + frac * math.pi)
        cairo_stroke(cr)
    end
    set_c(cr, WHITE, 0.45)
    cairo_set_line_width(cr, 1.2)
    cairo_arc(cr, cx, cy, r, math.pi, 2*math.pi)
    cairo_stroke(cr)
end

-- Raised semicircular plate (plaque) that the two storage half-rings sit on.
-- Convex dome fill, thin machined bevel along the arc, drop shadow under the
-- flat bottom so it reads as raised off the module panel.
local function storage_plate(cr, cx, cy, r)
    local rad = cairo_pattern_create_radial(cx - r*0.35, cy - r*0.55, r*0.10,
                                            cx - r*0.05, cy + r*0.05, r*1.05)
    cairo_pattern_add_color_stop_rgba(rad, 0.0, 0.38, 0.39, 0.41, 1)
    cairo_pattern_add_color_stop_rgba(rad, 0.55, 0.26, 0.27, 0.29, 1)
    cairo_pattern_add_color_stop_rgba(rad, 1.0, 0.18, 0.19, 0.21, 1)
    cairo_set_source(cr, rad)
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, r, math.pi, 2*math.pi)
    cairo_close_path(cr)
    cairo_fill(cr)
    cairo_pattern_destroy(rad)

    -- thin machined bevel along the arc
    set_c(cr, { 0xb9, 0xbb, 0xbe }, 0.5)
    cairo_set_line_width(cr, 1.4 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, r - 0.7*S, math.pi, 2*math.pi)
    cairo_stroke(cr)

    -- drop shadow underneath the flat bottom (lifts the plate off the module)
    local sh = cairo_pattern_create_linear(0, cy, 0, cy + 12 * S)
    cairo_pattern_add_color_stop_rgba(sh, 0.0, 0, 0, 0, 0.32)
    cairo_pattern_add_color_stop_rgba(sh, 1.0, 0, 0, 0, 0)
    cairo_set_source(cr, sh)
    cairo_new_path(cr)
    cairo_rectangle(cr, cx - r, cy, 2*r, 12 * S)
    cairo_fill(cr)
    cairo_pattern_destroy(sh)
end

-- ==================== CPU GAUGE ==========================
-- Clock-style speedometer: concentric ring sections (like the
-- clockwidget-orig face), 60 radial ticks, and a needle that
-- sweeps clockwise from 12 o'clock as CPU load rises (270°).
local TICK_MAJOR_IN = 0.46      -- major ticks start at inner-circle edge
local TICK_MINOR_IN = 0.64      -- minor ticks start outside thin black ring
local TICK_OUT      = 1.00      -- ticks extend to the rim (1.00)

local function cpu_face(cr, cx, cy, r)
    for _, sec in ipairs(GSECTIONS) do
        set_c(cr, sec[2], 1)
        cairo_arc(cr, cx, cy, r * sec[1], 0, 2*math.pi)
        cairo_fill(cr)
    end
end

local function cpu_ticks(cr, cx, cy, r)
    for i = 0, 59 do
        local major = (i % 5 == 0)
        local a = (i * 6 - 90) * math.pi / 180
        local r_in  = r * (major and TICK_MAJOR_IN or TICK_MINOR_IN)
        set_c(cr, major and TICKMAJOR or TICKMINOR, major and 0.55 or 0.85)
        cairo_set_line_width(cr, (major and 2.4 or 1.3) * S)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_move_to(cr, cx + r_in * math.cos(a), cy + r_in * math.sin(a))
        cairo_line_to(cr, cx + r * TICK_OUT * math.cos(a), cy + r * TICK_OUT * math.sin(a))
        cairo_stroke(cr)
    end
end

local function cpu_needle(cr, cx, cy, r, load)
    -- angle: 12 o'clock at 0%, sweeping clockwise to 9 o'clock at 100%
    local a = -math.pi/2 + (load/100) * 1.5 * math.pi
    local base = r * NEEDLE_IN
    local tip  = r * NEEDLE_TIP
    local dx, dy = math.cos(a), math.sin(a)
    local px, py = -dy, dx
    local halfw = 2.0 * S                        -- constant width
    -- rectangular hand: constant-width bar from the inner-circle
    -- edge out to a flat squared tip near the rim
    set_c(cr, HANDCOL, 1)
    cairo_move_to(cr, cx + base*dx + halfw*px, cy + base*dy + halfw*py)
    cairo_line_to(cr, cx + tip*dx + halfw*px,  cy + tip*dy + halfw*py)
    cairo_line_to(cr, cx + tip*dx - halfw*px,  cy + tip*dy - halfw*py)
    cairo_line_to(cr, cx + base*dx - halfw*px, cy + base*dy - halfw*py)
    cairo_close_path(cr)
    cairo_fill(cr)
end

-- Raised-gauge 3D: the gauge SITS ABOVE the plate.  A single
-- off-centre RADIAL gradient fills a full annulus around the gauge.
local function gauge_shadow(cr, cx, cy, r)
    local t = 8 * S
    local gx, gy = cx, cy + t
    local reach = 9 * S
    local p = cairo_pattern_create_radial(gx, gy, r - t, gx, gy, r + reach)
    cairo_pattern_add_color_stop_rgba(p, 0.00, 0.02, 0.02, 0.03, 0.50)
    cairo_pattern_add_color_stop_rgba(p, 0.30, 0.02, 0.02, 0.03, 0.38)
    cairo_pattern_add_color_stop_rgba(p, 0.55, 0.02, 0.02, 0.03, 0.26)
    cairo_pattern_add_color_stop_rgba(p, 0.75, 0.02, 0.02, 0.03, 0.16)
    cairo_pattern_add_color_stop_rgba(p, 1.00, 0.02, 0.02, 0.03, 0.00)
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx, cy, r + t + reach, 0, 2 * math.pi)
    cairo_arc_negative(cr, cx, cy, r, 2 * math.pi, 0)
    cairo_close_path(cr)
    cairo_set_source(cr, p)
    cairo_fill(cr)
    cairo_pattern_destroy(p)
end

-- Machined bezel ring with light/shadow bevel (lit from ~11 o'clock).
local function gauge_bezel(cr, cx, cy, r)
    -- base bright rim
    set_c(cr, { 0x9a, 0x97, 0x93 }, 1)
    cairo_set_line_width(cr, 1.8 * S)
    cairo_arc(cr, cx, cy, r, 0, 2*math.pi)
    cairo_stroke(cr)
    -- shadow arc on the bottom-right (light from upper-left)
    local peak = 80 * math.pi / 180
    local shade = {
        { 80, 0.04, 2.6 * S },
        { 55, 0.08, 2.6 * S },
        { 34, 0.12, 2.6 * S },
        { 16, 0.17, 2.6 * S },
    }
    for _, p in ipairs(shade) do
        local hw = p[1] * math.pi / 180
        set_c(cr, { 0x16, 0x16, 0x18 }, p[2])
        cairo_set_line_width(cr, p[3])
        cairo_arc(cr, cx, cy, r, peak - hw, peak + hw)
        cairo_stroke(cr)
    end
    -- sheen on the upper-left bezel
    local sheen = {
        { math.pi + 0.10, 3*math.pi/2, 3.6 * S, 0.07 },
        { math.pi + 0.30, 3*math.pi/2, 2.6 * S, 0.11 },
        { math.pi + 0.52, 3*math.pi/2, 1.7 * S, 0.16 },
    }
    for _, p in ipairs(sheen) do
        set_c(cr, { 0xd8, 0xd5, 0xcf }, p[4])
        cairo_set_line_width(cr, p[3])
        cairo_arc(cr, cx, cy, r, p[1], p[2])
        cairo_stroke(cr)
    end
end

local function cpu_gauge(cr, cx, cy, r, label, load)
    gauge_shadow(cr, cx, cy, r)          -- drop shadow on the module panel
    cpu_face(cr, cx, cy, r)
    cpu_ticks(cr, cx, cy, r)
    cpu_needle(cr, cx, cy, r, load)
    gauge_bezel(cr, cx, cy, r)           -- bevel + shading on top of the face
    -- label centred inside the inner circle
    text_cx(cr, cx, cy + 4*S, label, WHITE, 10, false, true)
end

-- ===================== MAIN DRAW =========================
function conky_draw_bg()
    if conky_window == nil then return end
    local w = conky_window.width
    local h = conky_window.height
    S = w / DW

    local cs = cairo_xlib_surface_create(conky_window.display,
                conky_window.drawable, conky_window.visual, w, h)
    local cr = cairo_create(cs)
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

    -- Backing plate (convex dome with outer bezel lip)
    paint_plate(cr, w, h)

    -- === MODULE 1: title + raised half-circle plate with stacked ROOT/HOME rings ===
    paint_module(cr, MOD_MX*S, M1_Y*S, MOD_W*S, M1_H*S, MOD_CR)
    local ux = MOD_CX * S
    text_cx(cr, ux, 46*S, TITLE, WHITE, 20, false, true)
    -- raised half-circle plate (like a plaque) with the two half-rings on it
    storage_plate(cr, PL_CX*S, PL_CY*S, PL_R*S)
    local fr = (tonumber(conky_parse('${fs_used_perc /}')) or 0) / 100
    local fh = (tonumber(conky_parse('${fs_used_perc /home}')) or 0) / 100
    storage_arc(cr, PL_CX*S, R_CY*S, R1_R*S, fr)
    storage_arc(cr, PL_CX*S, R_CY*S, R2_R*S, fh)
    text_cx(cr, PL_CX*S, R1_TX*S, conky_parse('${fs_used_perc /}') .. '%', WHITE, 14, true, true)
    text_cx(cr, PL_CX*S, R2_TX*S, conky_parse('${fs_used_perc /home}') .. '%', WHITE, 14, true, true)

    -- === MODULE 2: CPU gauges ===
    paint_module(cr, MOD_MX*S, M2_Y*S, MOD_W*S, M2_H*S, MOD_CR)
    local gcx = CPU_CX * S
    local gr  = CPU_R  * S
    local loads = {}
    for i = 0, 3 do
        loads[i+1] = tonumber(conky_parse('${cpu cpu' .. tostring(i) .. '}')) or 0
    end
    for i = 1, 4 do
        cpu_gauge(cr, gcx, CPU_CYS[i]*S, gr,
                  'CPU ' .. tostring(i-1), loads[i])
    end

    -- === MODULE 3: processes ===
    paint_module(cr, MOD_MX*S, M3_Y*S, MOD_W*S, M3_H*S, MOD_CR)
    text_at(cr, CNT_LX*S, PRC_HDR_Y*S, 'PROCESSES', WHITE, 11, false, true)
    for i = 1, 4 do
        local nm = conky_parse('${top name ' .. tostring(i) .. '}')
        local pc = conky_parse('${top cpu ' .. tostring(i) .. '}')
        local y = PRC_ROW_Y*S + (i - 1) * PRC_ROW_DY*S
        text_at(cr, CNT_LX*S, y, nm ~= '' and nm or '-', TXT, 11, true, true)
        text_right(cr, CNT_RX*S, y, pc .. '%', WHITE, 12, true, true)
    end

    -- === MODULE 4: network ===
    paint_module(cr, MOD_MX*S, M4_Y*S, MOD_W*S, M4_H*S, MOD_CR)
    text_at(cr, CNT_LX*S, NET_HDR_Y*S, 'NETWORK', WHITE, 11, false, true)
    local essid = conky_parse('${wireless_essid ' .. WDEV .. '}')
    text_at(cr, CNT_LX*S, NET_ESSID*S, 'ESSID', GREY, 10, false, false)
    text_at(cr, 72*S, NET_ESSID*S, essid, TXT, 11, false, false)
    -- signal bar
    local bx = 72 * S
    local bw = CNT_RX * S - bx
    local by = NET_BAR * S
    text_at(cr, CNT_LX*S, by + 4*S + 2, 'SIGNAL', GREY, 10, false, false)
    local lq = tonumber(conky_parse('${wireless_link_qual_perc ' .. WDEV .. '}')) or 0
    set_c(cr, DISC, 1)
    rrect(cr, bx, by, bw, 8*S, 4*S)
    cairo_fill(cr)
    set_c(cr, GREY, 1)
    if lq > 0 then
        rrect(cr, bx, by, bw * lq / 100, 8*S, 4*S)
        cairo_fill(cr)
    end
    -- up / down / ip
    local function netline(label, value, dy)
        text_at(cr, CNT_LX*S, dy*S, label, GREY, 10, false, false)
        text_right(cr, CNT_RX*S, dy*S, value, TXT, 11, true, true)
    end
    netline('UP',   conky_parse('${totalup ' .. WDEV .. '}') .. ' / '
                  .. conky_parse('${upspeed ' .. WDEV .. '}'),  NET_UP)
    netline('DOWN', conky_parse('${totaldown ' .. WDEV .. '}') .. ' / '
                  .. conky_parse('${downspeed ' .. WDEV .. '}'), NET_DOWN)
    netline('IP',   conky_parse('${addr ' .. WDEV .. '}'), NET_IP)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
