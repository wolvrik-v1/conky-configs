-- ############################################################
--  Conky Clock Widget  --  ORIGINAL-jpope-face edition
--  Separate version for Conky 1.12 (Lua/Cairo), replicating the
--  original jpope clock face from the reference screenshot:
--    * 12 long major hash marks at the hour positions + 48 minor
--      ticks, both starting just OUTSIDE the central inner circle
--    * a larger inner circle (0.46*R) that holds the digital readout:
--      date (top) / time (middle) / day (bottom), stacked in order
--    * the hands EMANATE from the outer edge of that inner circle
--      (their base), sweeping towards the rim - never reaching into
--      the centre, so the date/time/day stays clean
--    * all face markings (ticks, minor lines) much dimmer than the
--      bright hands (measured in the reference: marks ~98-155 luma)
--    * white hour hand, grey minute hand, thin RED second hand
--    * blue LED bottom-right
--
--  The plate is fully procedural (family-style flat square plate,
--  same as the MetalSysMonitor / metal-pianobar siblings): dark
--  translucent bezel to the window corners + matte metal face with a
--  subtle grey contour line. No PNG assets are required; the old
--  bckgnd*.png images are kept only as design reference.
--
--  LED click toggles via 'clockswitch' (line1 "0"/"1", line2
--  epoch); calendar auto-returns to clock after CAL_TIMEOUT s.
-- ############################################################

require 'cairo'

-- ======================= USER OPTIONS =========================
local SWITCH_FILE = os.getenv('HOME') .. '/.conky/clockwidget-orig/clockswitch'
local CAL_TIMEOUT = 10                    -- seconds the calendar stays visible

-- design grid (175 = the plate size; all geometry lives here and is
-- scaled by G.s to whatever size the conky window really is)
local DW, DH    = 175, 175
local CX, CY    = 87, 87                  -- round clock well center
local RADIUS    = 74                      -- dial face = plate PNG's real inner
                                         -- wall radius (measured ~74/175 grid;
                                         -- 67 left a visible dark gap before
                                         -- the metal bezel)
-- central circle that holds the date/time/day text; the hands EMANATE
-- from its outer edge (their base) so they never reach into the centre
local IN_R      = 0.46                    -- inner circle radius as fraction of RADIUS
local DATE_Y    = 74                      -- date label (top line, inside inner circle)
local TIME_Y    = 90                      -- time label (middle line)
local DAY_Y     = 103                     -- day label (bottom line)
local LED_X     = 154                     -- LED center; matches the button overlay
local LED_Y     = 155                     -- (btnclockwdgt-orig, grid 175)
local LED_R     = 6

-- colors (R, G, B as 0-255 hex values)
-- original look: hash marks on the dark well. all face markings are
-- deliberately MUCH DIMER than the hands (measured from the reference
-- screenshot: marks luma ~98-155 vs hands near-white/red)
local TICKMAJOR = { 0x9e, 0xa6, 0xb0 }    -- 12 long light-grey hour hash marks
local TICKMINOR = { 0x6e, 0x77, 0x81 }    -- short minute ticks
local HOURCOL   = { 0xcf, 0xd6, 0xdc }    -- hour hand = SAME grey as minute
local MINCOL    = { 0xcf, 0xd6, 0xdc }    -- grey-white minute hand
local SECCOL    = { 0xff, 0x3b, 0x30 }    -- red second hand
local DATECOL   = { 0xe8, 0xec, 0xef }
local SUBTXT    = { 0xa6, 0xaf, 0xb8 }
local CALHDR    = { 0xf2, 0xf5, 0xf7 }
local CALTXT    = { 0xf2, 0xf5, 0xf7 }
local TIMECOL   = { 0xf2, 0xf5, 0xf7 }
local LEDOFF    = { 0x4a, 0x52, 0x5c }
local LEDON     = { 0x3a, 0x8f, 0xd6 }
local LEDRING   = { 0x9a, 0xa4, 0xac }

-- concentric circular sections on the dial face (measured from the
-- original screenshot): each ring is a band out to the given fraction
-- of the dial radius; painted largest -> smallest so the last listed
-- colour wins in the centre. r_outer=1 covers the whole dial radius.
local SECTIONS = {
    { 1.00, { 0x14, 0x14, 0x16 } },   -- restored black (outer) ring next to the
                                     -- metal bezel (was luma 16-20 in plate PNG)
    { 0.91, { 0x2e, 0x2e, 0x2e } },   -- dark outer ring (46)
    { 0.76, { 0x52, 0x52, 0x52 } },   -- dark-mid transition (82)
    { 0.69, { 0x56, 0x56, 0x55 } },   -- mid ring (86)
    { 0.64, { 0x14, 0x14, 0x16 } },   -- thin black ring at minor tick start (~0.62)
    { 0.60, { 0x6c, 0x6b, 0x6a } },   -- lighter inner ring (107, lightened so it
                                     -- reads lighter than the 0.69 mid ring)
    { 0.46, { 0x43, 0x43, 0x43 } },   -- darker centre (67) = the inner circle
}                                       -- that holds the date/time/day text
-- ==============================================================

local G = { s = 1 }      -- runtime geometry (set each frame)
local cal_start          -- os.time() when the calendar became visible

local function set_c(cr, c, a)
    cairo_set_source_rgba(cr, c[1] / 255, c[2] / 255, c[3] / 255, a or 1)
end

local function rrect(cr, x, y, w, h, r)
    if r > w / 2 then r = w / 2 end
    if r > h / 2 then r = h / 2 end
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r,     r, -math.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0,          math.pi / 2)
    cairo_arc(cr, x + r,     y + h - r, r, math.pi / 2, math.pi)
    cairo_arc(cr, x + r,     y + r,     r, math.pi,    3 * math.pi / 2)
    cairo_close_path(cr)
end

local function contour_line(cr, x, y, w, h, r, lc, la, dc, da, lw)
    if r < 0.5 then
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
    set_c(cr, lc, la)
    cairo_set_line_width(cr, lw)
    cairo_move_to(cr, x, y + h - r)
    cairo_line_to(cr, x, y + r)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cairo_line_to(cr, x + w - r, y)
    cairo_arc(cr, x + w - r, y + r, r, 3 * math.pi / 2, 2 * math.pi)
    cairo_stroke(cr)
    set_c(cr, dc, da)
    cairo_move_to(cr, x + w, y + r)
    cairo_line_to(cr, x + w, y + h - r)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_line_to(cr, x + r, y + h)
    cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
    cairo_stroke(cr)
end

local function write_state(s)
    local ok, f = pcall(io.open, SWITCH_FILE, 'w')
    if ok and f then
        f:write(s, '\n')
        f:close()
    end
end

local function read_state()
    local f = io.open(SWITCH_FILE, 'r')
    if not f then return '0', nil end
    local state, stamp = '0', nil
    local l1 = f:read('*l')
    if l1 and l1:match('^%s*1') then state = '1'; stamp = tonumber(f:read('*l')) end
    f:close()
    return state, stamp
end

-- family-style flat plate, exactly like MetalSysMonitor /
-- metal-pianobar: a dark translucent bezel fills the ENTIRE window
-- (so the shading reaches the widget corners inside the outer grey
-- line), then a flat matte metal plate sits inset with SQUARE corners
-- (family plates are square, MOD_CR=0) and a subtle grey contour line
-- outlines the outside edge. No rounded corners, no metal shine.
local BEZ = 8     -- bezel width, grid units (window px = BEZ*G.s)

local function paint_bg(cr)
    local w, h = conky_window.width, conky_window.height
    local b   = BEZ * G.s
    local pw, ph = w - 2*b, h - 2*b

    -- 1) dark translucent bezel across the ENTIRE window: the dark
    --    shading reaches all the way into the corners (family paint_plate)
    rrect(cr, 0, 0, w, h, 0)
    set_c(cr, { 0x14, 0x14, 0x16 }, 0.55)
    cairo_fill(cr)

    -- 2) flat matte metal plate, inset, square corners (no rounding)
    local g = cairo_pattern_create_radial(w/2, h*0.35, 0, w/2, h*0.35, math.max(w, h)*0.75)
    cairo_pattern_add_color_stop_rgb(g, 0.00, 74/255, 76/255, 79/255)
    cairo_pattern_add_color_stop_rgb(g, 0.30, 62/255, 64/255, 67/255)
    cairo_pattern_add_color_stop_rgb(g, 0.55, 52/255, 54/255, 57/255)
    cairo_pattern_add_color_stop_rgb(g, 0.80, 43/255, 45/255, 48/255)
    cairo_pattern_add_color_stop_rgb(g, 1.00, 36/255, 37/255, 40/255)
    rrect(cr, b, b, pw, ph, 0)
    cairo_set_source(cr, g)
    cairo_fill_preserve(cr)
    cairo_pattern_destroy(g)
    -- subtle linear sheen (light top-left -> dim black bottom-right)
    local lg = cairo_pattern_create_linear(0, 0, w, h)
    cairo_pattern_add_color_stop_rgba(lg, 0.00, 1, 1, 1, 0.08)
    cairo_pattern_add_color_stop_rgba(lg, 0.50, 1, 1, 1, 0.01)
    cairo_pattern_add_color_stop_rgba(lg, 1.00, 0, 0, 0, 0.05)
    cairo_set_source(cr, lg)
    cairo_fill(cr)
    cairo_pattern_destroy(lg)

    -- 3) subtle grey line around the outside (square corners, family)
    contour_line(cr, b, b, pw, ph, 0,
                 { 0x9c, 0x9e, 0xa1 }, 0.55,
                 { 0x05, 0x05, 0x07 }, 0.55, 1.5 * G.s)
end

-- ############################################################
--  Silver dial bezel (the family's gauge_bezel from
--  MetalSysMonitor): a bright metal rim around the clock dial
--  with a soft shadow on the bottom-right and a sheen along the
--  upper-left (light source = upper-left). Drawn ON TOP of the
--  face + ticks, exactly like the sibling gauges.
-- ############################################################
local function dial_bezel(cr)
    local r = G.r
    -- base bright silver rim
    set_c(cr, { 0x9a, 0x97, 0x93 }, 1)
    cairo_set_line_width(cr, 1.8 * G.s)
    cairo_arc(cr, G.cx, G.cy, r, 0, 2 * math.pi)
    cairo_stroke(cr)
    -- shadow arc on the bottom-right (light from upper-left)
    local peak = 80 * math.pi / 180
    local shade = {
        { 80, 0.04 },
        { 55, 0.08 },
        { 34, 0.12 },
        { 16, 0.17 },
    }
    for _, p in ipairs(shade) do
        local hw = p[1] * math.pi / 180
        set_c(cr, { 0x16, 0x16, 0x18 }, p[2])
        cairo_set_line_width(cr, 2.6 * G.s)
        cairo_arc(cr, G.cx, G.cy, r, peak - hw, peak + hw)
        cairo_stroke(cr)
    end
    -- sheen on the upper-left bezel
    local sheen = {
        { math.pi + 0.10, 3*math.pi/2, 3.6 * G.s, 0.07 },
        { math.pi + 0.30, 3*math.pi/2, 2.6 * G.s, 0.11 },
        { math.pi + 0.52, 3*math.pi/2, 1.7 * G.s, 0.16 },
    }
    for _, p in ipairs(sheen) do
        set_c(cr, { 0xd8, 0xd5, 0xcf }, p[4])
        cairo_set_line_width(cr, p[3])
        cairo_arc(cr, G.cx, G.cy, r, p[1], p[2])
        cairo_stroke(cr)
    end
end

-- ############################################################
--  Original concentric dial-face sections: the well is not flat
--  grey, it steps through several concentric rings in slightly
--  lighter/darker shades of grey (see SECTIONS above).
-- ############################################################
local function draw_sections(cr)
    local r = G.r
    for _, sec in ipairs(SECTIONS) do
        set_c(cr, sec[2], 1)
        cairo_arc(cr, G.cx, G.cy, r * sec[1], 0, 2 * math.pi)
        cairo_fill(cr)
    end
end

-- ############################################################
--  Original hash-mark ticks:
--    12 long major ticks at the hour positions + 4 shorter minor
--    ticks between. Both start just OUTSIDE the inner circle that
--    holds the date/time/day text and end near the rim.
--  Lengths stated as fractions of the dial radius RADIUS.
-- ############################################################
local TICK_MAJOR_IN = 0.46      -- longest ticks start AT the outer edge of the
                                -- innermost circle (= IN_R, "touch" it)
local TICK_MINOR_IN = 0.64      -- minor tick starts OUTSIDE the thin black
                                -- ring (at its outer edge, 0.64*R)
local TICK_OUT      = 1.00      -- both extend all the way to the edge of
                                -- the metal case (inner well wall)

local function draw_ticks(cr)
    local cx, cy, r, s = G.cx, G.cy, G.r, G.s
    for i = 0, 59 do
        local major = (i % 5 == 0)
        local a = (i * 6 - 90) * math.pi / 180
        local r_in  = r * (major and TICK_MAJOR_IN or TICK_MINOR_IN)
        local r_out = r * TICK_OUT
        set_c(cr, major and TICKMAJOR or TICKMINOR, major and 0.55 or 0.85)
        cairo_set_line_width(cr, (major and 2.4 or 1.3) * s)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_move_to(cr, cx + r_in * math.cos(a), cy + r_in * math.sin(a))
        cairo_line_to(cr, cx + r_out * math.cos(a), cy + r_out * math.sin(a))
        cairo_stroke(cr)
    end
end

local function draw_hour_hand(cr, angle)
    -- RECTANGULAR hour hand: constant-width rectangle from the inner
    -- circle edge out to a flat tip near the rim. dimmer grey than the
    -- minute hand (user: "the hour hand should be rectangular").
    local a = (angle - 90) * math.pi / 180
    local cx, cy, s = G.cx, G.cy, G.s
    local base = G.r * IN_R
    local tip  = base + RADIUS * 0.40 * s        -- tip ~0.86*R
    local halfw = 2.0 * s                        -- half width (constant)
    local dx, dy = math.cos(a), math.sin(a)
    local px, py = -dy, dx                       -- perpendicular
    set_c(cr, HOURCOL, 1)
    cairo_move_to(cr, cx + base * dx + halfw * px, cy + base * dy + halfw * py)
    cairo_line_to(cr, cx + tip * dx + halfw * px, cy + tip * dy + halfw * py)
    cairo_line_to(cr, cx + tip * dx - halfw * px, cy + tip * dy - halfw * py)
    cairo_line_to(cr, cx + base * dx - halfw * px, cy + base * dy - halfw * py)
    cairo_close_path(cr)
    cairo_fill(cr)
end

local function draw_hand(cr, angle, length, width, col)
    -- hands EMANATE from the outer edge of the inner circle (the ring
    -- that holds the date/time/day text) and sweep towards the rim;
    -- they never reach into the centre, keeping the text clear.
    local a = (angle - 90) * math.pi / 180
    local base = G.r * IN_R
    set_c(cr, col, 1)
    cairo_set_line_width(cr, width * G.s)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_move_to(cr, G.cx + base * math.cos(a), G.cy + base * math.sin(a))
    cairo_line_to(cr, G.cx + (base + length * G.s) * math.cos(a), G.cy + (base + length * G.s) * math.sin(a))
    cairo_stroke(cr)
end

local function draw_second_hand(cr, angle)
    -- thin red second hand from the inner-circle edge out to the rim
    local a = (angle - 90) * math.pi / 180
    local base = G.r * IN_R
    local ln, w = RADIUS * 0.52, 1.1
    set_c(cr, SECCOL, 1)
    cairo_set_line_width(cr, w * G.s)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_move_to(cr, G.cx + base * math.cos(a), G.cy + base * math.sin(a))
    cairo_line_to(cr, G.cx + (base + ln * G.s) * math.cos(a), G.cy + (base + ln * G.s) * math.sin(a))
    cairo_stroke(cr)
end

local function drawLED(cr, on)
    local x, y = G.ledx, G.ledy
    local r = LED_R * G.s
    -- dark socket fill so the LED reads on any background
    set_c(cr, { 0x08, 0x09, 0x0a }, 0.9)
    cairo_arc(cr, x, y, r + 1.5 * G.s, 0, 2 * math.pi)
    cairo_fill(cr)
    set_c(cr, LEDRING, 1)
    cairo_set_line_width(cr, 1.5 * G.s)
    cairo_arc(cr, x, y, r + 1.5 * G.s, 0, 2 * math.pi)
    cairo_stroke(cr)
    set_c(cr, on and LEDON or LEDOFF, 1)
    cairo_arc(cr, x, y, r, 0, 2 * math.pi)
    cairo_fill(cr)
    set_c(cr, { 0xff, 0xff, 0xff }, 0.35)
    cairo_arc(cr, x - r * 0.3, y - r * 0.3, r * 0.4, 0, 2 * math.pi)
    cairo_fill(cr)
end

local function centered_text(cr, cx, y, text, col, size)
    set_c(cr, col, 1)
    cairo_select_font_face(cr, 'DejaVu Sans', CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * G.s)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, text, ext)
    cairo_move_to(cr, cx - (ext.width / 2 + ext.x_bearing), y * G.s)
    cairo_show_text(cr, text)
end

local function draw_clock(cr, on)
    paint_bg(cr)
    draw_sections(cr)
    draw_ticks(cr)
    dial_bezel(cr)

    local t = os.date('*t')
    local hr = (t.hour % 12) + t.min / 60
    local mn = t.min + t.sec / 60
    local sc = t.sec
    -- hands EMANATE from the inner circle edge; tips sweep the rim zone.
    -- base = IN_R*R, so "length" is the extra reach beyond the base.
    draw_hour_hand(cr, hr * 30)                                       -- tapered pointed grey hour hand
    draw_hand(cr, mn * 6,  RADIUS * 0.50, 2.4, MINCOL)    -- minute tip ~0.96*R
    draw_second_hand(cr, sc * 6)                          -- tip ~0.97*R

    -- date/time/day stacked inside the inner circle (no hub, no hands
    -- reaching in here, so the centre stays clean)
    centered_text(cr, G.cx, DATE_Y, os.date('%d'), DATECOL, 10)
    centered_text(cr, G.cx, TIME_Y, os.date('%H:%M'), TIMECOL, 14)
    centered_text(cr, G.cx, DAY_Y, os.date('%A'), SUBTXT, 8)
    drawLED(cr, on)
end

local function draw_calendar(cr, on)
    paint_bg(cr)

    local w = DW * G.s
    local cellw = w / 7

    centered_text(cr, G.cx, 34, string.upper(os.date('%B %Y')), CALHDR, 16)

    local names = { 'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa' }
    for c = 1, 7 do
        centered_text(cr, (c - 0.5) * cellw, 54, names[c], SUBTXT, 9)
    end

    local now  = os.date('*t')
    local fwd  = os.date('*t', os.time{ year = now.year, month = now.month, day = 1 }).wday - 1
    local dim  = os.date('*t', os.time{ year = now.year, month = now.month + 1, day = 0 }).day
    local top  = 68 * G.s
    local rowh = 14 * G.s
    for d = 1, dim do
        local idx = fwd + d - 1
        local row = math.floor(idx / 7)
        local col = idx % 7
        local x   = (col + 0.5) * cellw
        local y   = top + row * rowh
        centered_text(cr, x, 68 + row * 14, tostring(d), CALTXT, 11)
    end
    drawLED(cr, on)
end

function conky_main()
    if conky_window == nil then return end

    local updates = tonumber(conky_parse('${updates}')) or 0
    if updates <= 2 then return end

    local state, stamp = read_state()
    local now = os.time()

    if state == '1' then
        if not cal_start then cal_start = now end
        if stamp and stamp > cal_start then cal_start = stamp end
    else
        cal_start = nil
    end

    -- build cairo context on the conky drawable (transparent background)
    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

    -- geometry scaled to the actual window size
    G.s    = math.min(conky_window.width / DW, conky_window.height / DH)
    G.cx   = CX * G.s
    G.cy   = CY * G.s
    G.r    = RADIUS * G.s
    G.ledx = LED_X * G.s
    G.ledy = LED_Y * G.s

    if state == '1' then
        draw_calendar(cr, true)
        if os.time() - cal_start >= CAL_TIMEOUT then
            write_state('0')
            cal_start = nil
        end
    else
        draw_clock(cr, false)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- ============================================================
-- Keep the LED button alive alongside conky (works with any
-- launcher: conkyclock-orig, conky-manager, etc.). Guarded so a
-- button already running is never duplicated. The path is
-- reassembled inside the shell command so pgrep can never
-- match the spawning shell's own command line.
-- ============================================================
local function spawn_button()
    local sh = "HB='" .. os.getenv('HOME') .. "'; A=btncl; B=ockwdgt-orig; if ! pgrep -f 'clockwidget-orig/btncl[o]ckwdgt-orig' >/dev/null 2>&1; then setsid python3 \"$HB/.conky/clockwidget-orig/$A$B\" </dev/null >>\"$HB/.conky/clockwidget-orig/$A$B.log\" 2>&1 & fi"
    os.execute(sh)
end

spawn_button()