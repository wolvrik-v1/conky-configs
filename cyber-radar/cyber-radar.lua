-- ============================================================
--  ADSB RADAR  //  companion scope for Conky 1.12 (Lua/Cairo)
--  Shows live ADS-B aircraft around Pittsburgh Intl (KPIT).
--  Fully procedural. No image assets. Shares the status file
--  written by ~/.config/conky/adsb_radar.py.
-- ============================================================

require 'cairo'

-- ------------------------------------------------------------
--  DESIGN GRID
-- ------------------------------------------------------------
local GRID_W, GRID_H = 360, 400
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

local F_TITLE = 'SAIBA-45'
local F_MONO  = 'DejaVu Sans Mono'

-- ------------------------------------------------------------
--  STATE
-- ------------------------------------------------------------
local st = {
    up = 0,
    sweep_prev = nil,
    blips = {},
    adsb = { tracks = {}, t = 0, n = 0, link = false },
}
local ADSB_RANGE = 55.0     -- nm mapped to the radar rim (matches the poller)
local ADSB_FILE = os.getenv('HOME') .. '/.cache/conky/cyber-adsb.status'
local ADSB_STALE = 30      -- seconds before we call the link dead
local CENTER = 'KPIT 40.49N 080.14W'

-- ------------------------------------------------------------
--  HELPERS
-- ------------------------------------------------------------
local function readfile(p)
    local f = io.open(p, 'r')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

local function uptime()
    return tonumber((readfile('/proc/uptime') or ''):match('^(%S+)')) or os.time()
end

local function rgba(cr, c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or 1)
end

-- ADS-B return colour by altitude band
local function adscol(alt)
    if alt < 10000 then return G_MAIN end
    if alt < 28000 then return CYAN end
    return AMBER
end

-- text drawing with optional alignment + shadow
local function text(cr, s, x, y, fam, size, weight, c, a, align)
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
    rgba(cr, BG_DEEP, (a or 1) * 0.85)
    cairo_move_to(cr, tx + size * 0.06, y + size * 0.06)
    cairo_show_text(cr, s)
    rgba(cr, c, a or 1)
    cairo_move_to(cr, tx, y)
    cairo_show_text(cr, s)
    return ext
end

local function mix(c1, c2, t)
    return { c1[1] + (c2[1] - c1[1]) * t,
             c1[2] + (c2[2] - c1[2]) * t,
             c1[3] + (c2[3] - c1[3]) * t }
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

-- emissive text: glyphs as a path, stroked with bloom layers then filled hot.
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

-- ------------------------------------------------------------
--  ADS-B DATA READ
-- ------------------------------------------------------------
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
--  RADAR SCOPE  (cx, cy, r in px)
-- ------------------------------------------------------------
local function draw_radar(cr, cx, cy, r, up)
    -- recessed well
    rgba(cr, G_TRACE, 0.5)
    cairo_arc(cr, cx, cy, r + 5 * S, 0, 2 * math.pi)
    cairo_fill(cr)

    -- rings
    cairo_set_line_width(cr, 0.8 * S)
    for i = 1, 4 do
        rgba(cr, G_TRACE, 0.95)
        cairo_arc(cr, cx, cy, r * (i / 4), 0, 2 * math.pi)
        cairo_stroke(cr)
    end
    rgba(cr, G_DIM, 0.5)
    cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
    cairo_stroke(cr)

    -- crosshair + bearing ticks
    cairo_set_line_width(cr, 0.6 * S)
    rgba(cr, G_TRACE, 0.9)
    cairo_move_to(cr, cx - r, cy); cairo_line_to(cr, cx + r, cy)
    cairo_move_to(cr, cx, cy - r); cairo_line_to(cr, cx, cy + r)
    cairo_stroke(cr)
    for i = 1, 72 do
        local a = i * math.pi / 36
        local ro, ri = r, r - (i % 6 == 0 and 5 * S or 2.6 * S)
        rgba(cr, G_DIM, i % 6 == 0 and 0.9 or 0.55)
        cairo_set_line_width(cr, 0.7 * S)
        cairo_move_to(cr, cx + ri * math.cos(a), cy + ri * math.sin(a))
        cairo_line_to(cr, cx + ro * math.cos(a), cy + ro * math.sin(a))
        cairo_stroke(cr)
    end

    -- cardinal labels
    text(cr, 'N', cx, cy - r + 13 * S, F_MONO, 7 * S,
         CAIRO_FONT_WEIGHT_BOLD, G_MID, 0.9, 'center')
    text(cr, 'E', cx + r - 13 * S, cy + 2.5 * S, F_MONO, 7 * S,
         CAIRO_FONT_WEIGHT_BOLD, G_MID, 0.9, 'center')
    text(cr, 'S', cx, cy + r - 4 * S, F_MONO, 7 * S,
         CAIRO_FONT_WEIGHT_BOLD, G_MID, 0.9, 'center')
    text(cr, 'W', cx - r + 13 * S, cy + 2.5 * S, F_MONO, 7 * S,
         CAIRO_FONT_WEIGHT_BOLD, G_MID, 0.9, 'center')

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
--  MAIN
-- ------------------------------------------------------------
function conky_main()
    if conky_window == nil then return end
    local w, h = conky_window.width, conky_window.height
    if w == nil or h == nil or w < 8 or h < 8 then return end

    S = math.max(0.01, math.min(w / GRID_W, h / GRID_H))
    if st.up == 0 then
        math.randomseed(os.time())
        st.up = uptime()
    end
    local up = uptime()
    st.up = up

    if up - st.adsb.t > 1 then
        read_adsb()
        st.adsb.t = up
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

    -- outer neon frame
    chamfer_path(cr, 6 * S, 6 * S, (GRID_W - 12) * S, (GRID_H - 12) * S, 16 * S)
    neon_path(cr, G_MAIN, 1.7 * S)
    chamfer_path(cr, 10 * S, 10 * S, (GRID_W - 20) * S, (GRID_H - 20) * S, 13 * S)
    cairo_set_line_width(cr, 0.7 * S)
    rgba(cr, G_DIM, 0.7)
    cairo_stroke(cr)

    -- ============ HEADER ============
    glow_text(cr, 'ADSB RADAR', 24 * S, 40 * S, F_TITLE, 22 * S, G_MAIN, 'left')
    text(cr, CENTER, 336 * S, 42 * S, F_MONO, 8 * S,
         CAIRO_FONT_WEIGHT_NORMAL, G_DIM, 0.9, 'right')
    -- divider
    cairo_set_line_width(cr, 0.8 * S)
    rgba(cr, G_DIM, 0.6)
    cairo_move_to(cr, 24 * S, 54 * S); cairo_line_to(cr, (GRID_W - 24) * S, 54 * S)
    cairo_stroke(cr)

    -- ============ SCOPE ============
    local cx, cy, rr = (GRID_W / 2) * S, 214 * S, 128 * S
    draw_radar(cr, cx, cy, rr, up)

    -- ============ FOOTER ============
    if st.adsb.link then
        text(cr, string.format('ADSB %d TRK // RANGE 55NM', st.adsb.n), cx, 372 * S,
             F_MONO, 9 * S, CAIRO_FONT_WEIGHT_BOLD, G_MID, 0.95, 'center')
    else
        text(cr, 'ADSB //LINK DWN', cx, 372 * S, F_MONO, 9 * S,
             CAIRO_FONT_WEIGHT_BOLD, RED, 0.95, 'center')
    end

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
    os.execute('A="' .. home .. '/.conky/cyber-radar/scripts/adsb"; B="_radar.py"; '
        .. 'if ! pgrep -f "adsb_radar.p[y]" >/dev/null 2>&1; then '
        .. 'setsid python3 "$A$B" </dev/null >>/tmp/adsb_daemon.log 2>&1 & fi')
end
spawn_adsb_link()