-- ============================================================================
--  CLOCKWORK ALCHEMIST
--  A steampunk-inspired, fully procedural Lua/Cairo spectacle for Conky.
--  Meshing gear train visible through a skeleton watch dial, brass bevels,
--  pressure gauges, a mercury thermometer and a live steam boiler.
--  Grid: 352x940  (all geometry is authored in grid units, scaled by S)
-- ============================================================================

require 'cairo'

local GRID_W, GRID_H = 352, 940
local S = 1.0   -- scale factor, set in conky_main()

-- ---------------------------------------------------------------------------
--  PALETTE (RGB 0..255 tables)
-- ---------------------------------------------------------------------------
local B1 = {0.86, 0.64, 0.30}  -- bright brass
local B2 = {0.72, 0.52, 0.24}  -- mid brass
local B3 = {0.53, 0.37, 0.15}  -- dark brass
local B4 = {0.38, 0.26, 0.11}  -- darkest brass
local C1 = {0.82, 0.54, 0.30}  -- copper light
local C2 = {0.62, 0.37, 0.19}  -- copper mid
local C3 = {0.44, 0.26, 0.13}  -- copper dark
local S0 = {0.09, 0.09, 0.10}  -- steel near-black
local S1 = {0.22, 0.22, 0.24}  -- steel panel
local S2 = {0.43, 0.43, 0.47}  -- steel mid
local S3 = {0.64, 0.64, 0.68}  -- steel bright
local DIAL = {0.070, 0.065, 0.060}
local DIALHI = {0.13, 0.125, 0.115}
local CRIM = {0.85, 0.16, 0.13}
local GLOW = {1.0, 0.30, 0.22}
local MERC = {0.78, 0.80, 0.86}
local MERCHI = {0.92, 0.94, 0.98}
local AMBER = {0.78, 0.53, 0.20}
local TXT = {0.93, 0.88, 0.76}
local TXTDIM = {0.60, 0.53, 0.42}

-- ---------------------------------------------------------------------------
--  COLOR / SHAPE HELPERS
-- ---------------------------------------------------------------------------
local function setc(cr, c, a) cairo_set_source_rgba(cr, c[1], c[2], c[3], a or 1) end

local function rrect(cr, x, y, w, h, r)
    r = math.min(r, w / 2, h / 2)
    cairo_new_path(cr)
    cairo_move_to(cr, x + r, y)
    cairo_line_to(cr, x + w - r, y)
    cairo_arc(cr, x + w - r, y + r, r, -math.pi / 2, 0)
    cairo_line_to(cr, x + w, y + h - r)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_line_to(cr, x + r, y + h)
    cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
    cairo_line_to(cr, x, y + r)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cairo_close_path(cr)
end

local FS = 'DejaVu Sans'
local FM = 'DejaVu Sans Mono'

local function text_at(cr, x, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    setc(cr, col, 1)
    cairo_select_font_face(cr, mono and FM or FS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, str)
end

local function text_cx(cr, cx, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    setc(cr, col, 1)
    cairo_select_font_face(cr, mono and FM or FS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, str, ext)
    cairo_move_to(cr, cx - (ext.width / 2 + ext.x_bearing), y)
    cairo_show_text(cr, str)
end

local function text_ri(cr, right, y, str, col, size, mono, bold)
    if not str or str == '' then return end
    setc(cr, col, 1)
    cairo_select_font_face(cr, mono and FM or FS,
                           CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size * S)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, str, ext)
    cairo_move_to(cr, right - (ext.width + ext.x_bearing), y)
    cairo_show_text(cr, str)
end

local RAD = math.pi / 180

-- ---------------------------------------------------------------------------
--  METRIC READERS (all self-contained; no dependence on a specific iface)
-- ---------------------------------------------------------------------------
local function read_cpu()
    return tonumber(conky_parse('${cpu}') or '0') or 0
end

local function read_mem()
    return tonumber(conky_parse('${memperc}') or '0') or 0
end

local function read_temp()
    local f = io.open('/sys/class/thermal/thermal_zone0/temp', 'r')
    if f then
        local v = f:read('*l'); f:close()
        return tonumber(v) and tonumber(v) / 1000 or 0
    end
    return 0
end

local function read_load()
    local s = conky_parse('${loadavg}')
    local a, b, c = s:match('(%S+)%s+(%S+)%s+(%S+)')
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function read_uptime()
    local f = io.open('/proc/uptime', 'r')
    if f then
        local v = f:read('*l'); f:close()
        local t = tonumber(v:match('%S+')) or 0
        local hh = math.floor(t / 3600)
        local mm = math.floor((t % 3600) / 60)
        local ss = math.floor(t % 60)
        return string.format('%02d:%02d:%02d', hh, mm, ss)
    end
    return '00:00:00'
end

-- network: /proc/net/dev summed over non-loopback interfaces, EMA smoothed
local net_prev_up, net_prev_dn = nil, nil
local net_up_s, net_dn_s = 0, 0
local function read_net(dt)
    local up, dn = 0, 0
    for line in io.lines('/proc/net/dev') do
        local name, rest = line:match('^%s*([%w]+):%s*(.*)')
        if name and name ~= 'lo' then
            local rxb, txb = rest:match('(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)')
            if rxb and txb then dn = dn + tonumber(rxb); up = up + tonumber(txb) end
        end
    end
    if net_prev_up then
        local dup = (up - net_prev_up) / math.max(dt, 0.001)
        local ddn = (dn - net_prev_dn) / math.max(dt, 0.001)
        net_up_s = net_up_s * 0.85 + dup * 0.15
        net_dn_s = net_dn_s * 0.85 + ddn * 0.15
    end
    net_prev_up, net_prev_dn = up, dn
    return net_up_s / 1024, net_dn_s / 1024   -- KB/s
end

-- ---------------------------------------------------------------------------
--  DECORATIVE SCAFFOLDING
-- ---------------------------------------------------------------------------
local function rivet(cr, x, y, r)
    local g = cairo_pattern_create_radial(x - r * 0.35, y - r * 0.4, r * 0.2,
                                          x, y, r)
    cairo_pattern_add_color_stop_rgb(g, 0.0, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(g, 0.55, B2[1], B2[2], B2[3])
    cairo_pattern_add_color_stop_rgb(g, 1.0, B4[1], B4[2], B4[3])
    cairo_arc(cr, x, y, r, 0, 2 * math.pi)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)
    cairo_arc(cr, x - r * 0.3, y - r * 0.35, r * 0.28, 0, 2 * math.pi)
    setc(cr, TXT, 0.55)
    cairo_fill(cr)
end

local function rail(cr, y)
    local g = cairo_pattern_create_linear(0, y - 4, 0, y + 4)
    cairo_pattern_add_color_stop_rgb(g, 0.0, B3[1], B3[2], B3[3])
    cairo_pattern_add_color_stop_rgb(g, 0.5, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(g, 1.0, B4[1], B4[2], B4[3])
    rrect(cr, 16 * S, (y - 3) * S, 320 * S, 6 * S, 3 * S)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)
    rivet(cr, 176 * S, y * S, 4 * S)
    rivet(cr, 76 * S, y * S, 3 * S)
    rivet(cr, 276 * S, y * S, 3 * S)
end

-- steel backplate with a machined dome + faint face-turning rings
local function draw_plate(cr, w, h)
    local g = cairo_pattern_create_radial(w * 0.5, h * 0.28, 10,
                                          w * 0.5, h * 0.5, h * 0.72)
    cairo_pattern_add_color_stop_rgb(g, 0.0, 0.20, 0.20, 0.215)
    cairo_pattern_add_color_stop_rgb(g, 0.55, 0.155, 0.155, 0.165)
    cairo_pattern_add_color_stop_rgb(g, 1.0, 0.10, 0.10, 0.11)
    cairo_rectangle(cr, 0, 0, w, h)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)

    setc(cr, S3, 0.05)
    cairo_set_line_width(cr, 0.4)
    for r = 60 * S, w, 90 * S do
        cairo_arc(cr, w / 2, h * 0.3, r, 0, 2 * math.pi)
        cairo_stroke(cr)
    end
end

-- brass external frame with bevel + corner rivets
local function draw_frame(cr, w, h)
    local g = cairo_pattern_create_linear(0, 0, w, h)
    cairo_pattern_add_color_stop_rgb(g, 0.0, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(g, 0.5, B2[1], B2[2], B2[3])
    cairo_pattern_add_color_stop_rgb(g, 1.0, B4[1], B4[2], B4[3])
    cairo_rectangle(cr, 0, 0, w, 8 * S)
    cairo_rectangle(cr, 0, h - 8 * S, w, 8 * S)
    cairo_rectangle(cr, 0, 0, 8 * S, h)
    cairo_rectangle(cr, w - 8 * S, 0, 8 * S, h)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)

    cairo_set_line_width(cr, 1)
    setc(cr, TXT, 0.22)
    cairo_rectangle(cr, 0.5, 0.5, w - 1, h - 1)
    cairo_stroke(cr)
    setc(cr, S0, 0.6)
    cairo_rectangle(cr, 3.5 * S, 3.5 * S, w - 7 * S, h - 7 * S)
    cairo_stroke(cr)

    rivet(cr, 16 * S, 16 * S, 4.5 * S)
    rivet(cr, (GRID_W - 16) * S, 16 * S, 4.5 * S)
    rivet(cr, 16 * S, (GRID_H - 23) * S, 4.5 * S)
    rivet(cr, (GRID_W - 16) * S, (GRID_H - 23) * S, 4.5 * S)
    rivet(cr, (GRID_W / 2) * S, 16 * S, 4 * S)
    rivet(cr, (GRID_W / 2) * S, (GRID_H - 23) * S, 4 * S)
end

-- ---------------------------------------------------------------------------
--  GEARS  (procedural, meshing at true tooth ratios)
-- ---------------------------------------------------------------------------
-- Append a single closed silhouette for an N-tooth gear (teeth + root ring).
local function gear_path(cr, N, Ro, Rr)
    local ta = 2 * math.pi / N
    local tw, tt = ta * 0.42, ta * 0.28
    cairo_new_path(cr)
    for i = 0, N - 1 do
        local b = i * ta
        local g0, t1, p2 = b - ta / 2, b - tw / 2, b - tt / 2
        local p3, t4, g5 = b + tt / 2, b + tw / 2, b + ta / 2
        if i == 0 then cairo_move_to(cr, Rr * math.cos(g0), Rr * math.sin(g0)) end
        cairo_line_to(cr, Rr * math.cos(t1), Rr * math.sin(t1))
        cairo_line_to(cr, Ro * math.cos(p2), Ro * math.sin(p2))
        cairo_line_to(cr, Ro * math.cos(p3), Ro * math.sin(p3))
        cairo_line_to(cr, Rr * math.cos(t4), Rr * math.sin(t4))
        cairo_line_to(cr, Rr * math.cos(g5), Rr * math.sin(g5))
    end
    cairo_close_path(cr)
end

-- add cutout circles (hub + lightening holes) for even-odd fill
local function gear_holes(cr, N, Ro, Rr, hub)
    cairo_arc(cr, 0, 0, hub, 0, 2 * math.pi)
    local holes = 6
    local hc = (Ro + Rr) * 0.46
    local hr = (Ro - Rr) * 0.62
    for i = 0, holes - 1 do
        local a = i * 2 * math.pi / holes + math.pi / (holes * 2)
        cairo_arc(cr, hc * math.cos(a), hc * math.sin(a), hr, 0, 2 * math.pi)
    end
end

-- draw one gear. ang in radians. tone 'brass' | 'steel'
local function draw_gear(cr, cx, cy, N, Ro, Rr, hub, ang, tone)
    local s = S
    cairo_save(cr)
    cairo_translate(cr, cx * s, cy * s)
    cairo_rotate(cr, ang)

    -- drop shadow
    gear_path(cr, N, Ro, Rr)
    cairo_translate(cr, 0, 2.4 * s)
    setc(cr, S0, 0.45)
    cairo_fill(cr)
    cairo_translate(cr, 0, -2.4 * s)

    -- body (with lightening holes via even-odd)
    if tone == 'steel' then
        gear_path(cr, N, Ro, Rr)
        cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
        gear_holes(cr, N, Ro, Rr, hub)
        local g = cairo_pattern_create_radial(-3 * s, -4 * s, 2,
                                              -3 * s, -4 * s, (Ro + 6) * s)
        cairo_pattern_add_color_stop_rgb(g, 0.0, S3[1], S3[2], S3[3])
        cairo_pattern_add_color_stop_rgb(g, 0.5, S2[1], S2[2], S2[3])
        cairo_pattern_add_color_stop_rgb(g, 1.0, S1[1], S1[2], S1[3])
        cairo_set_source(cr, g)
        cairo_fill(cr)
        cairo_pattern_destroy(g)
    else
        gear_path(cr, N, Ro, Rr)
        cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
        gear_holes(cr, N, Ro, Rr, hub)
        local g = cairo_pattern_create_radial(-3 * s, -4 * s, 2,
                                              -3 * s, -4 * s, (Ro + 6) * s)
        cairo_pattern_add_color_stop_rgb(g, 0.0, 0.97, 0.80, 0.42)
        cairo_pattern_add_color_stop_rgb(g, 0.35, 0.82, 0.64, 0.33)
        cairo_pattern_add_color_stop_rgb(g, 0.7, 0.62, 0.47, 0.23)
        cairo_pattern_add_color_stop_rgb(g, 1.0, 0.46, 0.35, 0.17)
        cairo_set_source(cr, g)
        cairo_fill(cr)
        cairo_pattern_destroy(g)
    end

    -- rim stroke (polished bright edge so the gears read clearly)
    gear_path(cr, N, Ro, Rr)
    cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING)
    if tone == 'brass' then
        setc(cr, { 0.85, 0.68, 0.34 }, 0.95)
        cairo_set_line_width(cr, 1.4 * s)
        cairo_stroke(cr)
    else
        setc(cr, { 0.58, 0.66, 0.72 }, 0.85)
        cairo_set_line_width(cr, 1.2 * s)
        cairo_stroke(cr)
    end

    -- hub
    cairo_arc(cr, 0, 0, hub, 0, 2 * math.pi)
    local hg = cairo_pattern_create_radial(-hub * 0.3, -hub * 0.35, 0, 0, 0, hub + 2 * s)
    cairo_pattern_add_color_stop_rgb(hg, 0.0, S3[1], S3[2], S3[3])
    cairo_pattern_add_color_stop_rgb(hg, 0.7, S1[1], S1[2], S1[3])
    cairo_pattern_add_color_stop_rgb(hg, 1.0, S0[1], S0[2], S0[3])
    cairo_set_source(cr, hg)
    cairo_fill(cr)
    cairo_pattern_destroy(hg)
    cairo_arc(cr, 0, 0, 1.6 * s, 0, 2 * math.pi)
    setc(cr, B1, 1)
    cairo_fill(cr)
    cairo_restore(cr)
end

-- meshing phase offsets (tooth-center of A meets gap-center of B at contact)
local function mesh_phase(ax, ay, bx, by, Na, Nb)
    local alpha = math.atan2(by - ay, bx - ax)
    return alpha * (Na + Nb) / Nb + math.pi * (Nb - 1) / Nb
end

local GEAR_A   -- {x,y,N,Ro,Rr,hub,ang,base}
local GEAR_B
local GEAR_C
local function build_train(cx, cy)
    local Na, Nb, Nc = 40, 24, 16
    local pt = function(Ro, Rr) return (Ro + Rr) / 2 end
    -- A at centre of dial, ENLARGED so its teeth fill the skeleton hole
    local Ax, Ay = cx, cy
    local Ra = 66; local Rra = 57
    -- B upper-right meshing with A, pulled inward to keep the train in-frame
    local pb = pt(33, 27.5)
    local dAB = (pt(Ra, Rra) + pb) * 0.70
    local ba = -25 * RAD
    local Bx, By = Ax + dAB * math.cos(ba), Ay + dAB * math.sin(ba)
    -- C right-of-B
    local pc = pt(24, 20)
    local dBC = (pb + pc) * 0.82
    local bc = 32 * RAD
    local Cx, Cy = Bx + dBC * math.cos(bc), By + dBC * math.sin(bc)
    ba = math.atan2(By - Ay, Bx - Ax)
    bc = math.atan2(Cy - By, Cx - Bx)
    GEAR_A = { x = Ax, y = Ay, N = Na, Ro = Ra, Rr = Rra, hub = 16,
               ph = 0 }
    GEAR_B = { x = Bx, y = By, N = Nb, Ro = 33, Rr = 27.5, hub = 9,
               ph = math.fmod(mesh_phase(Ax, Ay, Bx, By, Na, Nb), 2 * math.pi) }
    GEAR_C = { x = Cx, y = Cy, N = Nc, Ro = 24, Rr = 20, hub = 7,
               ph = math.fmod(mesh_phase(Bx, By, Cx, Cy, Nb, Nc), 2 * math.pi) }
end

-- resolve actual tooth-grid angles for a smooth 'seconds-rate' runner
local function train_angles(sc)
    local aA = sc * 2 * math.pi / 60 * 2.0   -- 2 rev/min: lively but steady
    local aB = -(GEAR_A.N / GEAR_B.N) * aA + GEAR_B.ph
    local aC = -(GEAR_B.N / GEAR_C.N) * aB + GEAR_C.ph
    return aA, aB, aC
end

-- ---------------------------------------------------------------------------
--  CLOCK BODY
-- ---------------------------------------------------------------------------
local CLK_X, CLK_Y = 176, 132
local BEZ_R = 102      -- outer brass bezel radius
local DIAL_RO = 83     -- edge of the black dial annulus
local DIAL_RI = 70     -- inner opening (gears show through)

local NUM = { 'XII', 'I', 'II', 'III', 'IV', 'V', 'VI',
              'VII', 'VIII', 'IX', 'X', 'XI' }

local function draw_clock(cr, w, h, sc)
    local cx, cy = CLK_X * S, CLK_Y * S

    -- outer bezel ring (stepped brass)
    local g = cairo_pattern_create_radial(cx, cy, (BEZ_R - 10) * S,
                                          cx, cy, BEZ_R * S)
    cairo_pattern_add_color_stop_rgb(g, 0.0, B3[1], B3[2], B3[3])
    cairo_pattern_add_color_stop_rgb(g, 0.35, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(g, 0.7, B2[1], B2[2], B2[3])
    cairo_pattern_add_color_stop_rgb(g, 1.0, B4[1], B4[2], B4[3])
    cairo_set_source(cr, g)
    cairo_arc(cr, cx, cy, BEZ_R * S, 0, 2 * math.pi)
    cairo_fill(cr)
    cairo_pattern_destroy(g)
    -- bezel edge bevels
    setc(cr, TXT, 0.35)
    cairo_set_line_width(cr, 1.6 * S)
    cairo_arc(cr, cx, cy, (BEZ_R - 2) * S, math.pi * 0.25, math.pi * 1.35)
    cairo_stroke(cr)
    setc(cr, S0, 0.5)
    cairo_arc(cr, cx, cy, (BEZ_R - 2) * S, math.pi * 1.35, math.pi * 2.25)
    cairo_stroke(cr)

    -- dial annulus (black ring) 
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, DIAL_RO * S, 0, 2 * math.pi)
    cairo_arc_negative(cr, cx, cy, DIAL_RI * S, 0, 2 * math.pi)
    local dg = cairo_pattern_create_radial(cx - 8 * S, cy - 12 * S, 0,
                                           cx, cy, DIAL_RO * S)
    cairo_pattern_add_color_stop_rgb(dg, 0.0, DIALHI[1], DIALHI[2], DIALHI[3])
    cairo_pattern_add_color_stop_rgb(dg, 1.0, DIAL[1], DIAL[2], DIAL[3])
    cairo_set_source(cr, dg)
    cairo_fill(cr)
    cairo_pattern_destroy(dg)

    -- minute track: crisp hash marks hugging the inner opening edge, with bolder
    -- 5-minute marks (clear of the numerals so the chapter reads cleanly)
    for i = 0, 59 do
        local a = i * 6 * RAD - math.pi / 2
        local major = (i % 5 == 0)
        local r1 = (major and DIAL_RI + 0.5 or DIAL_RI + 1.2) * S
        local r2 = (major and DIAL_RI + 5.2 or DIAL_RI + 3.4) * S
        setc(cr, major and B1 or B3, major and 1 or 0.85)
        cairo_move_to(cr, cx + r1 * math.cos(a), cy + r1 * math.sin(a))
        cairo_line_to(cr, cx + r2 * math.cos(a), cy + r2 * math.sin(a))
        cairo_set_line_width(cr, (major and 2.6 or 1.3) * S)
        cairo_stroke(cr)
    end

    -- roman numerals on the dark dial ring, tucked well inside the bezel
    -- (rehaut) so they read clearly
    for i = 0, 11 do
        local a = i * 30 * RAD - math.pi / 2
        local px = cx + 76 * S * math.cos(a)
        local py = cy + 76 * S * math.sin(a)
        text_cx(cr, px, py + 3.5 * S, NUM[i + 1], B4, 12, false, true)
        text_cx(cr, px, py + 2 * S, NUM[i + 1], TXT, 12, false, true)
    end

    -- Roman numerals get an engraved shadow (drawn beneath) - do a subtle pass
    -- glass glare over the whole face
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, BEZ_R * S, 0, 2 * math.pi)
    cairo_clip(cr)
    local gg = cairo_pattern_create_radial(cx - BEZ_R * S * 0.45,
                                           cy - BEZ_R * S * 0.5,
                                           BEZ_R * S * 0.08,
                                           cx, cy, BEZ_R * S)
    cairo_pattern_add_color_stop_rgba(gg, 0.0, 1, 1, 1, 0.13)
    cairo_pattern_add_color_stop_rgba(gg, 0.5, 1, 1, 1, 0.03)
    cairo_pattern_add_color_stop_rgba(gg, 1.0, 0, 0, 0, 0.10)
    cairo_set_source(cr, gg)
    cairo_paint(cr)
    cairo_pattern_destroy(gg)
    cairo_reset_clip(cr)
end

local function draw_hand(cr, cx, cy, ang, len, tail, hw, col, col_hi)
    local a, s = ang, S
    local x1, y1 = cx + len * s * math.cos(a), cy + len * s * math.sin(a)
    local x0, y0 = cx - tail * s * math.cos(a), cy - tail * s * math.sin(a)
    local px, py = -math.sin(a), math.cos(a)
    -- shadow
    cairo_new_path(cr)
    cairo_move_to(cr, x0 + hw * px + 2 * s, y0 + hw * py + 2 * s)
    cairo_line_to(cr, x1 + hw * px + 2 * s, y1 + hw * py + 2 * s)
    cairo_line_to(cr, x1 - hw * px + 2 * s, y1 - hw * py + 2 * s)
    cairo_line_to(cr, x0 - hw * px + 2 * s, y0 - hw * py + 2 * s)
    cairo_close_path(cr)
    setc(cr, S0, 0.5)
    cairo_fill(cr)
    -- body
    cairo_new_path(cr)
    cairo_move_to(cr, x0 + hw * px, y0 + hw * py)
    cairo_line_to(cr, x1 + hw * px, y1 + hw * py)
    cairo_line_to(cr, x1 - hw * px, y1 - hw * py)
    cairo_line_to(cr, x0 - hw * px, y0 - hw * py)
    cairo_close_path(cr)
    setc(cr, col, 1)
    cairo_fill(cr)
    -- rounded tip highlight
    cairo_arc(cr, x1, y1, hw * s, 0, 2 * math.pi)
    setc(cr, col_hi or col, 1)
    cairo_fill(cr)
end

local function draw_seconds(cr, cx, cy, ang)
    local a, s = ang, S
    local len, tail = 74, 24
    local x1, y1 = cx + len * s * math.cos(a), cy + len * s * math.sin(a)
    local x0, y0 = cx - tail * s * math.cos(a), cy - tail * s * math.sin(a)
    -- recessed groove: concentric shadow so the tip never shows an offset smear
    cairo_set_line_width(cr, 2.4 * s)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_move_to(cr, x0, y0)
    cairo_line_to(cr, x1, y1)
    setc(cr, S0, 0.45)
    cairo_stroke(cr)
    -- crimson stem
    cairo_set_line_width(cr, 1.6 * s)
    cairo_move_to(cr, x0, y0)
    cairo_line_to(cr, x1, y1)
    setc(cr, CRIM, 1)
    cairo_stroke(cr)
    -- tail counterweight (brass ball, per design brief)
    cairo_arc(cr, x0, y0, 2.6 * s, 0, 2 * math.pi)
    local tg = cairo_pattern_create_radial(x0 - 0.9 * s, y0 - 1.1 * s, 0, x0, y0, 2.6 * s)
    cairo_pattern_add_color_stop_rgb(tg, 0.0, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(tg, 0.6, B2[1], B2[2], B2[3])
    cairo_pattern_add_color_stop_rgb(tg, 1.0, B4[1], B4[2], B4[3])
    cairo_set_source(cr, tg)
    cairo_fill(cr)
    cairo_pattern_destroy(tg)
    -- tip bead: brass ring + crimson core + glow glint
    cairo_arc(cr, x1, y1, 3.4 * s, 0, 2 * math.pi)
    local bg2 = cairo_pattern_create_radial(x1 - 1.2 * s, y1 - 1.4 * s, 0, x1, y1, 3.4 * s)
    cairo_pattern_add_color_stop_rgb(bg2, 0.0, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(bg2, 0.6, B2[1], B2[2], B2[3])
    cairo_pattern_add_color_stop_rgb(bg2, 1.0, B4[1], B4[2], B4[3])
    cairo_set_source(cr, bg2)
    cairo_fill(cr)
    cairo_pattern_destroy(bg2)
    cairo_arc(cr, x1, y1, 2.2 * s, 0, 2 * math.pi)
    setc(cr, CRIM, 1)
    cairo_fill(cr)
    cairo_arc(cr, x1 - 0.6 * s, y1 - 0.6 * s, 0.8 * s, 0, 2 * math.pi)
    setc(cr, GLOW, 1)
    cairo_fill(cr)
    -- hub cap
    cairo_arc(cr, cx, cy, 5.5 * s, 0, 2 * math.pi)
    local hg = cairo_pattern_create_radial(cx - 2 * s, cy - 2 * s, 0, cx, cy, 6 * s)
    cairo_pattern_add_color_stop_rgb(hg, 0.0, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(hg, 1.0, B4[1], B4[2], B4[3])
    cairo_set_source(cr, hg)
    cairo_fill(cr)
    cairo_pattern_destroy(hg)
end

local function draw_hands(cr, w, h, d, sc)
    local cx, cy = CLK_X * S, CLK_Y * S
    local hh = d.hour % 12 + d.min / 60 + sc / 3600
    local mm = d.min + sc / 60
    local ss = sc
    local ha = hh / 12 * 2 * math.pi - math.pi / 2
    local ma = mm / 60 * 2 * math.pi - math.pi / 2
    local sa = ss / 60 * 2 * math.pi - math.pi / 2
    draw_hand(cr, cx, cy, ha, 52, 20, 4.4, B1, TXT)
    draw_hand(cr, cx, cy, ma, 72, 24, 3.4, B2, B1)
    draw_seconds(cr, cx, cy, sa)
end

-- ---------------------------------------------------------------------------
--  PRESSURE GAUGE (reused for CPU / RAM / boiler)
-- ---------------------------------------------------------------------------
local function draw_gauge(cr, cx, cy, r, frac, label, sub)
    local s = S
    cx, cy = cx * s, cy * s
    r = r * s
    -- bezel
    local g = cairo_pattern_create_radial(cx - r * 0.3, cy - r * 0.35, 0, cx, cy, r)
    cairo_pattern_add_color_stop_rgb(g, 0.0, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(g, 0.55, B2[1], B2[2], B2[3])
    cairo_pattern_add_color_stop_rgb(g, 1.0, B4[1], B4[2], B4[3])
    cairo_set_source(cr, g)
    cairo_arc(cr, cx, cy, r, 0, 2 * math.pi)
    cairo_fill(cr)
    cairo_pattern_destroy(g)
    -- face
    cairo_arc(cr, cx, cy, r * 0.86, 0, 2 * math.pi)
    local fg = cairo_pattern_create_radial(cx, cy, 0, cx, cy, r * 0.86)
    cairo_pattern_add_color_stop_rgb(fg, 0.0, 0.16, 0.155, 0.15)
    cairo_pattern_add_color_stop_rgb(fg, 0.7, 0.10, 0.098, 0.095)
    cairo_pattern_add_color_stop_rgb(fg, 1.0, 0.065, 0.063, 0.06)
    cairo_set_source(cr, fg)
    cairo_fill(cr)
    cairo_pattern_destroy(fg)

    -- tick arc: 225deg .. -45deg (270 sweep), zero at bottom-left
    local a0 = 225 * RAD
    local sweep = 270 * RAD
    for i = 0, 40 do
        local a = a0 + sweep * i / 40
        local maj = (i % 5 == 0)
        local r1 = r * (maj and 0.74 or 0.79)
        local r2 = r * (maj and 0.82 or 0.82)
        setc(cr, maj and B1 or B2, maj and 0.9 or 0.55)
        cairo_move_to(cr, cx + r1 * math.cos(a), cy + r1 * math.sin(a))
        cairo_line_to(cr, cx + r2 * math.cos(a), cy + r2 * math.sin(a))
        cairo_set_line_width(cr, (maj and 2.2 or 1) * s)
        cairo_stroke(cr)
    end

    -- value arc (green->amber->red by fraction)
    local col_arc
    if frac < 0.5 then
        local t = frac / 0.5
        col_arc = { 0.35 + 0.43 * t, 0.72 - 0.35 * t, 0.25 }
    elseif frac < 0.8 then
        local t = (frac - 0.5) / 0.3
        col_arc = { 0.78 - 0.18 * t, 0.37 - 0.2 * t, 0.12 }
    else
        local t = (frac - 0.8) / 0.2
        col_arc = { 0.60 + 0.4 * t, 0.17, 0.12 }
    end
    cairo_set_line_width(cr, r * 0.16)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
    setc(cr, { 0.12, 0.12, 0.11 }, 1)
    cairo_arc(cr, cx, cy, r * 0.62, a0, a0 + sweep)
    cairo_stroke(cr)
    if frac > 0.01 then
        setc(cr, col_arc, 1)
        cairo_arc(cr, cx, cy, r * 0.62, a0, a0 + sweep * frac)
        cairo_stroke(cr)
    end

    -- needle
    local na = a0 + sweep * frac
    local nx = cx + r * 0.62 * math.cos(na)
    local ny = cy + r * 0.62 * math.sin(na)
    local px, py = -math.sin(na), math.cos(na)
    cairo_new_path(cr)
    cairo_move_to(cr, cx - r * 0.12 * math.cos(na) + 2 * s, cy - r * 0.12 * math.sin(na) + 2 * s)
    cairo_line_to(cr, nx + r * 0.035 * px + 2 * s, ny + r * 0.035 * py + 2 * s)
    cairo_line_to(cr, nx - r * 0.035 * px + 2 * s, ny - r * 0.035 * py + 2 * s)
    cairo_close_path(cr)
    setc(cr, S0, 0.5)
    cairo_fill(cr)
    cairo_new_path(cr)
    cairo_move_to(cr, cx - r * 0.12 * math.cos(na), cy - r * 0.12 * math.sin(na))
    cairo_line_to(cr, nx + r * 0.035 * px, ny + r * 0.035 * py)
    cairo_line_to(cr, nx - r * 0.035 * px, ny - r * 0.035 * py)
    cairo_close_path(cr)
    setc(cr, CRIM, 1)
    cairo_fill(cr)

    -- center hub
    cairo_arc(cr, cx, cy, r * 0.055, 0, 2 * math.pi)
    setc(cr, B1, 1)
    cairo_fill(cr)
    cairo_arc(cr, cx, cy, r * 0.025, 0, 2 * math.pi)
    setc(cr, S0, 1)
    cairo_fill(cr)

    -- labels
    text_cx(cr, cx, cy - r * 0.52, label, B1, 11, false, true)
    text_cx(cr, cx, cy + r * 0.05, sub, TXT, 15, true, true)
    text_at(cr, cx - r * 0.78, cy + r * 0.16, '0', TXTDIM, 8, false, false)
    text_ri(cr, cx + r * 0.78, cy + r * 0.16, '100', TXTDIM, 8, false, false)

    -- glass
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, r * 0.86, 0, 2 * math.pi)
    cairo_clip(cr)
    local gg = cairo_pattern_create_radial(cx - r * 0.4, cy - r * 0.45, 0, cx, cy, r)
    cairo_pattern_add_color_stop_rgba(gg, 0.0, 1, 1, 1, 0.14)
    cairo_pattern_add_color_stop_rgba(gg, 0.5, 1, 1, 1, 0.03)
    cairo_pattern_add_color_stop_rgba(gg, 1.0, 0.1, 0.1, 0.1, 0.16)
    cairo_set_source(cr, gg)
    cairo_paint(cr)
    cairo_pattern_destroy(gg)
    cairo_reset_clip(cr)
end

-- ---------------------------------------------------------------------------
--  MERCURY THERMOMETER (silver column because we're classy)
-- ---------------------------------------------------------------------------
local TH_X = 176
local TH_TOP, TH_BOT = 336, 543
local TH_W = 20

local function draw_thermo(cr, w, h, temp)
    local cx = TH_X * S
    local top, bot = TH_TOP * S, TH_BOT * S
    local tw = TH_W * S
    local ymin, ymax = 30, 90
    local frac = math.max(0, math.min(1, (temp - ymin) / (ymax - ymin)))

    -- brass backplate (rounded column, kept slender so it clears the gauges)
    local g = cairo_pattern_create_linear(cx - tw, top, cx + tw, bot)
    cairo_pattern_add_color_stop_rgb(g, 0.0, B2[1], B2[2], B2[3])
    cairo_pattern_add_color_stop_rgb(g, 0.5, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(g, 1.0, B4[1], B4[2], B4[3])
    rrect(cr, cx - tw * 1.1, top - tw * 0.6, tw * 2.2, (bot - top) + tw * 1.2, tw)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)

    -- scale ticks (left side, inside the backplate)
    for i = 0, 6 do
        local v = ymin + (ymax - ymin) * i / 6
        local fy = (v - ymin) / (ymax - ymin)
        local yy = bot - fy * (bot - top)
        setc(cr, B3, 0.9)
        cairo_move_to(cr, cx - tw * 1.02, yy)
        cairo_line_to(cr, cx - tw * 0.78, yy)
        cairo_set_line_width(cr, 1.5 * S)
        cairo_stroke(cr)
    end

    -- glass tube
    rrect(cr, cx - tw * 0.75, top, tw * 1.5, bot - top, tw * 0.7)
    local tg = cairo_pattern_create_linear(cx - tw * 0.75, 0, cx + tw * 0.75, 0)
    cairo_pattern_add_color_stop_rgba(tg, 0.0, 0.05, 0.05, 0.06, 0.9)
    cairo_pattern_add_color_stop_rgba(tg, 0.5, 0.16, 0.17, 0.19, 0.9)
    cairo_pattern_add_color_stop_rgba(tg, 1.0, 0.04, 0.04, 0.05, 0.9)
    cairo_set_source(cr, tg)
    cairo_fill(cr)
    cairo_pattern_destroy(tg)

    -- mercury column: runs INSIDE the glass tube (top = tube top, bottom =
    -- tube bottom), bulb hangs below the case; never pokes below the case
    local bulb_r = 8.5 * S
    local bulb_y = bot + bulb_r * 1.45
    local col_bot = bot - 2 * S
    local col_hi = (bot - top) * (1 - frac)
    local col_top = bot - math.max(col_hi + bulb_r * 0.4, bulb_r * 0.8)
    local mg = cairo_pattern_create_linear(0, col_top, 0, col_bot)
    cairo_pattern_add_color_stop_rgb(mg, 0.0, MERCHI[1], MERCHI[2], MERCHI[3])
    cairo_pattern_add_color_stop_rgb(mg, 1.0, MERC[1], MERC[2], MERC[3])
    rrect(cr, cx - tw * 0.5, col_top, tw, col_bot - col_top + 2 * S, tw * 0.5)
    cairo_set_source(cr, mg)
    cairo_fill(cr)
    cairo_pattern_destroy(mg)
    -- bulb
    cairo_arc(cr, cx, bulb_y, bulb_r, 0, 2 * math.pi)
    setc(cr, MERC, 1)
    cairo_fill(cr)
    cairo_arc(cr, cx - bulb_r * 0.3, bulb_y - bulb_r * 0.35, bulb_r * 0.5, 0, 2 * math.pi)
    setc(cr, MERCHI, 0.6)
    cairo_fill(cr)

    -- temp readout: gold value on a dark plaque BELOW the bulb so the silver
    -- bulb stays clear, with a DEG C caption tucked beneath the value
    local tv = temp or 0
    local ry = bot + bulb_r * 3.0
    rrect(cr, cx - 30 * S, ry, 60 * S, 36 * S, 5 * S)
    setc(cr, S0, 0.6)
    cairo_fill(cr)
    setc(cr, B1, 0.9)
    cairo_set_line_width(cr, 1 * S)
    cairo_stroke(cr)
    text_cx(cr, cx, ry + 20 * S, string.format('%02d', tv), B1, 22, true, true)
    text_cx(cr, cx, ry + 32 * S, 'DEG C', TXTDIM, 9, false, true)
    text_cx(cr, cx, top - 14 * S, 'TEMP', B1, 12, false, true)
end

-- ---------------------------------------------------------------------------
--  READOUT PLAQUES
-- ---------------------------------------------------------------------------
local function plaque(cr, x, y, w, h, label, value)
    local s = S
    -- recessed dark panel with brass contour
    local g = cairo_pattern_create_radial((x + w / 2) * s, (y + h * 0.3) * s, 0,
                                          (x + w / 2) * s, (y + h / 2) * s, w * 0.7 * s)
    cairo_pattern_add_color_stop_rgb(g, 0.0, 0.19, 0.18, 0.16)
    cairo_pattern_add_color_stop_rgb(g, 1.0, 0.10, 0.095, 0.085)
    rrect(cr, x * s, y * s, w * s, h * s, 4 * s)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)
    rrect(cr, x * s, y * s, w * s, h * s, 4 * s)
    setc(cr, B3, 1)
    cairo_set_line_width(cr, 1.2 * s)
    cairo_stroke(cr)
    text_at(cr, (x + 10) * s, (y + 16) * s, label, B1, 9, false, true)
    text_ri(cr, (x + w - 10) * s, (y + 34) * s, value, TXT, 11, true, true)
end

-- ---------------------------------------------------------------------------
--  BRASS PIPES  (clock support struts: rise beside the bezel, route around the
--  module block, then run down the outer margin and feed one end of the boiler)
-- ---------------------------------------------------------------------------
local PIPE_TOP = { 86, 266 }    -- upper run x (braces tuck behind the bezel)
local PIPE_OUT = { 16, 336 }    -- outer run x (visible edge run around the boxes)
local PIPE_ELB = 350            -- height of the outward elbow
local PIPE_TANK = { 66, 286 }   -- boiler entry points (one per tank end)

local function draw_pipes(cr, w, h)
    local s = S
    local pg = cairo_pattern_create_linear(0, 236 * s, 0, 816 * s)
    cairo_pattern_add_color_stop_rgb(pg, 0.0, B1[1], B1[2], B1[3])
    cairo_pattern_add_color_stop_rgb(pg, 0.45, B2[1], B2[2], B2[3])
    cairo_pattern_add_color_stop_rgb(pg, 1.0, B4[1], B4[2], B4[3])
    for i = 1, 2 do
        local tx, ox, et = PIPE_TOP[i], PIPE_OUT[i], PIPE_TANK[i]
        local dir = (tx < 176) and -1 or 1
        -- diagonal brace up to the bezel
        local bx2 = tx < 176 and 114 or 238
        cairo_new_path(cr)
        cairo_move_to(cr, (tx - 3) * s, 256 * s)
        cairo_line_to(cr, (tx + 3) * s, 256 * s)
        cairo_line_to(cr, (bx2 + 3) * s, 192 * s)
        cairo_line_to(cr, (bx2 - 3) * s, 192 * s)
        cairo_close_path(cr)
        setc(cr, B2, 1)
        cairo_fill(cr)
        -- upper vertical run (behind the caption plate, down to the elbow)
        cairo_rectangle(cr, (tx - 6.5) * s, 238 * s, 13 * s, (PIPE_ELB - 238) * s)
        cairo_set_source(cr, pg)
        cairo_fill(cr)
        -- the long run: outward elbow -> outer margin -> down into the tank end
        cairo_set_line_width(cr, 13 * s)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
        cairo_new_path(cr)
        cairo_move_to(cr, tx * s, PIPE_ELB * s)
        cairo_line_to(cr, ox * s, PIPE_ELB * s)
        cairo_line_to(cr, ox * s, 786 * s)
        cairo_line_to(cr, et * s, 822 * s)
        cairo_set_source(cr, pg)
        cairo_stroke(cr)
        -- cylindrical contour: bright specular on the inner edge, dark shade outer
        cairo_set_line_width(cr, 1.4 * s)
        setc(cr, TXT, 0.42)
        cairo_move_to(cr, (tx - dir * 3.1) * s, 240 * s)
        cairo_line_to(cr, (tx - dir * 3.1) * s, (PIPE_ELB - 2) * s)
        cairo_stroke(cr)
        cairo_move_to(cr, tx * s, (PIPE_ELB - 2.6) * s)
        cairo_line_to(cr, ox * s, (PIPE_ELB - 2.6) * s)
        cairo_stroke(cr)
        cairo_move_to(cr, (ox - dir * 3.1) * s, (PIPE_ELB + 2) * s)
        cairo_line_to(cr, (ox - dir * 3.1) * s, 784 * s)
        cairo_stroke(cr)
        local cdx, cdy = et - ox, 822 - 786
        local cl = math.sqrt(cdx * cdx + cdy * cdy)
        local ux, uy = cdx / cl, cdy / cl
        local px, py = -uy, ux
        cairo_move_to(cr, (ox + px * 2.7) * s, (786 + py * 2.7) * s)
        cairo_line_to(cr, (et + px * 2.7) * s, (822 + py * 2.7) * s)
        cairo_stroke(cr)
        setc(cr, S0, 0.40)
        cairo_set_line_width(cr, 1.1 * s)
        cairo_move_to(cr, (ox + dir * 3.3) * s, (PIPE_ELB + 2) * s)
        cairo_line_to(cr, (ox + dir * 3.3) * s, 782 * s)
        cairo_stroke(cr)
        -- pipe clips along the outer run
        for _, clipy in ipairs({ 380, 560, 700 }) do
            cairo_rectangle(cr, (ox - 8) * s, clipy * s, 16 * s, 3 * s)
            setc(cr, B3, 0.85)
            cairo_fill(cr)
        end
        -- knurled collar + cap disc at the top
        local cg = cairo_pattern_create_linear(0, 230 * s, 0, 242 * s)
        cairo_pattern_add_color_stop_rgb(cg, 0.0, B1[1], B1[2], B1[3])
        cairo_pattern_add_color_stop_rgb(cg, 1.0, B4[1], B4[2], B4[3])
        cairo_rectangle(cr, (tx - 9) * s, 230 * s, 18 * s, 12 * s)
        cairo_set_source(cr, cg)
        cairo_fill(cr)
        cairo_pattern_destroy(cg)
        setc(cr, S0, 0.6)
        cairo_set_line_width(cr, 1 * s)
        cairo_move_to(cr, (tx - 9) * s, 234 * s)
        cairo_line_to(cr, (tx + 9) * s, 234 * s)
        cairo_stroke(cr)
        cairo_move_to(cr, (tx - 9) * s, 238 * s)
        cairo_line_to(cr, (tx + 9) * s, 238 * s)
        cairo_stroke(cr)
        cairo_rectangle(cr, (tx - 6) * s, 227 * s, 12 * s, 4 * s)
        setc(cr, B3, 1)
        cairo_fill(cr)
    end
    cairo_pattern_destroy(pg)
end

-- ---------------------------------------------------------------------------
--  STEAM BOILER
-- ---------------------------------------------------------------------------
local STM = {}
local function spawn_steam(px, py, strong)
    if #STM > 40 then table.remove(STM, 1) end
    table.insert(STM, { x = px, y = py, r = (strong and 5.0 or 3.4) * S,
                        a = 0.50, vx = (math.random() - 0.5) * 1.1 * S,
                        vy = -(1.4 + math.random() * 1.5) * S,
                        grow = (0.14 + math.random() * 0.22) * S })
end

local function draw_steam(cr, dt)
    for i = #STM, 1, -1 do
        local p = STM[i]
        p.x = p.x + p.vx + math.sin(p.y / 6) * 0.35 * S
        p.y = p.y + p.vy
        p.r = p.r + p.grow
        p.a = p.a - dt * 0.24
        if p.a <= 0 then
            table.remove(STM, i)
        else
            local sd = cairo_pattern_create_radial(p.x - p.r * 0.2, p.y - p.r * 0.25,
                                                   p.r * 0.08, p.x, p.y, p.r)
            cairo_pattern_add_color_stop_rgba(sd, 0.0, 0.96, 0.97, 0.99,
                                              math.min(0.52, p.a))
            cairo_pattern_add_color_stop_rgba(sd, 0.55, 0.92, 0.94, 0.96,
                                              math.min(0.34, p.a * 0.7))
            cairo_pattern_add_color_stop_rgba(sd, 1.0, 0.87, 0.89, 0.92, 0.0)
            cairo_arc(cr, p.x, p.y, p.r, 0, 2 * math.pi)
            cairo_set_source(cr, sd)
            cairo_fill(cr)
            cairo_pattern_destroy(sd)
        end
    end
end

local steam_timer = 0.0
local steam_toggle = false
local function draw_boiler(cr, w, h, load, dt)
    local bx, by = 176, 856       -- boiler centre
    local bw, bh = 240, 96        -- BIGGER drum
    local s = S
    local x, y = (bx - bw / 2) * s, (by - bh / 2) * s
    local ww, hh = bw * s, bh * s

    -- shadow
    rrect(cr, (bx - bw / 2 + 3) * s, (by - bh / 2 + 4) * s, ww, hh, hh / 2)
    setc(cr, S0, 0.4)
    cairo_fill(cr)
    -- copper drum
    local g = cairo_pattern_create_linear(0, y, 0, y + hh)
    cairo_pattern_add_color_stop_rgb(g, 0.0, C1[1], C1[2], C1[3])
    cairo_pattern_add_color_stop_rgb(g, 0.45, C2[1], C2[2], C2[3])
    cairo_pattern_add_color_stop_rgb(g, 1.0, C3[1], C3[2], C3[3])
    rrect(cr, x, y, ww, hh, hh / 2)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)
    -- edge strap bands (kept clear of the central PSI dial)
    for _, fx in ipairs({ 0.10, 0.90 }) do
        rrect(cr, x + ww * fx - 4 * s, y - 3 * s, 8 * s, hh + 6 * s, 4 * s)
        setc(cr, B3, 0.9)
        cairo_fill(cr)
    end
    -- raised central PSI gauge (tucked up so the nameplate clears its glass)
    draw_gauge(cr, bx, by - 16, 30, math.max(0, math.min(1, load)), 'PSI', '')
    -- engraved maker's mark on a brass nameplate bolted BELOW the PSI dial so
    -- it sits fully on the tank face, clear of the gauge glass
    local nl = (by + 18) * s
    rrect(cr, (bx - 54) * s, nl, 108 * s, 24 * s, 4 * s)
    setc(cr, S0, 0.6)
    cairo_fill(cr)
    setc(cr, B3, 1)
    cairo_set_line_width(cr, 1 * s)
    cairo_stroke(cr)
    text_cx(cr, (bx + 1.2) * s, (by + 30) * s, 'A L C H E M I S T', C3, 8, false, true)
    text_cx(cr, bx * s, (by + 28.5) * s, 'A L C H E M I S T', C1, 9, false, true)
    text_cx(cr, (bx + 1.2) * s, (by + 38.5) * s, 'S T E A M  W O R K S', C3, 8, false, true)
    text_cx(cr, bx * s, (by + 37) * s, 'S T E A M  W O R K S', C1, 9, false, true)
    -- bolted junction collars where the drive pipes enter the drum shoulders
    for _, et in ipairs({ 66, 286 }) do
        local jy = (by - bh * 0.35) * s
        local ux, uy = et * s, jy
        local ug = cairo_pattern_create_radial(ux - 3 * s, uy - 3 * s, 0, ux, uy, 10 * s)
        cairo_pattern_add_color_stop_rgb(ug, 0.0, B1[1], B1[2], B1[3])
        cairo_pattern_add_color_stop_rgb(ug, 0.6, B2[1], B2[2], B2[3])
        cairo_pattern_add_color_stop_rgb(ug, 1.0, B4[1], B4[2], B4[3])
        cairo_arc(cr, ux, uy, 9 * s, 0, 2 * math.pi)
        cairo_set_source(cr, ug)
        cairo_fill(cr)
        cairo_pattern_destroy(ug)
        cairo_arc(cr, ux - 2 * s, uy - 2 * s, 4.5 * s, 0, 2 * math.pi)
        setc(cr, S0, 0.8)
        cairo_fill(cr)
    end
    -- TWIN safety valves (symmetric) spouting steam
    local vy = (by - bh * 0.40) * s
    local steam_pts = {}
    for _, vfx in ipairs({ -0.30, 0.30 }) do
        local vx = (bx + bw * vfx) * s
        cairo_move_to(cr, vx - 8 * s, (by + bh * 0.22) * s)
        cairo_line_to(cr, vx - 7 * s, vy)
        cairo_line_to(cr, vx + 7 * s, vy)
        cairo_line_to(cr, vx + 8 * s, (by + bh * 0.22) * s)
        setc(cr, B2, 1)
        cairo_fill(cr)
        cairo_arc(cr, vx, vy, 7 * s, 0, 2 * math.pi)
        setc(cr, B1, 1)
        cairo_fill(cr)
        cairo_arc(cr, vx, vy + 2 * s, 3 * s, 0, 2 * math.pi)
        setc(cr, S0, 0.5)
        cairo_fill(cr)
        steam_pts[#steam_pts + 1] = vx
    end
    steam_timer = steam_timer - dt
    if steam_timer <= 0 then
        steam_toggle = not steam_toggle
        local vi = steam_toggle and 1 or 2
        local vx = steam_pts[vi]
        spawn_steam(vx + (math.random() - 0.5) * 6 * s, vy - 5 * s,
                    load > 0.4 or math.random() < 0.45)
        steam_timer = 0.05 + math.random() * 0.10
    end
    -- pole junction wisps (steam entering the drive pipes)
    if math.random() < 0.20 then
        for _, px in ipairs({ 66, 286 }) do
            if #STM < 40 then
                table.insert(STM, { x = px * s + (math.random() - 0.5) * 8 * s,
                                    y = (by - bh * 0.35 - 6) * s,
                                    r = (2.0 + math.random() * 1.5) * s,
                                    a = 0.22,
                                    vx = (math.random() - 0.5) * 0.35 * s,
                                    vy = -(0.5 + math.random() * 0.8) * s,
                                    grow = (0.06 + math.random() * 0.10) * s })
            end
        end
    end
end

-- ---------------------------------------------------------------------------
--  MAIN
-- ---------------------------------------------------------------------------
local last_clock = 0
function conky_main()
    if conky_window == nil then return end
    local w, h = conky_window.width, conky_window.height
    if w < 8 or h < 8 then return end
    S = math.max(0.01, w / GRID_W)

    local cs = cairo_xlib_surface_create(conky_window.display,
                                         conky_window.drawable,
                                         conky_window.visual, w, h)
    local cr = cairo_create(cs)

    local now = os.clock()
    local dt = math.max(0.01, math.min(0.25, now - last_clock))
    last_clock = now

    local d = os.date('*t')
    -- smooth wall-clock seconds: /proc/uptime is a monotonic wall clock with
    -- sub-second precision. os.clock()%1 (CPU time) drifts out of phase with
    -- d.sec, so the hand read ~1s ahead/behind everywhere and snapped
    -- backwards whenever the CPU fraction wrapped. uptime%60 is phase-locked.
    local sc = d.sec + (os.clock() % 1)
    local uf = io.open('/proc/uptime', 'r')
    if uf then
        local ln = uf:read('*l') or ''
        uf:close()
        local up = tonumber(ln:match('[%d.]+'))
        if up then sc = up % 60 end
    end

    draw_plate(cr, w, h)
    draw_frame(cr, w, h)
    draw_pipes(cr, w, h)

    -- clock + gears
    if not GEAR_A then build_train(CLK_X, CLK_Y) end
    local aA, aB, aC = train_angles(sc)
    draw_gear(cr, GEAR_C.x, GEAR_C.y, GEAR_C.N, GEAR_C.Ro, GEAR_C.Rr,
              GEAR_C.hub, aC, 'steel')
    draw_gear(cr, GEAR_B.x, GEAR_B.y, GEAR_B.N, GEAR_B.Ro, GEAR_B.Rr,
              GEAR_B.hub, aB, 'brass')
    draw_gear(cr, GEAR_A.x, GEAR_A.y, GEAR_A.N, GEAR_A.Ro, GEAR_A.Rr,
              GEAR_A.hub, aA, 'brass')
    draw_clock(cr, w, h, sc)
    draw_hands(cr, w, h, d, sc)

    -- caption plate: wide nameplate under the clock so the engraving clears
    -- the pipes that route past either side
    rrect(cr, 28 * S, 262 * S, 296 * S, 22 * S, 4 * S)
    setc(cr, S0, 0.5)
    cairo_fill(cr)
    rrect(cr, 24 * S, 260 * S, 304 * S, 22 * S, 4 * S)
    local pg = cairo_pattern_create_radial(176 * S, 264 * S, 0, 176 * S, 271 * S, 110 * S)
    cairo_pattern_add_color_stop_rgb(pg, 0.0, 0.24, 0.21, 0.16)
    cairo_pattern_add_color_stop_rgb(pg, 1.0, 0.12, 0.105, 0.08)
    cairo_set_source(cr, pg)
    cairo_fill(cr)
    cairo_pattern_destroy(pg)
    text_cx(cr, 176 * S, 276 * S, 'T H E  C L O C K W O R K  A L C H E M I S T', B2, 12, false, true)

    rail(cr, 300)

    -- gauges + thermometer
    local cpu = read_cpu()
    local mem = read_mem()
    local temp = read_temp()
    draw_gauge(cr, 92, 452, 56, cpu / 100, 'CPU', string.format('%.0f%%', cpu))
    draw_gauge(cr, 260, 452, 56, mem / 100, 'RAM', string.format('%.0f%%', mem))
    draw_thermo(cr, w, h, temp)

    rail(cr, 610)

    -- readouts
    local l1, l2, l3 = read_load()
    plaque(cr, 34, 618, 140, 46, 'LOAD', string.format('%.2f  %.2f  %.2f', l1, l2, l3))
    plaque(cr, 178, 618, 140, 46, 'CORE', string.format('%d C  %d%%', temp, cpu))
    plaque(cr, 34, 670, 140, 46, 'TEMPERATURE', string.format('%d C', temp))
    plaque(cr, 178, 670, 140, 46, 'UPTIME', read_uptime())

    local iu = (d.hour * 100 + d.min) .. ''
    local time_str = string.format('%02d:%02d', d.hour, d.min)
    local date_str = d.month .. '/' .. d.day .. '/' .. (d.year % 100)
    plaque(cr, 34, 722, 140, 46, 'NOW', time_str .. '  ' .. date_str)
    plaque(cr, 178, 722, 140, 46, 'UTIL', string.format('%.2f', l1))

    -- boiler + steam
    local up, dn = read_net(dt)
    draw_boiler(cr, w, h, math.max(l1, cpu) / 90, dt)
    draw_steam(cr, dt)

    -- network ticker under boiler
    text_cx(cr, 176 * S, 922 * S,
            'UP ' .. string.format('%.1f', up) .. ' KB/s    DN ' .. string.format('%.1f', dn) .. ' KB/s',
            TXT, 12, true, false)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    cr = nil
end
