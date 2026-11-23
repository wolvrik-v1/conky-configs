--[[
  Light Japan Bodhi Lacquer Clock
  Ink-steel instrument with a restrained bronze bodhi-leaf motif.
]]

require 'cairo'

local GRID_W = 280
local GRID_H = 280
local S = 1
local DEG = math.pi / 180

local TEXT_EXT = cairo_text_extents_t:create()

-- ======================= BODHI LACQUER PALETTE =======================
local LACQUER_BLACK = { 0.541, 0.467, 0.369 }
local INK_STEEL     = { 0.424, 0.400, 0.349 }
local GRAPHITE      = { 0.302, 0.259, 0.208 }
local LEMON_CHIFFON = { 0.098, 0.086, 0.067 }
local BODHI_BRONZE  = { 0.811, 0.709, 0.545 }
local CINNABAR      = { 0.72, 0.23, 0.18 }

local function set_c(cr, c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or 1)
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

-- ======================= TIME SOURCE =========================
local HAS_SOCKET, SOCKET = pcall(require, 'socket')
local last_wall = nil

local function wall_now()
    if not HAS_SOCKET then return nil end
    local ok, t = pcall(SOCKET.gettime)
    if not ok or type(t) ~= 'number' then return nil end
    if last_wall ~= nil and t < last_wall and (last_wall - t) < 1.0 then
        t = last_wall
    end
    last_wall = t
    return t
end

local function local_offset(t)
    t = math.floor(t)
    local d = os.date('*t', t)
    local off = (d.hour*3600 + d.min*60 + d.sec) - (t % 86400)
    if off > 14*3600 then off = off - 86400
    elseif off < -12*3600 then off = off + 86400 end
    return off
end

local function clock_now()
    local w = wall_now()
    if w then return w + local_offset(w) end
    return os.time() + local_offset(os.time())
end

-- ======================= BODHI LACQUER GEOMETRY ===============
local CX, CY    = 140, 140
local PLATE_R   = 132
local RIM_MID   = 135.5
local RIM_W     = 7
local RIM_OUT   = 139
local TICK_R    = 128
local TICK_MI_FR, TICK_MO_FR = 0.958, 0.992
local TICK_NI_FR, TICK_NO_FR = 0.964, 0.980

local function paint_round_plate(cr)
    local g = cairo_pattern_create_radial(CX*S, CY*S*0.90, 0, CX*S, CY*S, PLATE_R*S)
    cairo_pattern_add_color_stop_rgba(g, 0.00, 0.671, 0.655, 0.588, 0.94)
    cairo_pattern_add_color_stop_rgba(g, 0.62, 0.600, 0.588, 0.537, 0.96)
    cairo_pattern_add_color_stop_rgba(g, 0.86, 0.541, 0.467, 0.369, 0.97)
    cairo_pattern_add_color_stop_rgba(g, 1.00, 0.424, 0.400, 0.349, 0.98)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, PLATE_R*S, 0, 2*math.pi)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)
end

local function bodhi_leaf(cr)
    cairo_save(cr)
    cairo_translate(cr, CX*S, (CY - 5)*S)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    local leaf_hi = { 0.98, 0.91, 0.75 }

    local function leaf_path()
        cairo_new_path(cr)
        cairo_move_to(cr, 0, -36*S)
        cairo_curve_to(cr, -3*S, -31*S, -10*S, -21*S, -22*S, 4*S)
        cairo_curve_to(cr, -26*S, 18*S, -16*S, 32*S, -6*S, 31*S)
        cairo_curve_to(cr, -3*S, 30*S, -1.5*S, 28*S, 0, 27*S)
        cairo_curve_to(cr, 1.5*S, 28*S, 3*S, 30*S, 6*S, 31*S)
        cairo_curve_to(cr, 16*S, 32*S, 26*S, 18*S, 22*S, 4*S)
        cairo_curve_to(cr, 10*S, -21*S, 3*S, -31*S, 0, -36*S)
        cairo_close_path(cr)
    end

    local function mid_path()
        cairo_new_path(cr)
        cairo_move_to(cr, 0, -30*S)
        cairo_curve_to(cr, -1*S, -10*S, 1*S, 11*S, 0, 25*S)
    end

    local VEINS = {
        { -18,  7.2, 4.6 },
        { -11, 10.8, 5.1 },
        {  -4, 13.6, 5.6 },
        {   3, 16.8, 6.0 },
        {  10, 19.2, 6.3 },
        {  17, 18.4, 6.0 },
        {  23, 14.2, 5.2 },
        {  27,  8.6, 4.0 },
    }

    local function side_path()
        cairo_new_path(cr)
        for i = 1, #VEINS do
            local y = VEINS[i][1] * S
            local spread = VEINS[i][2] * S
            local rise = VEINS[i][3] * S
            cairo_move_to(cr, 0, y)
            cairo_curve_to(cr, -spread*0.32, y - rise*0.10,
                               -spread*0.74, y - rise*0.48,
                               -spread, y - rise)
            cairo_move_to(cr, 0, y)
            cairo_curve_to(cr, spread*0.32, y - rise*0.10,
                               spread*0.74, y - rise*0.48,
                               spread, y - rise)
        end
    end

    local function stem_path()
        cairo_new_path(cr)
        cairo_move_to(cr, 0, 25.5*S)
        cairo_curve_to(cr, -0.9*S, 30*S, -0.5*S, 34.5*S, 0.2*S, 37.5*S)
    end

    leaf_path()
    local lg = cairo_pattern_create_linear(-24*S, 12*S, 24*S, -18*S)
    cairo_pattern_add_color_stop_rgba(lg, 0.00, 0.360, 0.290, 0.200, 0.62)
    cairo_pattern_add_color_stop_rgba(lg, 0.38, 0.620, 0.520, 0.370, 0.56)
    cairo_pattern_add_color_stop_rgba(lg, 0.72, 0.811, 0.709, 0.545, 0.52)
    cairo_pattern_add_color_stop_rgba(lg, 1.00, 0.960, 0.880, 0.700, 0.50)
    cairo_set_source(cr, lg)
    cairo_fill_preserve(cr)
    cairo_pattern_destroy(lg)

    cairo_save(cr)
    cairo_clip(cr)
    local rg = cairo_pattern_create_radial(0, 1*S, 0, 0, 1*S, 34*S)
    cairo_pattern_add_color_stop_rgba(rg, 0.00, 0.302, 0.259, 0.208, 0.15)
    cairo_pattern_add_color_stop_rgba(rg, 0.55, 0.302, 0.259, 0.208, 0.04)
    cairo_pattern_add_color_stop_rgba(rg, 1.00, 0.302, 0.259, 0.208, 0.00)
    cairo_new_path(cr)
    cairo_rectangle(cr, -30*S, -40*S, 60*S, 80*S)
    cairo_set_source(cr, rg)
    cairo_fill(cr)
    cairo_pattern_destroy(rg)
    local rl = cairo_pattern_create_radial(0, 1*S, 0, 0, 1*S, 34*S)
    cairo_pattern_add_color_stop_rgba(rl, 0.00, 0.980, 0.910, 0.750, 0.00)
    cairo_pattern_add_color_stop_rgba(rl, 0.78, 0.980, 0.910, 0.750, 0.00)
    cairo_pattern_add_color_stop_rgba(rl, 0.94, 0.980, 0.910, 0.750, 0.11)
    cairo_pattern_add_color_stop_rgba(rl, 1.00, 0.980, 0.910, 0.750, 0.00)
    cairo_new_path(cr)
    cairo_rectangle(cr, -30*S, -40*S, 60*S, 80*S)
    cairo_set_source(cr, rl)
    cairo_fill(cr)
    cairo_pattern_destroy(rl)
    cairo_restore(cr)

    cairo_save(cr)
    cairo_translate(cr, 0.5*S, 0.6*S)
    stem_path()
    set_c(cr, GRAPHITE, 0.55)
    cairo_set_line_width(cr, 5.4 * S)
    cairo_stroke(cr)
    cairo_restore(cr)
    stem_path()
    set_c(cr, BODHI_BRONZE, 0.90)
    cairo_set_line_width(cr, 3.2 * S)
    cairo_stroke(cr)
    cairo_save(cr)
    cairo_translate(cr, -0.3*S, -0.3*S)
    stem_path()
    set_c(cr, leaf_hi, 0.40)
    cairo_set_line_width(cr, 1.3 * S)
    cairo_stroke(cr)
    cairo_restore(cr)

    leaf_path()
    set_c(cr, GRAPHITE, 0.34)
    cairo_set_line_width(cr, 1.6 * S)
    cairo_stroke_preserve(cr)
    set_c(cr, BODHI_BRONZE, 0.72)
    cairo_set_line_width(cr, 0.95 * S)
    cairo_stroke_preserve(cr)
    set_c(cr, leaf_hi, 0.28)
    cairo_set_line_width(cr, 0.55 * S)
    cairo_stroke(cr)

    cairo_save(cr)
    cairo_translate(cr, 0.55*S, 0.65*S)
    mid_path()
    set_c(cr, GRAPHITE, 0.38)
    cairo_set_line_width(cr, 2.0 * S)
    cairo_stroke(cr)
    cairo_restore(cr)
    cairo_save(cr)
    cairo_translate(cr, -0.35*S, -0.35*S)
    mid_path()
    set_c(cr, leaf_hi, 0.42)
    cairo_set_line_width(cr, 1.45 * S)
    cairo_stroke(cr)
    cairo_restore(cr)
    mid_path()
    set_c(cr, BODHI_BRONZE, 0.92)
    cairo_set_line_width(cr, 0.9 * S)
    cairo_stroke(cr)

    cairo_save(cr)
    cairo_translate(cr, 0.55*S, 0.65*S)
    side_path()
    set_c(cr, GRAPHITE, 0.34)
    cairo_set_line_width(cr, 1.9 * S)
    cairo_stroke(cr)
    cairo_restore(cr)
    cairo_save(cr)
    cairo_translate(cr, -0.30*S, -0.30*S)
    side_path()
    set_c(cr, leaf_hi, 0.36)
    cairo_set_line_width(cr, 1.35 * S)
    cairo_stroke(cr)
    cairo_restore(cr)
    side_path()
    set_c(cr, BODHI_BRONZE, 0.92)
    cairo_set_line_width(cr, 0.85 * S)
    cairo_stroke(cr)

    cairo_restore(cr)
end

local function ink_steel_inner_bezel(cr, cx, cy)
    local BEZEL_R = 116.0
    local BEZEL_W = 4.5
    set_c(cr, LACQUER_BLACK, 0.90)
    cairo_set_line_width(cr, (BEZEL_W + 1.5) * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, BEZEL_R*S, 0, 2*math.pi)
    cairo_stroke(cr)
    set_c(cr, INK_STEEL, 0.85)
    cairo_set_line_width(cr, BEZEL_W * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, BEZEL_R*S, 0, 2*math.pi)
    cairo_stroke(cr)
    set_c(cr, GRAPHITE, 0.60)
    cairo_set_line_width(cr, 0.8 * S)
    cairo_new_path(cr)
    cairo_arc(cr, cx*S, cy*S, (BEZEL_R - BEZEL_W/2)*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

local function dial_ticks(cr, cx, cy, r)
    for i = 1, 59 do
        local d = (i * 6) % 360
        if d > 180 then d = d - 360 end
        if math.abs(d) >= 0 then
            local major = (i % 5 == 0)
            local a = (i * 6 - 90) * DEG
            local rin  = r * (major and TICK_MI_FR or TICK_NI_FR)
            local rout = r * (major and TICK_MO_FR or TICK_NO_FR)
            set_c(cr, major and LEMON_CHIFFON or GRAPHITE, major and 0.88 or 0.95)
            cairo_set_line_width(cr, (major and 1.8 or 1.15) * S)
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
            cairo_new_path(cr)
            cairo_move_to(cr, cx*S + rin*S*math.cos(a), cy*S + rin*S*math.sin(a))
            cairo_line_to(cr, cx*S + rout*S*math.cos(a), cy*S + rout*S*math.sin(a))
            cairo_stroke(cr)
        end
    end
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
end

local function ink_steel_rim(cr)
    set_c(cr, INK_STEEL, 0.95)
    cairo_set_line_width(cr, RIM_W * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, RIM_MID*S, 0, 2*math.pi)
    cairo_stroke(cr)
    set_c(cr, LACQUER_BLACK, 0.75)
    cairo_set_line_width(cr, 2.6 * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, (RIM_MID - 1.6)*S, 0, 2*math.pi)
    cairo_stroke(cr)
    set_c(cr, BODHI_BRONZE, 0.26)
    cairo_set_line_width(cr, 0.6 * S)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, (RIM_MID - RIM_W/2 + 0.6)*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

-- ======================= JUMP-HOUR WINDOW ====================
local function jump_hour(cr)
    local d = os.date('*t')
    local hh = d.hour % 12
    if hh == 0 then hh = 12 end

    local wx, wy = CX, CY - 84
    local ww, wh = 46, 30
    local x0 = (wx - ww/2) * S
    local y0 = (wy - wh/2) * S

    set_c(cr, INK_STEEL, 0.95)
    rrect(cr, x0, y0, ww*S, wh*S, 4*S)
    cairo_fill(cr)

    cairo_save(cr)
    cairo_new_path(cr)
    cairo_rectangle(cr, x0, y0, ww*S, wh*S)
    cairo_clip(cr)
    set_c(cr, LEMON_CHIFFON, 0.96)
    cairo_select_font_face(cr, "DejaVu Sans Mono", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 26 * S)
    cairo_text_extents(cr, tostring(hh), TEXT_EXT)
    local tw = TEXT_EXT.width
    cairo_move_to(cr, wx*S - tw/2 - TEXT_EXT.x_bearing, wy*S + 9*S)
    cairo_show_text(cr, tostring(hh))
    cairo_restore(cr)

    -- AM / PM tag under the window
    cairo_select_font_face(cr, "Noto Sans CJK JP", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 11 * S)
    local ap = (d.hour < 12) and '午前' or '午後'
    cairo_text_extents(cr, ap, TEXT_EXT)
    set_c(cr, CINNABAR, 1.0)
    cairo_move_to(cr, wx*S - TEXT_EXT.width/2 - TEXT_EXT.x_bearing,
                      (wy + wh/2 + 13)*S)
    cairo_show_text(cr, ap)

    set_c(cr, INK_STEEL, 0.85)
    cairo_set_line_width(cr, 1.2 * S)
    rrect(cr, x0, y0, ww*S, wh*S, 4*S)
    cairo_stroke(cr)

    -- Crown dot above the aperture
    set_c(cr, BODHI_BRONZE, 0.62)
    cairo_new_path(cr)
    cairo_arc(cr, wx*S, (wy - wh/2 - 7)*S, 2.2*S, 0, 2*math.pi)
    cairo_fill(cr)
end

-- ======================= TOURBILLON SECONDS ==================
local function tourbillon(cr)
    local now = clock_now()
    local s = now % 60
    local ang = (s / 60) * 2 * math.pi - math.pi/2

    local tx, ty = CX, CY + 78
    local TR = 26

    set_c(cr, LACQUER_BLACK, 0.88)
    cairo_new_path(cr)
    cairo_arc(cr, tx*S, ty*S, (TR + 4)*S, 0, 2*math.pi)
    cairo_fill(cr)

    set_c(cr, GRAPHITE, 0.75)
    cairo_set_line_width(cr, 1.4 * S)
    cairo_new_path(cr)
    cairo_arc(cr, tx*S, ty*S, TR*S, 0, 2*math.pi)
    cairo_stroke(cr)

    set_c(cr, GRAPHITE, 0.45)
    cairo_set_line_width(cr, 0.8 * S)
    cairo_new_path(cr)
    cairo_arc(cr, tx*S, ty*S, (TR * 0.55)*S, 0, 2*math.pi)
    cairo_stroke(cr)

    set_c(cr, LEMON_CHIFFON, 0.86)
    cairo_set_line_width(cr, 1.0 * S)
    for k = 0, 2 do
        local a = ang + k * (2*math.pi/3)
        cairo_new_path(cr)
        cairo_move_to(cr, tx*S, ty*S)
        cairo_line_to(cr, (tx + TR*0.92*math.cos(a))*S, (ty + TR*0.92*math.sin(a))*S)
        cairo_stroke(cr)
    end

    local tipx = (tx + TR*0.92*math.cos(ang))*S
    local tipy = (ty + TR*0.92*math.sin(ang))*S
    set_c(cr, CINNABAR, 1.0)
    cairo_new_path(cr)
    cairo_arc(cr, tipx, tipy, 3.0*S, 0, 2*math.pi)
    cairo_fill(cr)

    set_c(cr, INK_STEEL, 0.95)
    cairo_new_path(cr)
    cairo_arc(cr, tx*S, ty*S, 4.5*S, 0, 2*math.pi)
    cairo_fill(cr)
    set_c(cr, LEMON_CHIFFON, 0.75)
    cairo_set_line_width(cr, 0.9 * S)
    cairo_new_path(cr)
    cairo_arc(cr, tx*S, ty*S, 4.5*S, 0, 2*math.pi)
    cairo_stroke(cr)
end

-- ======================= BOLD KANJI NUMERALS ==================
local function kanji_numerals(cr)
    local kanji = {"十二", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一"}
    cairo_select_font_face(cr, "Noto Sans CJK JP", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)

    for i = 1, 12 do
        local a = (i * 30 - 90) * DEG
        if i ~= 12 and i ~= 6 then
            local rn = TICK_R * 0.78
            local s  = kanji[i]

            if i == 4 then
                cairo_set_font_size(cr, 14.8 * S)
            else
                cairo_set_font_size(cr, 13.5 * S)
            end
            set_c(cr, LEMON_CHIFFON, 0.98)

            cairo_text_extents(cr, s, TEXT_EXT)
            local tw = TEXT_EXT.width / S
            local th = TEXT_EXT.height / S
            cairo_move_to(cr, (CX + rn*math.cos(a))*S - tw*S/2 - TEXT_EXT.x_bearing,
                              (CY + rn*math.sin(a))*S + th*S*0.35)
            cairo_show_text(cr, s)
        end
    end
end

-- ======================= MINUTE HAND =========================
local function minute_hand(cr)
    local now = clock_now()
    local m = (now/60) % 60
    local a = (m / 60) * 360 * DEG - 90 * DEG
    local R = 96.0

    set_c(cr, LEMON_CHIFFON, 0.95)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_width(cr, 2.0 * S)
    cairo_new_path(cr)
    cairo_move_to(cr, (CX - 10*math.cos(a))*S, (CY - 10*math.sin(a))*S)
    cairo_line_to(cr, (CX + R*math.cos(a))*S, (CY + R*math.sin(a))*S)
    cairo_stroke(cr)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)

    -- Tiny directional arrowhead on the tip of the minute hand
    local tipx, tipy = CX + R*math.cos(a), CY + R*math.sin(a)
    local bx = math.cos(a + math.pi/2) * 2.6
    local by = math.sin(a + math.pi/2) * 2.6
    set_c(cr, LEMON_CHIFFON, 0.95)
    cairo_new_path(cr)
    cairo_move_to(cr, (tipx + 4*math.cos(a))*S, (tipy + 4*math.sin(a))*S)
    cairo_line_to(cr, (tipx - 1*math.cos(a) + bx)*S, (tipy - 1*math.sin(a) + by)*S)
    cairo_line_to(cr, (tipx - 1*math.cos(a) - bx)*S, (tipy - 1*math.sin(a) - by)*S)
    cairo_close_path(cr)
    cairo_fill(cr)

    set_c(cr, GRAPHITE, 0.95)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, 5.2 * S, 0, 2*math.pi)
    cairo_fill(cr)

    set_c(cr, INK_STEEL, 1.0)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, 3.6 * S, 0, 2*math.pi)
    cairo_fill(cr)

    set_c(cr, LEMON_CHIFFON, 0.95)
    cairo_new_path(cr)
    cairo_arc(cr, CX*S, CY*S, 1.6 * S, 0, 2*math.pi)
    cairo_fill(cr)
end

-- ======================= MAIN DRAW ============================
function conky_main()
    if conky_window == nil then return end
    local w = conky_window.width
    local h = conky_window.height
    if w < 8 or h < 8 then return end
    S = w / GRID_W

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, w, h)
    local cr = cairo_create(cs)
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

    paint_round_plate(cr)
    bodhi_leaf(cr)

    ink_steel_inner_bezel(cr, CX, CY)
    dial_ticks(cr, CX, CY, TICK_R)
    kanji_numerals(cr)

    jump_hour(cr)
    tourbillon(cr)
    minute_hand(cr)

    ink_steel_rim(cr)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
