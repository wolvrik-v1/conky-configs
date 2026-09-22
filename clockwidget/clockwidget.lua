-- ############################################################
--  Conky Clock Widget  --  Cairo/Lua renderer
--  original concept by jpope (2010); rewritten for Conky 1.12
--
--  Restored look: draws the original jpope square faces
--   * bckgnd.png      -> clock mode:  square face, round analog
--                        clock drawn into the recessed well +
--                        month/day + LED
--   * bckgnd_plain.png -> calendar mode: month grid + LED
--  The images are painted behind the Cairo drawing, so the
--  analog hands/ticks/calendar sit "in" the original hardware.
--
--  Clicking the LED toggles the mode. State is kept in the
--  'clockswitch' file (line 1: "0" clock / "1" calendar; line 2:
--  epoch timestamp of the click so re-clicks extend the timeout).
--  The calendar auto-returns to the clock after CAL_TIMEOUT s;
--  the timeout is handled here in Lua (no shell sleep).
--
--  Design coordinates live in a 175x175 grid (the image size)
--  and are scaled to whatever the conky window actually is.
-- ############################################################

require 'cairo'

-- ======================= USER OPTIONS =========================
local SWITCH_FILE = os.getenv('HOME') .. '/.conky/clockwidget/clockswitch'
local CAL_TIMEOUT = 10                    -- seconds the calendar stays visible

local IMG_DIR  = os.getenv('HOME') .. '/.conky/clockwidget/images'
local IMG_FACE = IMG_DIR .. '/bckgnd.png'          -- square clock face
local IMG_CAL  = IMG_DIR .. '/bckgnd_plain.png'    -- calendar background

-- design grid (175 = the image size; all geometry lives here and is
-- scaled by G.s to whatever size the conky window really is -- the
-- window itself is larger (see clockwidgetrc min/max size))
local DW, DH    = 175, 175
local CX, CY    = 87, 87                  -- round clock well center
local RADIUS    = 67                      -- dial face, expanded almost to the
                                          -- inner edge of the metal well wall
                                          -- (~70 grid units)
local MONTH_Y   = 62                      -- month label (inside well, top)
local DAY_Y     = 116                     -- day label (inside well, bottom)
local LED_X     = 154                     -- LED center; matches the socket
local LED_Y     = 155                     -- dot baked into bckgnd*.png
local LED_R     = 6

-- opaque backing for the faces: the source PNGs carry an alpha channel
-- (the originals were meant to sit on the old desktop background), which
-- would let the wallpaper bleed through. composite them onto a flat,
-- near-black plate once at load time so the metal face is solid.
local BACK_R, BACK_G, BACK_B = 0.02, 0.03, 0.04

-- colors (R, G, B as 0-255 hex values) -- chosen to read on the
-- gray metal plate backgrounds
local TICKMAJOR = { 0xe8, 0xec, 0xef }
local TICKMINOR = { 0x9a, 0xa4, 0xac }
local HOURCOL   = { 0xff, 0xff, 0xff }
local MINCOL    = { 0xc8, 0xd0, 0xd6 }
local SECCOL    = { 0xff, 0x3b, 0x30 }     -- red second hand
local DATECOL   = { 0xe8, 0xec, 0xef }
local SUBTXT    = { 0x9a, 0xa4, 0xac }
local CALHDR    = { 0xf2, 0xf5, 0xf7 }
local CALTXT    = { 0xf2, 0xf5, 0xf7 }
local LEDOFF    = { 0x4a, 0x52, 0x5c }
local LEDON     = { 0x3a, 0x8f, 0xd6 }
local LEDRING   = { 0x9a, 0xa4, 0xac }
-- ==============================================================

local G = { s = 1 }      -- runtime geometry (set each frame)
local cal_start          -- os.time() when the calendar became visible

-- background images (nil if a file could not be loaded); the loaded
-- PNGs are flattened onto an opaque plate so the desktop never shows
-- through the metal faces
local img_face, img_cal
local function flatten_opaque(surf, r, g, b)
    local w = cairo_image_surface_get_width(surf)
    local h = cairo_image_surface_get_height(surf)
    local plate = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h)
    local cr = cairo_create(plate)
    -- opaque backing, cut to the PNG's own alpha silhouette (rounded
    -- corners / soft rim) so the plate stays contoured instead of a
    -- hard square filling the window edge-to-edge
    cairo_set_source_rgb(cr, r, g, b)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_DEST_IN)
    cairo_set_source_surface(cr, surf, 0, 0)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
    cairo_set_source_surface(cr, surf, 0, 0)
    cairo_paint(cr)
    cairo_destroy(cr)
    cairo_surface_destroy(surf)
    return plate
end

local function load_images()
    local ok1, s1 = pcall(cairo_image_surface_create_from_png, IMG_FACE)
    local ok2, s2 = pcall(cairo_image_surface_create_from_png, IMG_CAL)
    if ok1 and s1 then img_face = flatten_opaque(s1, BACK_R, BACK_G, BACK_B) end
    if ok2 and s2 then img_cal  = flatten_opaque(s2, BACK_R, BACK_G, BACK_B) end
end

local function set_c(cr, c, a)
    cairo_set_source_rgba(cr, c[1] / 255, c[2] / 255, c[3] / 255, a or 1)
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

-- fallback plain face (used only if bckgnd.png is missing)
local function draw_face(cr)
    set_c(cr, { 0x2a, 0x2f, 0x36 }, 1)
    cairo_arc(cr, G.cx, G.cy, G.r, 0, 2 * math.pi)
    cairo_fill(cr)
    set_c(cr, { 0x4a, 0x52, 0x5c }, 1)
    cairo_set_line_width(cr, 3 * G.s)
    cairo_arc(cr, G.cx, G.cy, G.r, 0, 2 * math.pi)
    cairo_stroke(cr)
end

local function paint_bg(cr, img)
    if not img then return end
    -- scale the (175x175) face image up to the actual conky window so
    -- the square metal plate fills the whole widget
    local iw = cairo_image_surface_get_width(img)
    local ih = cairo_image_surface_get_height(img)
    local pat = cairo_pattern_create_for_surface(img)
    local mtx = cairo_matrix_t:create()
    -- pattern space = user space * mtx, so a ratio < 1 stretches the
    -- (175x175) plate up to cover the full (larger) conky window
    cairo_matrix_init_scale(mtx, iw / conky_window.width, ih / conky_window.height)
    cairo_pattern_set_matrix(pat, mtx)
    cairo_set_source(cr, pat)
    cairo_paint(cr)
    cairo_pattern_destroy(pat)
end

local function draw_ticks(cr)
    local cx, cy, r, s = G.cx, G.cy, G.r, G.s
    for i = 0, 59 do
        local major = (i % 5 == 0)
        local a = (i * 6 - 90) * math.pi / 180
        local r1 = r - (major and 7 or 3.5) * s
        local r2 = r - 1.5 * s
        set_c(cr, major and TICKMAJOR or TICKMINOR, major and 1 or 0.6)
        cairo_set_line_width(cr, (major and 2 or 1) * s)
        cairo_move_to(cr, cx + r1 * math.cos(a), cy + r1 * math.sin(a))
        cairo_line_to(cr, cx + r2 * math.cos(a), cy + r2 * math.sin(a))
        cairo_stroke(cr)
    end
end

local function draw_hand(cr, angle, length, width, col)
    local a = (angle - 90) * math.pi / 180
    set_c(cr, col, 1)
    cairo_set_line_width(cr, width * G.s)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_move_to(cr, G.cx, G.cy)
    cairo_line_to(cr, G.cx + length * G.s * math.cos(a), G.cy + length * G.s * math.sin(a))
    cairo_stroke(cr)
end

local function draw_second_hand(cr, angle)
    -- long thin red hand with a short counterweight behind the hub
    local a = (angle - 90) * math.pi / 180
    local ln, tail, w = RADIUS * 0.88, RADIUS * 0.14, 1.1
    set_c(cr, SECCOL, 1)
    cairo_set_line_width(cr, w * G.s)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_move_to(cr, G.cx - tail * G.s * math.cos(a), G.cy - tail * G.s * math.sin(a))
    cairo_line_to(cr, G.cx + ln * G.s * math.cos(a), G.cy + ln * G.s * math.sin(a))
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
    paint_bg(cr, img_face)
    if not img_face then draw_face(cr) end
    draw_ticks(cr)

    local t = os.date('*t')
    local hr = (t.hour % 12) + t.min / 60
    local mn = t.min + t.sec / 60
    local sc = t.sec
    draw_hand(cr, hr * 30, RADIUS * 0.52, 4.0, HOURCOL)
    draw_hand(cr, mn * 6, RADIUS * 0.72, 2.5, MINCOL)
    draw_second_hand(cr, sc * 6)

    set_c(cr, { 0xff, 0xff, 0xff }, 0.9)
    cairo_arc(cr, G.cx, G.cy, 2.8 * G.s, 0, 2 * math.pi)
    cairo_fill(cr)

    -- date strip: month (top) / day (bottom) inside the clock well
    centered_text(cr, G.cx, MONTH_Y, string.upper(os.date('%B %Y')), SUBTXT, 9)
    centered_text(cr, G.cx, DAY_Y, os.date('%d'), DATECOL, 18)
    drawLED(cr, on)
end

local function draw_calendar(cr, on)
    paint_bg(cr, img_cal)
    if not img_cal then set_c(cr, { 0x1a, 0x1d, 0x22 }, 1); cairo_paint(cr) end

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

    -- debug: write once on first meaningful frame
    if not _dbg_done then
        _dbg_done = true
        local df = io.open('/tmp/conky_debug.txt', 'w')
        if df then
            df:write(string.format('cw.width=%s cw.height=%s\n', tostring(conky_window.width), tostring(conky_window.height)))
            df:write(string.format('G.s=%s img_face=%s img_cal=%s\n', tostring(G.s), tostring(img_face ~= nil), tostring(img_cal ~= nil)))
            df:close()
        end
    end

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

-- load the face plates once at startup
load_images()

-- ============================================================
-- Keep the LED button alive alongside conky (works with any
-- launcher: clockwidget, conky-manager, etc.). Guarded so a
-- button already running is never duplicated. The path is
-- reassembled inside the shell command so pgrep can never
-- match the spawning shell's own command line.
-- ============================================================
local function spawn_button()
    local sh = "HB='" .. os.getenv('HOME') .. "'; A=clockwidget-b; B=tn; if ! pgrep -f 'clockwidget/clockwidget-b[t]n' >/dev/null 2>&1; then setsid python3 \"$HB/.conky/clockwidget/$A$B\" </dev/null >>\"$HB/.conky/clockwidget/$A$B.log\" 2>&1 & fi"
    os.execute(sh)
end

spawn_button()
