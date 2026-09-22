-- ############################################################
--  metal-pianobar -- Cairo/Lua renderer (metal-sysmon style)
--  HORIZONTAL CONSOLE: header strip + record dial (cover art with
--  a machined progress ring) on the left, metadata plinth on the right.
--  Reads from the shared pianobar now-playing cache.
--  All paths use $HOME / XDG env vars -- no hardcoded usernames.
-- ############################################################

require 'cairo'

-- ======================= PATHS (user-agnostic) ===============
local HOME        = os.getenv('HOME') or os.getenv('USERPROFILE') or ''
local XDG_CACHE   = os.getenv('XDG_CACHE_HOME') or (HOME .. '/.cache')
local XDG_CONFIG  = os.getenv('XDG_CONFIG_HOME') or (HOME .. '/.config')

local CACHE_PATH  = XDG_CACHE .. '/conky/pianobar-widget.status'
local COVER_JPG   = XDG_CONFIG .. '/pianobar/coverArt.jpg'
local COVER_PNG   = XDG_CACHE .. '/conky/metal_pianobar_cover.png'
local COVER_MARKER = COVER_PNG .. '.mtime'

-- ======================= DESIGN GRID =========================
local GRID_W = 640                          -- horizontal console
local GRID_H = 340

-- OUTER BEZEL + MODULE LAYOUT
local BEZ    = 10
local MOD_MX = BEZ + 10                     -- = 20
local MOD_W  = GRID_W - 2 * MOD_MX          -- = 600
local MOD_CR = 0

-- Header strip (full width)
local HDR_Y, HDR_H = 14, 60

-- Left module: record dial (cover art + needle gauge)
local DIAL_X, DIAL_Y, DIAL_W, DIAL_H = 20, 84, 300, 240
local DIAL_CX, DIAL_CY = 168, 204           -- dial centre (seated in module)
local DIAL_R          = 104                 -- dial outer radius (expanded ring)
local ART_R           = DIAL_R * 0.53          -- cover art sits just below the 0.60 grey ring, so the
                                               -- family ring sequence (grey->black->grey->grey->dark->rim)
                                               -- stays visible around it in a slim but clear band
-- Major ticks reach from the album-art edge (the gauge's "inner circle",
-- mirroring the family's 0.46->1.00) out to the rim.
local TICK_MI_FR, TICK_MO_FR = ART_R/DIAL_R, 0.990
local TICK_NI_FR, TICK_NO_FR = 0.770, 0.975 -- minor ticks stay shorter

-- Right module: metadata
local META_X, META_Y, META_W, META_H = 330, 84, 290, 240

-- Content margins
local CNT_LX    = MOD_MX + 14               -- = 34
local CNT_RX    = MOD_MX + MOD_W - 12       -- = 588

-- Metadata text layout
local MTX          = META_X + 16            -- = 346
local META_CW      = CNT_RX - MTX           -- text width to the right margin

-- ======================= PALETTE =============================
-- metal-sysmon family palette: cool black-metal greys only.
local WHITE  = { 0xf2, 0xf5, 0xf7 }
local TXT    = { 0xe8, 0xec, 0xef }
local GREY   = { 0x9a, 0xa4, 0xac }
local DARK   = { 0x2a, 0x2d, 0x31 }
local DISC   = { 0x14, 0x14, 0x16 }
local ARCCOL = { 0xbb, 0xbb, 0xbb }         -- bright metal accent (ring fill)
local HANDCOL = { 0xcf, 0xd6, 0xdc }        -- bright grey-white (needle / playing)

local TICKMAJOR = { 0x9e, 0xa6, 0xb0 }
local TICKMINOR = { 0x6e, 0x77, 0x81 }

-- The family gauge face: 7 concentric ring sections (largest -> smallest).
local GSECTIONS = {
    { 1.00, { 0x14, 0x14, 0x16 } },
    { 0.91, { 0x2e, 0x2e, 0x2e } },
    { 0.76, { 0x52, 0x52, 0x52 } },
    { 0.69, { 0x56, 0x56, 0x55 } },
    { 0.64, { 0x14, 0x14, 0x16 } },
    { 0.60, { 0x6c, 0x6b, 0x6a } },
    { 0.46, { 0x43, 0x43, 0x43 } },
}

local FSANS = 'DejaVu Sans'
local FMONO = 'DejaVu Sans Mono'

local S = 1

-- ======================= HELPERS =============================
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

-- ======================= BACKING PLATE =======================
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

local function paint_plate(cr, w, h)
    local b = BEZ * S
    rrect(cr, 0, 0, w, h, 0)
    set_c(cr, { 0x14, 0x14, 0x16 }, 0.55)
    cairo_fill(cr)
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
    local lg = cairo_pattern_create_linear(0, 0, w, h)
    cairo_pattern_add_color_stop_rgba(lg, 0.00, 1, 1, 1, 0.08)
    cairo_pattern_add_color_stop_rgba(lg, 0.50, 1, 1, 1, 0.01)
    cairo_pattern_add_color_stop_rgba(lg, 1.00, 0, 0, 0, 0.05)
    cairo_set_source(cr, lg)
    cairo_fill(cr)
    cairo_pattern_destroy(lg)
    contour_line(cr, b, b, pw, ph, 0, { 0x9c, 0x9e, 0xa1 }, 0.55, { 0x05, 0x05, 0x07 }, 0.55, 1.5 * S)
end

-- ======================= MODULE SECTION ======================
local function paint_module(cr, mx, my, mw, mh, corner_r)
    local r  = corner_r * S
    rrect(cr, mx + 1.5*S, my + 2*S, mw, mh, r)
    set_c(cr, { 0, 0, 0 }, 0.10)
    cairo_fill(cr)
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
    contour_line(cr, ix, iy, iw, ih, ir, { 0xaa, 0xac, 0xaf }, 0.45, { 0x12, 0x12, 0x14 }, 0.45, 1.3 * S)
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
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, str, ext)
    cairo_move_to(cr, (right - (ext.width + ext.x_bearing)) * S, y * S)
    cairo_show_text(cr, str)
end

local function draw_dot(cr, cx, cy, radius, color)
    set_c(cr, color)
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
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, text, ext)
    if ext.width <= max_w * S then return text end
    local chars = {}
    for _, c in utf8.codes(text) do chars[#chars+1] = utf8.char(c) end
    local lo, hi = 0, #chars
    while lo < hi do
        local mid = math.floor((lo + hi + 1)/2)
        local cand = table.concat(chars, '', 1, mid) .. '…'
        cairo_text_extents(cr, cand, ext)
        if ext.width <= max_w * S then lo = mid else hi = mid - 1 end
    end
    local res = table.concat(chars, '', 1, lo)
    if lo < #chars then res = res .. '…' end
    return res
end

-- ==================== DROP SHADOW (annulus) ==================
local function dial_shadow(cr, cx, cy, r)
    local t = 6 * S
    local gx, gy = cx * S, cy * S + t
    local reach = 7 * S
    local p = cairo_pattern_create_radial(gx, gy, r*S - t, gx, gy, r*S + reach)
    cairo_pattern_add_color_stop_rgba(p, 0.00, 0.02, 0.02, 0.03, 0.50)
    cairo_pattern_add_color_stop_rgba(p, 0.30, 0.02, 0.02, 0.03, 0.38)
    cairo_pattern_add_color_stop_rgba(p, 0.55, 0.02, 0.02, 0.03, 0.26)
    cairo_pattern_add_color_stop_rgba(p, 0.75, 0.02, 0.02, 0.03, 0.16)
    cairo_pattern_add_color_stop_rgba(p, 1.00, 0.02, 0.02, 0.03, 0.00)
    cairo_new_sub_path(cr)
    cairo_arc(cr, cx*S, cy*S, r*S + t + reach, 0, 2 * math.pi)
    cairo_arc_negative(cr, cx*S, cy*S, r*S, 2 * math.pi, 0)
    cairo_close_path(cr)
    cairo_set_source(cr, p)
    cairo_fill(cr)
    cairo_pattern_destroy(p)
end

-- ==================== RECORD DIAL ============================
-- The record dial's recessed face is the SAME 7-concentric-ring
-- gauge face used by the metal-sysmon CPU gauges (GSECTIONS),
-- with the album art floating on the dark centre circle.
local function dial_well(cr, cx, cy, r)
    for _, sec in ipairs(GSECTIONS) do
        set_c(cr, sec[2], 1)
        cairo_arc(cr, cx*S, cy*S, r*S*sec[1], 0, 2*math.pi)
        cairo_fill(cr)
    end
    set_c(cr, { 0xd8, 0xd5, 0xcf }, 0.10)
    cairo_set_line_width(cr, 2.0 * S)
    cairo_arc(cr, cx*S, cy*S, r*0.92*S, math.pi + 0.15, 3*math.pi/2)
    cairo_stroke(cr)
end

local function dial_ticks(cr, cx, cy, r)
    for i = 0, 59 do
        local major = (i % 5 == 0)
        local a = (i * 6 - 90) * math.pi / 180
        local rin  = r * (major and TICK_MI_FR or TICK_NI_FR)
        local rout = r * (major and TICK_MO_FR or TICK_NO_FR)
        set_c(cr, major and TICKMAJOR or TICKMINOR, major and 0.55 or 0.85)
        cairo_set_line_width(cr, (major and 2.4 or 1.3) * S)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_move_to(cr, cx*S + rin*S*math.cos(a), cy*S + rin*S*math.sin(a))
        cairo_line_to(cr, cx*S + rout*S*math.cos(a), cy*S + rout*S*math.sin(a))
        cairo_stroke(cr)
    end
end

-- The metal-sysmon gauge needle: a rectangular HANDCOL bar sweeping
-- 270 degrees from 12 o'clock as track progress rises. Base sits just
-- outside the album art disc; tip reaches the inner edge of the black
-- rim (the outer edge of the grey tick zone).
local function gauge_needle(cr, cx, cy, r, frac, color, paused)
    frac = math.max(0, math.min(1, frac or 0))
    local base  = ART_R * 1.02
    local tip   = r * 0.96
    local halfw = 2.0 * S
    local ang   = -math.pi/2 + frac * 3*math.pi/2   -- 12 o'clock -> 9 o'clock
    cairo_save(cr)
    cairo_translate(cr, cx*S, cy*S)
    cairo_rotate(cr, ang)
    cairo_new_path(cr)
    cairo_move_to(cr, base*S, -halfw)
    cairo_line_to(cr, tip*S,  -halfw)
    cairo_line_to(cr, tip*S,   halfw)
    cairo_line_to(cr, base*S,  halfw)
    cairo_close_path(cr)
    set_c(cr, color, 1)
    cairo_fill(cr)
    if paused then
        -- rest line under the needle at 12 o'clock
        set_c(cr, { 0xd8, 0xd5, 0xcf }, 0.10)
        cairo_set_line_width(cr, 1.0 * S)
        cairo_new_path(cr)
        cairo_move_to(cr, base*S, -halfw/2)
        cairo_line_to(cr, tip*S, -halfw/2)
        cairo_stroke(cr)
    end
    cairo_restore(cr)
end

-- Machined bezel ring, identical to the metal-sysmon gauge bezel:
-- bright base rim, shadow arc on the bottom-right, sheen on the
-- upper-left (light from ~11 o'clock).
local function dial_bezel(cr, cx, cy, r)
    set_c(cr, { 0x9a, 0x97, 0x93 }, 1)
    cairo_set_line_width(cr, 1.8 * S)
    cairo_arc(cr, cx*S, cy*S, r*S, 0, 2*math.pi)
    cairo_stroke(cr)
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
        cairo_arc(cr, cx*S, cy*S, r*S, peak - hw, peak + hw)
        cairo_stroke(cr)
    end
    local sheen = {
        { math.pi + 0.10, 3*math.pi/2, 3.6 * S, 0.07 },
        { math.pi + 0.30, 3*math.pi/2, 2.6 * S, 0.11 },
        { math.pi + 0.52, 3*math.pi/2, 1.7 * S, 0.16 },
    }
    for _, p in ipairs(sheen) do
        set_c(cr, { 0xd8, 0xd5, 0xcf }, p[4])
        cairo_set_line_width(cr, p[3])
        cairo_arc(cr, cx*S, cy*S, r*S, p[1], p[2])
        cairo_stroke(cr)
    end
end

-- ==================== COVER ART ==============================
local function file_mtime(path)
    local h = io.popen('stat -c %Y ' .. "'" .. path .. "'" .. ' 2>/dev/null')
    if not h then return 0 end
    local v = tonumber(h:read('*a') or '') or 0
    h:close()
    return v
end
local function file_exists(path)
    local h = io.open(path, 'rb')
    if h then h:close(); return true end
    return false
end
local function shell_quote(v)
    return "'" .. tostring(v):gsub("'", "'\\''") .. "'"
end

local function draw_cover_image(cr, cx, cy, img_r)
    local jpg_mtime = file_mtime(COVER_JPG)
    if jpg_mtime > 0 then
        local marker_h = io.open(COVER_MARKER, 'r')
        local marker_v = marker_h and marker_h:read('*l') or ''
        if marker_h then marker_h:close() end
        if marker_v ~= tostring(jpg_mtime) or not file_exists(COVER_PNG) then
            os.remove(COVER_PNG)
            local sz = math.floor(img_r * 2 + 0.5)   -- %d needs an integer (ART_R is fractional)
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
    cairo_set_source_rgba(cr, 0.035, 0.045, 0.05, 1.00)
    cairo_arc(cr, cx*S, cy*S, r*S, 0, 2*math.pi)
    cairo_fill(cr)
    cairo_set_source_rgba(cr, 0.18, 0.21, 0.22, 0.82)
    cairo_set_line_width(cr, math.max(1, 1.0 * S))
    cairo_arc(cr, cx*S, cy*S, r*0.6*S, 0, 2*math.pi)
    cairo_stroke(cr)
    local bars = { 0.40, 0.80, 1.00, 0.80, 0.40 }
    for i, f in ipairs(bars) do
        local bh = r * f
        local x = cx + (i - 3) * 11
        cairo_set_source_rgba(cr, 0.22, 0.25, 0.26, 0.72)
        cairo_rectangle(cr, (x - 2)*S, (cy - bh/2)*S, 4*S, bh*S)
        cairo_fill(cr)
    end
end

-- ==================== CACHE PARSING ==========================
local STATUS_PATTERN = '^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$'

local function clean(v)
    v = tostring(v or '')
    v = v:gsub('[\t\r\n|]', ' ')
    v = v:gsub('[%c]', ' ')
    v = v:gsub('%s+', ' ')
    v = v:gsub('^%s+', ''):gsub('%s+$', '')
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
    dur  = tonumber(dur) or 0
    pos  = tonumber(pos) or 0
    if dur < 0 then dur = 0 end
    if pos < 0 then pos = 0 end
    state = clean(state):lower()
    if state ~= 'playing' and state ~= 'paused' and state ~= 'waiting' and state ~= 'stopped' then
        state = 'stopped'
    end
    local active = state ~= 'stopped' and (title ~= '' or artist ~= '')
    return {
        title    = clean(title),
        artist   = clean(artist),
        album    = clean(album),
        duration = dur,
        position = pos,
        state    = state,
        active   = active
    }
end

local function get_data()
    local line = read_cache()
    if not line or line == '' then
        return { title='', artist='', album='', duration=0, position=0, state='stopped', active=false }
    end
    local d = parse_status(line)
    return d or { title='', artist='', album='', duration=0, position=0, state='stopped', active=false }
end

local function format_time(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format('%d:%02d', math.floor(sec/60), sec%60)
end

local function state_color_label(state, active)
    if active and state == 'playing'  then return HANDCOL, 'PLAYING' end
    if active and state == 'paused'   then return GREY,    'PAUSED'  end
    if active and state == 'waiting'  then return GREY,    'WAITING' end
    return DARK, 'STOPPED'
end

-- ===================== MAIN DRAW =============================
function conky_draw_now_playing()
    if conky_window == nil then return end
    local w = conky_window.width
    local h = conky_window.height
    S = w / GRID_W

    local cs = cairo_xlib_surface_create(conky_window.display,
                conky_window.drawable, conky_window.visual, w, h)
    local cr = cairo_create(cs)
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST)

    paint_plate(cr, w, h)

    local d = get_data()
    local scol, slabel = state_color_label(d.state, d.active)
    local is_playing = d.active and d.state == 'playing'
    local header_label = is_playing and 'NOW PLAYING' or 'PIANOBAR'
    local content = is_playing and WHITE or TXT
    local frac = 0
    if d.active and d.duration > 0 then
        frac = math.max(0, math.min(1, d.position / d.duration))
    end

    -- === HEADER STRIP ===
    paint_module(cr, MOD_MX*S, HDR_Y*S, MOD_W*S, HDR_H*S, MOD_CR)
    text_at(cr, CNT_LX, HDR_Y + 34, header_label, content, 16, false, true)
    local elapsed = d.active and format_time(d.position) or '--:--'
    local total   = (d.active and d.duration > 0) and format_time(d.duration) or '--:--'
    local tstr = elapsed .. '  /  ' .. total
    text_right(cr, CNT_RX, HDR_Y + 56, tstr, GREY, 15, true, true)
    if d.active then
        cairo_select_font_face(cr, FSANS, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, 12 * S)
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, slabel, ext)
        local xpos = CNT_RX - (ext.width + ext.x_bearing) - 18
        draw_dot(cr, xpos, HDR_Y + 26, 3, scol)
        text_at(cr, xpos + 8, HDR_Y + 30, slabel, scol, 12, true, true)
    end

    -- === LEFT MODULE: RECORD DIAL ===
    paint_module(cr, DIAL_X*S, DIAL_Y*S, DIAL_W*S, DIAL_H*S, MOD_CR)
    dial_shadow(cr, DIAL_CX, DIAL_CY, DIAL_R)
    dial_well(cr, DIAL_CX, DIAL_CY, DIAL_R)
    local has_art = draw_cover_image(cr, DIAL_CX, DIAL_CY, ART_R)
    if not has_art then
        draw_cover_placeholder(cr, DIAL_CX, DIAL_CY, ART_R)
    end
    dial_ticks(cr, DIAL_CX, DIAL_CY, DIAL_R)
    local needle_color = is_playing and HANDCOL or (d.active and GREY or DARK)
    gauge_needle(cr, DIAL_CX, DIAL_CY, DIAL_R, frac, needle_color, d.active and not is_playing)
    dial_bezel(cr, DIAL_CX, DIAL_CY, DIAL_R)

    -- === RIGHT MODULE: METADATA ===
    paint_module(cr, META_X*S, META_Y*S, META_W*S, META_H*S, MOD_CR)
    text_at(cr, MTX, META_Y + 32, 'TRACK', GREY, 9, false, true)
    text_at(cr, MTX, META_Y + 60, fit_text(cr, d.title ~= '' and d.title or 'No Music Playing', META_CW, FSANS, 18, true), content, 18, false, true)
    text_at(cr, MTX, META_Y + 108, 'ARTIST', GREY, 9, false, true)
    text_at(cr, MTX, META_Y + 132, fit_text(cr, d.artist ~= '' and d.artist or '—', META_CW, FSANS, 13, false), TXT, 13, false, false)
    text_at(cr, MTX, META_Y + 180, 'ALBUM', GREY, 9, false, true)
    text_at(cr, MTX, META_Y + 204, fit_text(cr, d.album ~= '' and d.album or '—', META_CW, FSANS, 11, false), TXT, 11, false, false)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
