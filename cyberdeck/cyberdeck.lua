-- ============================================================
--  CYBERDECK  //  system monitor for Conky 1.12 (Lua/Cairo)
--  Fully procedural. No image assets.
-- ============================================================

require 'cairo'

-- ------------------------------------------------------------
--  DESIGN GRID
-- ------------------------------------------------------------
local GRID_W, GRID_H = 340, 920
local S = 1.0

-- ------------------------------------------------------------
--  PALETTE  (0..1 floats)
-- ------------------------------------------------------------
local function col(r, g, b) return { r / 255, g / 255, b / 255 } end

local G_BRIGHT = col(0x6c, 0xff, 0x8a)   -- hot core of the neon
local G_MAIN   = col(0x00, 0xff, 0x41)   -- primary phosphor green
local G_MID    = col(0x00, 0xb3, 0x2e)
local G_DIM    = col(0x0c, 0x7a, 0x2a)
local G_FAINT  = col(0x0a, 0x3a, 0x18)
local G_TRACE  = col(0x06, 0x2a, 0x12)
local BG_PANEL = col(0x02, 0x08, 0x04)
local BG_DEEP  = col(0x01, 0x03, 0x02)
local CYAN     = col(0x30, 0xf0, 0xff)
local AMBER    = col(0xff, 0xb0, 0x20)
local RED      = col(0xff, 0x30, 0x28)
local WHITE    = col(0xe8, 0xff, 0xee)

-- ------------------------------------------------------------
--  FONTS
-- ------------------------------------------------------------
local F_TITLE = 'SAIBA-45'
local F_MONO  = 'DejaVu Sans Mono'
local F_TECH  = 'Electroharmonix'
local F_KANA  = 'Noto Sans Mono CJK JP'
local F_UI    = 'Noto Sans Mono CJK JP'

-- ------------------------------------------------------------
--  DATA / ANIMATION STATE
-- ------------------------------------------------------------
local st = {
    init = false,
    prev_up = nil,
    net = { rx = 0, tx = 0, t = 0, up = 0, dn = 0 },
    cores = nil,
    prev_cores = nil,
    cpu_hist = {},
    net_hist = {},
    rain = {},
    blips = {},
    next_glitch = 0,
    glitch_until = 0,
    scroll = 0,
    boot = 0,
    adsb = { tracks = {}, t = 0, n = 0, link = false },
    sweep_prev = nil,
}
local CHIST, NHIST = 26, 26
for i = 1, CHIST do st.cpu_hist[i] = 0 end
for i = 1, NHIST do st.net_hist[i] = 0 end

-- ------------------------------------------------------------
--  SMALL HELPERS
-- ------------------------------------------------------------
local function readfile(p)
    local f = io.open(p, 'r')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

local function uptime()
    local s = readfile('/proc/uptime')
    if not s then return os.time() end
    return tonumber(s:match('^(%S+)')) or os.time()
end

local function rgba(cr, c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or 1)
end

local function mix(c1, c2, t)
    return { c1[1] + (c2[1] - c1[1]) * t,
             c1[2] + (c2[2] - c1[2]) * t,
             c1[3] + (c2[3] - c1[3]) * t }
end

local function lerp(a, b, t) return a + (b - a) * t end

-- value colour: mostly phosphor green, hot only at the top
local function valcol(v)
    if v < 0.78 then return mix(G_MAIN, G_BRIGHT, v / 0.78) end
    if v < 0.92 then return mix(G_BRIGHT, AMBER, (v - 0.78) / 0.14) end
    return mix(AMBER, RED, (v - 0.92) / 0.08)
end

-- ADS-B return colour by altitude band
local function adscol(alt)
    if alt < 10000 then return G_MAIN end
    if alt < 28000 then return CYAN end
    return AMBER
end

-- text drawing with optional alignment + shadow
local function text(cr, s, x, y, fam, size, weight, c, a, align, shadow)
    cairo_select_font_face(cr, fam, CAIRO_FONT_SLANT_NORMAL,
        weight or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, s, ext)
    local tx = x
    if align == 'center' then
        tx = x - (ext.width / 2 + ext.x_bearing)
    elseif align == 'right' then
        tx = x - (ext.width + ext.x_bearing)
    end
    if shadow ~= false then
        rgba(cr, BG_DEEP, (a or 1) * 0.85)
        cairo_move_to(cr, tx + size * 0.06, y + size * 0.06)
        cairo_show_text(cr, s)
    end
    rgba(cr, c, a or 1)
    cairo_move_to(cr, tx, y)
    cairo_show_text(cr, s)
    return ext
end

-- emissive text: glyphs as a path, stroked with bloom layers then filled hot.
-- works well for thin/pixel display fonts that would otherwise read dim.
local function glow_text(cr, s, x, y, fam, size, c, align, weight)
    if not s or s == '' then return end
    cairo_select_font_face(cr, fam, CAIRO_FONT_SLANT_NORMAL,
        weight or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, s, ext)
    local tx = x
    if align == 'center' then
        tx = x - (ext.width / 2 + ext.x_bearing)
    elseif align == 'right' then
        tx = x - (ext.width + ext.x_bearing)
    end
    cairo_new_path(cr)
    cairo_move_to(cr, tx, y)
    cairo_text_path(cr, s)
    local passes = { { 9.0, 0.05 }, { 6.5, 0.07 }, { 4.4, 0.10 },
                     { 2.8, 0.16 }, { 1.6, 0.30 }, { 0.9, 0.55 } }
    for _, p in ipairs(passes) do
        cairo_set_line_width(cr, p[1] * S)
        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        rgba(cr, c, p[2])
        cairo_stroke_preserve(cr)
    end
    rgba(cr, G_BRIGHT, 1)
    cairo_fill_preserve(cr)
    cairo_set_line_width(cr, 1.25 * S)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
    rgba(cr, G_BRIGHT, 0.95)
    cairo_stroke(cr)
end

-- multi-pass neon stroke of the CURRENT path (keeps path alive)
local function neon_path(cr, c, width)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
    cairo_set_line_width(cr, width * 3.6)
    rgba(cr, c, 0.08)
    cairo_stroke_preserve(cr)
    cairo_set_line_width(cr, width * 1.9)
    rgba(cr, c, 0.18)
    cairo_stroke_preserve(cr)
    cairo_set_line_width(cr, width)
    rgba(cr, c, 0.95)
    cairo_stroke(cr)
end

-- straight neon line
local function nline(cr, x1, y1, x2, y2, c, w, a)
    cairo_move_to(cr, x1, y1)
    cairo_line_to(cr, x2, y2)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_width(cr, w * 3.4)
    rgba(cr, c, 0.07 * (a or 1))
    cairo_stroke_preserve(cr)
    cairo_set_line_width(cr, w * 1.8)
    rgba(cr, c, 0.16 * (a or 1))
    cairo_stroke_preserve(cr)
    cairo_set_line_width(cr, w)
    rgba(cr, c, (a or 1))
    cairo_stroke(cr)
end

local function chamfer_path(cr, x, y, w, h, cut)
    cairo_move_to(cr, x + cut, y)
    cairo_line_to(cr, x + w - cut, y)
    cairo_line_to(cr, x + w, y + cut)
    cairo_line_to(cr, x + w, y + h - cut)
    cairo_line_to(cr, x + w - cut, y + h)
    cairo_line_to(cr, x + cut, y + h)
    cairo_line_to(cr, x, y + h - cut)
    cairo_line_to(cr, x, y + cut)
    cairo_close_path(cr)
end

local function rrect_path(cr, x, y, w, h, r)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r,     r, -math.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_arc(cr, x + r,     y + h - r, r, math.pi / 2, math.pi)
    cairo_arc(cr, x + r,     y + r,     r, math.pi, 3 * math.pi / 2)
    cairo_close_path(cr)
end

-- a framed instrument panel
local function panel(cr, x, y, w, h, cut, label)
    chamfer_path(cr, x, y, w, h, cut)
    rgba(cr, BG_PANEL, 0.86)
    cairo_fill_preserve(cr)
    cairo_set_line_width(cr, 1.0 * S)
    rgba(cr, G_DIM, 0.85)
    cairo_stroke(cr)

    -- corner brackets
    local b = 7 * S
    cairo_set_line_width(cr, 1.4 * S)
    rgba(cr, G_MAIN, 0.9)
    local corners = { { x, y, 1, 1 }, { x + w, y, -1, 1 },
                      { x, y + h, 1, -1 }, { x + w, y + h, -1, -1 } }
    for _, c in ipairs(corners) do
        cairo_move_to(cr, c[1] + c[3] * b, c[2])
        cairo_line_to(cr, c[1], c[2])
        cairo_line_to(cr, c[1], c[2] + c[4] * b)
        cairo_stroke(cr)
    end

    if label then
        text(cr, label, x + 9 * S, y + 14 * S, F_MONO, 8.5 * S,
             CAIRO_FONT_WEIGHT_BOLD, G_MID, 0.95, 'left')
    end
end

-- ------------------------------------------------------------
--  CIRCUIT TRACES (decorative frame doodads)
-- ------------------------------------------------------------
local function circuit(cr, x1, y1, x2, y2, seed)
    cairo_set_line_width(cr, 1.0 * S)
    rgba(cr, G_TRACE, 0.9)
    local seg = 9
    local x, y = x1, y1
    local horiz = true
    cairo_move_to(cr, x, y)
    local n = 0
    while (horiz and math.abs(x - x2) > seg) or (not horiz and math.abs(y - y2) > seg) do
        local step = ((n % 3 == 2) and -(seg * 1.6) or seg)
        if horiz then
            x = x + step
            x = math.max(math.min(x, x2), x1)
        else
            y = y + step
            y = math.max(math.min(y, y2), y1)
        end
        cairo_line_to(cr, x, y)
        horiz = not horiz
        n = n + 1
        if n > 14 then break end
    end
    cairo_line_to(cr, x2, y2)
    cairo_stroke(cr)
    rgba(cr, G_MAIN, 0.5)
    cairo_arc(cr, x2, y2, 1.6 * S, 0, 2 * math.pi)
    cairo_fill(cr)
end

-- ------------------------------------------------------------
--  MATRIX RAIN
-- ------------------------------------------------------------
local KANA = { 'ﾊ', 'ﾐ', 'ﾋ', 'ｰ', 'ｳ', 'ｼ', 'ﾅ', 'ﾓ', 'ﾆ', 'ｻ', 'ﾜ', 'ﾂ',
               'ｵ', 'ﾘ', 'ｱ', 'ﾎ', 'ﾃ', 'ﾏ', 'ｹ', 'ﾒ', 'ｴ', 'ｶ', 'ｷ', 'ﾑ',
               'ﾕ', 'ﾗ', 'ｾ', 'ﾈ', 'ｽ', 'ﾀ', 'ﾇ', 'ﾍ', '0', '1', '2', '3',
               '4', '5', '6', '7', '8', '9', '<', '>', '/', '\\', '|', '=',
               '+', '*', 'Ｚ', 'ｦ', 'ﾝ' }

local function init_rain()
    st.rain = {}
    local colw = 13
    local n = math.floor((GRID_W - 24) / colw)
    for i = 1, n do
        local len = math.random(8, 18)
        local glyphs = {}
        for j = 1, len do glyphs[j] = KANA[math.random(#KANA)] end
        st.rain[i] = {
            x = 14 + (i - 1) * colw + math.random(-1, 1),
            y = math.random(-GRID_H, 0) / 10,
            speed = math.random(1800, 4200) / 100,
            len = len,
            glyphs = glyphs,
            flicker = math.random() * 6.28,
        }
    end
end

local function draw_rain(cr, dt)
    local lh = 15
    cairo_select_font_face(cr, F_KANA, CAIRO_FONT_SLANT_NORMAL,
        CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 12 * S)
    for _, c in ipairs(st.rain) do
        c.y = c.y + c.speed * dt
        if c.y - (c.len * lh) / 10 > GRID_H / 10 then
            c.y = -math.random(2, 12)
            c.speed = math.random(1800, 4200) / 100
            c.len = math.random(8, 18)
            local g = {}
            for j = 1, c.len do g[j] = KANA[math.random(#KANA)] end
            c.glyphs = g
        end
        for j = 0, c.len - 1 do
            local gy = c.y - j * (lh / 10)
            if gy > 10 and gy < GRID_H - 10 then
                local f = 1 - (j / c.len)
                local a = (j == 0) and 0.55 or (f * f * 0.30)
                local cc = (j == 0) and G_BRIGHT or G_MAIN
                local gx = c.x * S
                rgba(cr, cc, a)
                cairo_move_to(cr, gx, gy * 10 * S)
                cairo_show_text(cr, c.glyphs[j + 1] or '0')
            end
        end
    end
end

-- ------------------------------------------------------------
--  GLITCH CLOCK
-- ------------------------------------------------------------
local function draw_clock(cr, s, cx, cy, size, up)
    local fam, weight = F_MONO, CAIRO_FONT_WEIGHT_BOLD
    cairo_select_font_face(cr, fam, CAIRO_FONT_SLANT_NORMAL, weight)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, s, ext)
    local tx = cx - (ext.width / 2 + ext.x_bearing)
    local ty = cy

    -- glow bloom
    rgba(cr, G_MAIN, 0.16)
    for _, o in ipairs({ { 0, 2 }, { 0, -2 }, { 2, 0 }, { -2, 0 } }) do
        cairo_move_to(cr, tx + o[1], ty + o[2])
        cairo_show_text(cr, s)
    end

    local glitching = up < st.glitch_until
    if glitching then
        -- slice tear: draw a few horizontal bands offset in x, occasionally cyan
        for band = 1, 3 do
            local by = ty - size + math.random() * size
            local bh = size * (0.12 + math.random() * 0.22)
            local off = (math.random() - 0.5) * size * 0.55
            cairo_save(cr)
            cairo_rectangle(cr, cx - size * 5, by, size * 10, bh)
            cairo_clip(cr)
            local cc = (band == 2) and CYAN or G_BRIGHT
            rgba(cr, cc, 0.9)
            cairo_move_to(cr, tx + off, ty)
            cairo_show_text(cr, s)
            cairo_restore(cr)
        end
    end

    -- crisp core
    rgba(cr, G_BRIGHT, 1)
    cairo_move_to(cr, tx, ty)
    cairo_show_text(cr, s)
    return ext
end

-- ------------------------------------------------------------
--  HEX GAUGE
-- ------------------------------------------------------------
local function hex_verts(cx, cy, r)
    local v = {}
    for i = 0, 5 do
        local a = -math.pi / 2 + i * math.pi / 3
        v[#v + 1] = { cx + r * math.cos(a), cy + r * math.sin(a) }
    end
    return v
end

local function hex_perim(cr, cx, cy, r, frac)
    if frac <= 0 then return end
    if frac > 1 then frac = 1 end
    local v = hex_verts(cx, cy, r)
    local total = 6 * r
    local target = total * frac
    cairo_move_to(cr, v[1][1], v[1][2])
    local acc = 0
    for i = 1, 6 do
        local a, b = v[i], v[i % 6 + 1]
        if acc + r <= target then
            cairo_line_to(cr, b[1], b[2])
            acc = acc + r
        else
            local t = (target - acc) / r
            cairo_line_to(cr, a[1] + (b[1] - a[1]) * t,
                              a[2] + (b[2] - a[2]) * t)
            break
        end
    end
end

local function hex_gauge(cr, cx, cy, r, frac, label, value, sub)
    -- empty hex recess
    local v = hex_verts(cx, cy, r)
    cairo_move_to(cr, v[1][1], v[1][2])
    for i = 2, 6 do cairo_line_to(cr, v[i][1], v[i][2]) end
    cairo_close_path(cr)
    rgba(cr, BG_DEEP, 0.9)
    cairo_fill_preserve(cr)
    cairo_set_line_width(cr, 1.1 * S)
    rgba(cr, G_DIM, 0.8)
    cairo_stroke(cr)

    -- inner faint hex
    local iv = hex_verts(cx, cy, r * 0.72)
    cairo_move_to(cr, iv[1][1], iv[1][2])
    for i = 2, 6 do cairo_line_to(cr, iv[i][1], iv[i][2]) end
    cairo_close_path(cr)
    cairo_set_line_width(cr, 0.7 * S)
    rgba(cr, G_TRACE, 0.9)
    cairo_stroke(cr)

    -- progress arc along perimeter
    local c = valcol(frac)
    hex_perim(cr, cx, cy, r, frac)
    neon_path(cr, c, 2.6 * S)

    -- tick at current end
    local total = 6 * r
    local a = -math.pi / 2 + (frac * total / r) * (math.pi / 3)
    rgba(cr, G_BRIGHT, 1)
    cairo_arc(cr, cx + r * math.cos(a), cy + r * math.sin(a), 2.2 * S, 0, 2 * math.pi)
    cairo_fill(cr)

    -- value
    glow_text(cr, string.format('%.0f', frac * 100), cx, cy + 6 * S,
         F_MONO, 24 * S, c, 'center', CAIRO_FONT_WEIGHT_BOLD)
    text(cr, '%', cx, cy + 22 * S, F_MONO, 10 * S,
         CAIRO_FONT_WEIGHT_NORMAL, G_MID, 1, 'center')
    -- label + sub
    text(cr, label, cx, cy + r + 17 * S, F_MONO, 10.5 * S,
         CAIRO_FONT_WEIGHT_BOLD, G_MAIN, 1, 'center')
    if sub then
        text(cr, sub, cx, cy + r + 30 * S, F_MONO, 9 * S,
             CAIRO_FONT_WEIGHT_NORMAL, G_DIM, 1, 'center')
    end
end

-- ------------------------------------------------------------
--  OSCILLOSCOPE
-- ------------------------------------------------------------
local function draw_scope(cr, x, y, w, h)
    -- grid
    cairo_set_line_width(cr, 0.6 * S)
    rgba(cr, G_TRACE, 0.9)
    for i = 1, 7 do
        local gx = x + (w / 8) * i
        cairo_move_to(cr, gx, y + 3 * S); cairo_line_to(cr, gx, y + h - 3 * S)
    end
    for i = 1, 3 do
        local gy = y + (h / 4) * i
        cairo_move_to(cr, x + 3 * S, gy); cairo_line_to(cr, x + w - 3 * S, gy)
    end
    cairo_stroke(cr)

    -- waveform from net history
    local n = NHIST
    cairo_move_to(cr, x + 3 * S, y + h - 6 * S)
    for i = 1, n do
        local v = st.net_hist[i] / 100
        if v > 1 then v = 1 end
        local px = x + 3 * S + (w - 6 * S) * ((i - 1) / (n - 1))
        local py = y + h - 6 * S - (h - 12 * S) * v
        cairo_line_to(cr, px, py)
    end
    neon_path(cr, G_MAIN, 1.6 * S)

    -- scan blob at the head
    local hx = x + w - 3 * S
    local hv = st.net_hist[n] / 100
    if hv > 1 then hv = 1 end
    local hy = y + h - 6 * S - (h - 12 * S) * hv
    rgba(cr, G_BRIGHT, 0.9)
    cairo_arc(cr, hx, hy, 3 * S, 0, 2 * math.pi)
    cairo_fill(cr)
    rgba(cr, G_MAIN, 0.25)
    cairo_arc(cr, hx, hy, 8 * S, 0, 2 * math.pi)
    cairo_fill(cr)
end

-- ------------------------------------------------------------
--  EQUALIZER
-- ------------------------------------------------------------
local function draw_eq(cr, x, y, w, h)
    local n = CHIST
    local gap = 2 * S
    local bw = (w - gap * (n + 1)) / n
    for i = 1, n do
        local v = st.cpu_hist[i] / 100
        if v > 1 then v = 1 end
        local bx = x + gap + (i - 1) * (bw + gap)
        local bh = (h - 8 * S) * v
        local by = y + h - 4 * S - bh
        local c = valcol(v)
        -- track
        rgba(cr, G_TRACE, 0.7)
        cairo_rectangle(cr, bx, y + 4 * S, bw, h - 8 * S)
        cairo_fill(cr)
        -- bar with glow
        rgba(cr, c, 0.20)
        cairo_rectangle(cr, bx - 1, by - 1, bw + 2, bh + 2)
        cairo_fill(cr)
        rgba(cr, c, 0.95)
        cairo_rectangle(cr, bx, by, bw, bh)
        cairo_fill(cr)
        -- cap
        rgba(cr, G_BRIGHT, 0.95)
        cairo_rectangle(cr, bx, by, bw, 1.6 * S)
        cairo_fill(cr)
    end
end

-- ------------------------------------------------------------
--  RADAR
-- ------------------------------------------------------------
local function draw_radar(cr, cx, cy, r, up)
    -- rings
    cairo_set_line_width(cr, 0.8 * S)
    for i = 1, 3 do
        rgba(cr, G_TRACE, 0.95)
        cairo_arc(cr, cx, cy, r * (i / 3), 0, 2 * math.pi)
        cairo_stroke(cr)
    end
    rgba(cr, G_DIM, 0.5)
    cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
    cairo_stroke(cr)
    -- crosshair
    cairo_set_line_width(cr, 0.6 * S)
    rgba(cr, G_TRACE, 0.9)
    cairo_move_to(cr, cx - r, cy); cairo_line_to(cr, cx + r, cy)
    cairo_move_to(cr, cx, cy - r); cairo_line_to(cr, cx, cy + r)
    cairo_stroke(cr)

    -- sweep trail
    local ang = (up * 1.1) % (2 * math.pi)
    local trail = 46
    for i = 0, trail do
        local a = ang - i * 0.028
        local al = (1 - i / trail)
        rgba(cr, G_MAIN, al * al * 0.5)
        cairo_set_line_width(cr, 1.6 * S)
        cairo_move_to(cr, cx, cy)
        cairo_line_to(cr, cx + r * math.cos(a), cy + r * math.sin(a))
        cairo_stroke(cr)
    end
    -- leading edge
    rgba(cr, G_BRIGHT, 0.95)
    cairo_set_line_width(cr, 1.4 * S)
    cairo_move_to(cr, cx, cy)
    cairo_line_to(cr, cx + r * math.cos(ang), cy + r * math.sin(ang))
    cairo_stroke(cr)

    -- sweep advance this frame (for crossing detection)
    local swept = 0
    if st.sweep_prev ~= nil then
        swept = (ang - st.sweep_prev + 2 * math.pi) % (2 * math.pi)
    end
    st.sweep_prev = ang

    -- ADS-B tracks: real aircraft. A bright return lights up when the
    -- sweep crosses the aircraft's bearing, then decays with the trail.
    for h, t in pairs(st.adsb.tracks) do
        local dfrom = (ang - t.a + 2 * math.pi) % (2 * math.pi)
        local crossed = st.sweep_prev ~= nil and
            (dfrom <= swept + 0.25 or dfrom > 2 * math.pi - swept + 0.25)
        if crossed and (up - (t.ping or 0)) > 0.55 then
            t.ping = up
        end
        local age = up - (t.ping or 0)
        local ret = age < 1.2 and (1 - age / 1.2) or 0
        local px = cx + t.d * r * math.cos(t.a)
        local py = cy + t.d * r * math.sin(t.a)
        local c = adscol(t.alt)
        -- persistent faint track dot
        rgba(cr, c, 0.25)
        cairo_arc(cr, px, py, 1.6 * S, 0, 2 * math.pi)
        cairo_fill(cr)
        -- the radar return itself
        rgba(cr, c, 0.15 + 0.85 * ret)
        cairo_arc(cr, px, py, (1.6 + 2.6 * ret) * S, 0, 2 * math.pi)
        cairo_fill(cr)
        if ret > 0.25 then
            rgba(cr, c, 0.30 * ret)
            cairo_arc(cr, px, py, 5 * S, 0, 2 * math.pi)
            cairo_fill(cr)
        end
        -- callsign label on the freshly-lit return
        if ret > 0.55 and t.fl and t.fl ~= '-' then
            text(cr, t.fl, px, py - 6 * S, F_MONO, 6.5 * S,
                 CAIRO_FONT_WEIGHT_BOLD, c, 0.95, 'center')
        end
    end

    -- blips
    for _, b in ipairs(st.blips) do
        local d = (up - b.t) / b.life
        if d >= 0 and d < 1 then
            local al = math.sin(d * math.pi)
            local bx = cx + b.d * r * math.cos(b.a)
            local by = cy + b.d * r * math.sin(b.a)
            rgba(cr, G_BRIGHT, al)
            cairo_arc(cr, bx, by, 2.4 * S, 0, 2 * math.pi)
            cairo_fill(cr)
            rgba(cr, G_MAIN, al * 0.4)
            cairo_arc(cr, bx, by, 5 * S, 0, 2 * math.pi)
            cairo_fill(cr)
        end
    end
    -- spawn blips occasionally
    if math.random() < 0.06 then
        st.blips[#st.blips + 1] = {
            a = math.random() * 2 * math.pi,
            d = 0.25 + math.random() * 0.7,
            t = up,
            life = 1.6 + math.random() * 1.8,
        }
    end
    while #st.blips > 8 do table.remove(st.blips, 1) end
end

-- ------------------------------------------------------------
--  DATA COLLECTION
-- ------------------------------------------------------------
local function read_net(now)
    local s = readfile('/proc/net/dev')
    if not s then return end
    local rx, tx = 0, 0
    for line in s:gmatch('[^\n]+') do
        local iface, rest = line:match('^%s*(%w+):%s*(.+)$')
        if iface and iface ~= 'lo' then
            local r = tonumber(rest:match('^(%d+)')) or 0
            local parts = {}
            for num in rest:gmatch('%d+') do parts[#parts + 1] = tonumber(num) end
            local t = parts[9] or 0
            rx = rx + r
            tx = tx + t
        end
    end
    if st.net.t > 0 then
        local dt = now - st.net.t
        if dt > 0 then
            local dn = (rx - st.net.rx) / dt / 1024
            local up = (tx - st.net.tx) / dt / 1024
            if dn < 0 then dn = 0 end
            if up < 0 then up = 0 end
            st.net.dn = st.net.dn * 0.7 + dn * 0.3
            st.net.up = st.net.up * 0.7 + up * 0.3
        end
    end
    st.net.rx, st.net.tx, st.net.t = rx, tx, now
end

local function read_cores()
    local s = readfile('/proc/stat')
    if not s then return end
    local cur = {}
    for line in s:gmatch('[^\n]+') do
        local id = line:match('^cpu(%d+)%s+')
        if id then
            local nums = {}
            for n in line:gmatch('%d+') do nums[#nums + 1] = tonumber(n) end
            -- nums[1..] are user..steal (id itself not captured as number here)
            local total, idle = 0, 0
            for i = 1, #nums do total = total + nums[i] end
            idle = (nums[4] or 0) + (nums[5] or 0) -- idle + iowait
            cur[tonumber(id) + 1] = { total = total, idle = idle }
        end
    end
    if st.prev_cores then
        local load = {}
        for i = 1, #cur do
            local a, b = st.prev_cores[i], cur[i]
            if a and b then
                local dt = b.total - a.total
                local di = b.idle - a.idle
                load[i] = (dt > 0) and (1 - di / dt) or 0
            else
                load[i] = 0
            end
        end
        st.cores = load
    end
    st.prev_cores = cur
end

local function read_temp()
    local s = readfile('/sys/class/thermal/thermal_zone0/temp')
    if s then
        local t = tonumber(s)
        if t and t > 1000 then return t / 1000 end
    end
    return nil
end

local function read_playing()
    local s = readfile(os.getenv('HOME') .. '/.cache/conky/pianobar-widget.status')
    if not s then return nil end
    local title, artist, album, dur, pos, state =
        s:match('^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)')
    if not title or title == '' then return nil end
    return { title = title, artist = artist or '', state = state or '' }
end

-- ------------------------------------------------------------
--  ADS-B / LIVE RADAR  (feeds ~/.cache/conky/cyberdeck-adsb.status)
-- ------------------------------------------------------------
local ADSB_RANGE = 55.0    -- nm mapped to the radar rim (matches the poller)
local ADSB_FILE = os.getenv('HOME') .. '/.cache/conky/cyberdeck-adsb.status'
local ADSB_STALE = 30      -- seconds before we call the link dead

local function read_adsb()
    local s = readfile(ADSB_FILE)
    st.adsb.link = false
    if not s then return end
    local ts, n, seen = nil, 0, {}
    for line in s:gmatch('[^\n]+') do
        local b = line:match('^TS +(%S+)')
        if b then ts = tonumber(b) end
        local h, brg, dist, alt, gs, fl, typ =
            line:match('^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)')
        if h and h ~= 'TS' and h ~= 'N' then
            seen[h] = true
            local t = st.adsb.tracks[h] or { ping = 0 }
            t.a = ((tonumber(brg) or 0) - 90) * math.pi / 180
            t.d = math.min(1, (tonumber(dist) or 0) / ADSB_RANGE)
            t.alt = tonumber(alt) or 0
            t.gs = tonumber(gs) or 0
            t.fl = fl or '-'
            t.typ = typ or '-'
            st.adsb.tracks[h] = t
            n = n + 1
        end
    end
    for h in pairs(st.adsb.tracks) do
        if not seen[h] then st.adsb.tracks[h] = nil end
    end
    st.adsb.n = n
    st.adsb.link = ts ~= nil and (os.time() - ts) < ADSB_STALE
end

-- ------------------------------------------------------------
--  MAIN
-- ------------------------------------------------------------
function conky_main()
    if conky_window == nil then return end
    local w, h = conky_window.width, conky_window.height
    if w == nil or h == nil or w < 8 or h < 8 then return end

    S = math.max(0.01, math.min(w / GRID_W, h / GRID_H))
    if not st.init then
        math.randomseed(os.time())
        init_rain()
        st.prev_up = uptime()
        st.init = true
    end

    local up = uptime()
    local dt = up - (st.prev_up or up)
    if dt < 0 or dt > 1 then dt = 0.1 end
    st.prev_up = up

    -- glitch scheduling
    if up > st.next_glitch and up > st.glitch_until then
        st.glitch_until = up + 0.12 + math.random() * 0.18
        st.next_glitch = up + 3 + math.random() * 6
    end

    read_net(up)
    read_cores()
    if up - st.adsb.t > 1 then
        read_adsb()
        st.adsb.t = up
    end

    -- histories
    do
        local cpu = tonumber(conky_parse('${cpu}')) or 0
        table.remove(st.cpu_hist, 1)
        st.cpu_hist[CHIST] = cpu
        local netload = math.min(100, (st.net.dn + st.net.up) * 2)
        table.remove(st.net_hist, 1)
        st.net_hist[NHIST] = netload
    end

    local surface = cairo_xlib_surface_create(conky_window.display,
        conky_window.drawable, conky_window.visual, w, h)
    local cr = cairo_create(surface)

    -- background
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
    rgba(cr, BG_DEEP, 0)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

    -- clip everything to the frame
    chamfer_path(cr, 6 * S, 6 * S, (GRID_W - 12) * S, (GRID_H - 12) * S, 16 * S)
    cairo_clip(cr)

    -- deep plate
    chamfer_path(cr, 6 * S, 6 * S, (GRID_W - 12) * S, (GRID_H - 12) * S, 16 * S)
    rgba(cr, BG_PANEL, 0.55)
    cairo_fill(cr)

    draw_rain(cr, dt)

    -- outer neon frame
    chamfer_path(cr, 6 * S, 6 * S, (GRID_W - 12) * S, (GRID_H - 12) * S, 16 * S)
    neon_path(cr, G_MAIN, 1.7 * S)
    chamfer_path(cr, 10 * S, 10 * S, (GRID_W - 20) * S, (GRID_H - 20) * S, 13 * S)
    cairo_set_line_width(cr, 0.7 * S)
    rgba(cr, G_DIM, 0.7)
    cairo_stroke(cr)

    -- ============ HEADER ============
    glow_text(cr, 'CYBERDECK', 22 * S, 58 * S, F_TITLE, 24 * S,
         G_MAIN, 'left')
    text(cr, '// SYS.MON  v2.077', 23 * S, 78 * S, F_MONO, 9 * S,
         CAIRO_FONT_WEIGHT_NORMAL, G_DIM, 1, 'left')

    local hhmmss = os.date('%H:%M:%S')
    draw_clock(cr, hhmmss, 262 * S, 60 * S, 27 * S, up)
    text(cr, os.date('%a %d %b %Y'):upper(), 322 * S, 82 * S, F_MONO, 9.5 * S,
         CAIRO_FONT_WEIGHT_BOLD, G_MID, 1, 'right')

    -- header LEDs
    local leds = {
        { 'PWR', true }, { 'NET', st.net.dn + st.net.up > 1 },
        { 'CPU', (tonumber(conky_parse('${cpu}')) or 0) > 40 }, { 'OK', true },
    }
    local lx = 23 * S
    for _, l in ipairs(leds) do
        rgba(cr, l[2] and G_BRIGHT or G_FAINT, l[2] and 1 or 0.8)
        cairo_arc(cr, lx, 92 * S, 2.6 * S, 0, 2 * math.pi)
        cairo_fill(cr)
        text(cr, l[1], lx + 6 * S, 95 * S, F_MONO, 8 * S,
             CAIRO_FONT_WEIGHT_NORMAL, l[2] and G_MID or G_FAINT, 1, 'left')
        lx = lx + 34 * S
    end
    nline(cr, 18 * S, 106 * S, 322 * S, 106 * S, G_TRACE, 1.0 * S, 0.9)

    -- ============ HEX GAUGES ============
    local mem = tonumber(conky_parse('${memperc}')) or 0
    local disk = tonumber(conky_parse('${fs_used_perc /}')) or 0
    local cpu = tonumber(conky_parse('${cpu}')) or 0
    hex_gauge(cr, 72 * S, 200 * S, 50 * S, cpu / 100, 'CPU', cpu,
        string.format('%.0f%%', cpu))
    hex_gauge(cr, 170 * S, 200 * S, 50 * S, mem / 100, 'MEM', mem,
        string.format('%.0f%%', mem))
    hex_gauge(cr, 268 * S, 200 * S, 50 * S, disk / 100, 'DISK', disk,
        string.format('%.0f%%', disk))

    -- ============ SCOPE ============
    panel(cr, 18 * S, 286 * S, 304 * S, 88 * S, 10 * S, 'NET.SCOPE')
    local dn = st.net.dn; local upx = st.net.up
    text(cr, string.format('DN %6.1f KB/S', dn), 26 * S, 316 * S, F_MONO, 9.5 * S,
         CAIRO_FONT_WEIGHT_BOLD, G_MAIN, 1, 'left')
    text(cr, string.format('UP %6.1f KB/S', upx), 178 * S, 316 * S, F_MONO, 9.5 * S,
         CAIRO_FONT_WEIGHT_BOLD, G_MID, 1, 'left')
    draw_scope(cr, 24 * S, 328 * S, 292 * S, 46 * S)

    -- ============ EQUALIZER ============
    panel(cr, 18 * S, 380 * S, 304 * S, 90 * S, 10 * S, 'CORE.LOAD')
    draw_eq(cr, 26 * S, 398 * S, 288 * S, 66 * S)

    -- ============ TELEMETRY ============
    panel(cr, 18 * S, 478 * S, 304 * S, 160 * S, 10 * S, 'TELEMETRY')
    local ty = 510 * S
    local function row(lbl, val, c)
        text(cr, lbl, 28 * S, ty, F_MONO, 11 * S,
             CAIRO_FONT_WEIGHT_NORMAL, G_DIM, 1, 'left')
        text(cr, val, 312 * S, ty, F_MONO, 12 * S,
             CAIRO_FONT_WEIGHT_BOLD, c or G_MAIN, 1, 'right')
        ty = ty + 19 * S
    end
    local temp = read_temp()
    row('CORE.TEMP', temp and string.format('%.1f C', temp) or '--.- C',
        temp and (temp > 70 and RED or G_MAIN) or G_DIM)
    local ut = math.floor(up)
    row('UPTIME', string.format('%dd %02dh %02dm',
        math.floor(ut / 86400), math.floor(ut % 86400 / 3600),
        math.floor(ut % 3600 / 60)))
    row('PROC', conky_parse('${processes}') .. ' / ' .. conky_parse('${running_processes}'))
    row('LOAD', conky_parse('${loadavg}'):match('^%S+ %S+ %S+') or '--')
    row('FREQ', (conky_parse('${freq_g}') or '--') .. ' GHz')
    if st.cores then
        local cy = 600 * S
        text(cr, 'CORES', 28 * S, cy, F_MONO, 11 * S,
             CAIRO_FONT_WEIGHT_NORMAL, G_DIM, 1, 'left')
        local n = #st.cores
        local bw = (284 * S) / n
        for i = 1, n do
            local v = st.cores[i] or 0
            local bx = 28 * S + (i - 1) * bw
            rgba(cr, G_TRACE, 0.8)
            cairo_rectangle(cr, bx, cy + 6 * S, bw - 3 * S, 26 * S)
            cairo_fill(cr)
            local c = valcol(v)
            rgba(cr, c, 0.95)
            cairo_rectangle(cr, bx, cy + 6 * S + (26 * S) * (1 - v),
                            bw - 3 * S, (26 * S) * v)
            cairo_fill(cr)
            text(cr, tostring(i - 1), bx + (bw - 3 * S) / 2, cy + 25 * S,
                 F_MONO, 9 * S, CAIRO_FONT_WEIGHT_NORMAL, G_MID, 1, 'center')
        end
    end

    -- ============ NOW PLAYING ============
    panel(cr, 18 * S, 646 * S, 304 * S, 38 * S, 8 * S, 'NOW.PLAYING')
    local np = read_playing()
    local npx = 26 * S
    local npw = 288 * S
    cairo_save(cr)
    cairo_rectangle(cr, npx, 654 * S, npw, 26 * S)
    cairo_clip(cr)
    if np then
        local str = '\226\150\182 ' .. np.title .. '  \226\128\148  ' .. np.artist
        cairo_select_font_face(cr, F_UI, CAIRO_FONT_SLANT_NORMAL,
            CAIRO_FONT_WEIGHT_BOLD)
        cairo_set_font_size(cr, 11 * S)
        local ext = cairo_text_extents_t:create()
        cairo_text_extents(cr, str, ext)
        local tw = ext.width
        st.scroll = st.scroll + 0.9 * S
        if st.scroll > tw + 20 * S then st.scroll = 0 end
        rgba(cr, G_MAIN, 0.95)
        cairo_move_to(cr, npx + npw - st.scroll, 670 * S)
        cairo_show_text(cr, str)
        -- second copy for seamless wrap
        cairo_move_to(cr, npx + npw - st.scroll + tw + 40 * S, 670 * S)
        cairo_show_text(cr, str)
    else
        text(cr, '// NO SIGNAL', npx, 670 * S, F_MONO, 10 * S,
             CAIRO_FONT_WEIGHT_NORMAL, G_DIM, 0.7, 'left')
    end
    cairo_restore(cr)

    -- ============ PROCESSES ============
    panel(cr, 18 * S, 690 * S, 304 * S, 180 * S, 10 * S, 'PROC.TOP')
    local py = 716 * S
    for i = 1, 6 do
        local name = conky_parse('${top name ' .. i .. '}')
        local pcpu = conky_parse('${top cpu ' .. i .. '}')
        local pmem = conky_parse('${top mem ' .. i .. '}')
        if name and name ~= '' then
            local c = valcol((tonumber(pcpu) or 0) / 100)
            text(cr, string.format('%d', i), 26 * S, py, F_MONO, 9 * S,
                 CAIRO_FONT_WEIGHT_NORMAL, G_DIM, 1, 'left')
            text(cr, name, 38 * S, py, F_MONO, 9.5 * S,
                 CAIRO_FONT_WEIGHT_BOLD, G_MAIN, 1, 'left')
            text(cr, string.format('%5.1f%%', tonumber(pcpu) or 0), 252 * S, py,
                 F_MONO, 9.5 * S, CAIRO_FONT_WEIGHT_BOLD, c, 1, 'right')
            text(cr, string.format('%5.1f%%', tonumber(pmem) or 0), 312 * S, py,
                 F_MONO, 9.5 * S, CAIRO_FONT_WEIGHT_NORMAL, G_MID, 1, 'right')
        end
        py = py + 18 * S
    end

    -- ============ CRT FX ============
    -- scanlines
    cairo_set_line_width(cr, 1.0)
    rgba(cr, BG_DEEP, 0.16)
    for y = 8 * S, (GRID_H - 8) * S, 3 do
        cairo_move_to(cr, 6 * S, y)
        cairo_line_to(cr, (GRID_W - 6) * S, y)
    end
    cairo_stroke(cr)

    -- vignette top/bottom
    local vg = cairo_pattern_create_linear(0, 0, 0, GRID_H * S)
    cairo_pattern_add_color_stop_rgba(vg, 0.0, 0, 0, 0, 0.45)
    cairo_pattern_add_color_stop_rgba(vg, 0.12, 0, 0, 0, 0.0)
    cairo_pattern_add_color_stop_rgba(vg, 0.88, 0, 0, 0, 0.0)
    cairo_pattern_add_color_stop_rgba(vg, 1.0, 0, 0, 0, 0.5)
    cairo_set_source(cr, vg)
    cairo_paint(cr)
    cairo_pattern_destroy(vg)

    cairo_destroy(cr)
    cairo_surface_destroy(surface)
end

-- ------------------------------------------------------------
--  ADS-B LINK MANAGER  (one-shot, pgrep-guarded)
--  A/B are re-joined INSIDE the shell so the literal filename
--  never appears on the spawning shell's command line (pgrep
--  would otherwise self-match the sh -c owned by os.execute).
-- ------------------------------------------------------------
local function spawn_adsb_link()
    local home = os.getenv('HOME') or '.'
    os.execute('A="' .. home .. '/.conky/cyberdeck/scripts/adsb"; B="_radar.py"; '
        .. 'if ! pgrep -f "adsb_radar.p[y]" >/dev/null 2>&1; then '
        .. 'setsid python3 "$A$B" </dev/null >/dev/null 2>&1 & fi')
end
spawn_adsb_link()
