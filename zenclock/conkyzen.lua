-- ############################################################
--  Zen Meditation Timer -- Cairo/Lua renderer (v7, clean slate)
--
--  Minimal dark panel with a zen vibe:
--    - dark rounded plate, subtle depth
--    - thin gold accent line
--    - big white digital clock + date
--    - meditation timer (mode / count-up / goal)
--    - three control buttons (drawn here, clickable via btnzen)
--
--  No enso, no scene, no figures -- just calm and readable.
-- ############################################################

require 'cairo'

local HOME     = os.getenv('HOME')
local SWITCH   = HOME .. '/.conky/zenclock/zentimer'
local GONG     = HOME .. '/.conky/zenclock/gong.wav'
local CHIME    = HOME .. '/.conky/zenclock/chime.wav'
local CHIME_EVERY = 900          -- periodic chime, once every 15 min (scarcer)
local BREATH_PERIOD = 8          -- seconds per full breathe in/out cycle
local FRAME_DT = 0.25            -- matches update_interval in the .rc

-- Grid size (equals window size, 1:1)
local DW, DH = 280, 400

-- Colors
local WHITE   = { 0xf2, 0xf2, 0xf0 }
local GOLD    = { 0xc9, 0xa9, 0x6e }
local DIM     = { 0x9a, 0x9a, 0xa0 }
local FAINT   = { 0x6a, 0x6a, 0x70 }
local SHADOW  = { 0x00, 0x00, 0x00 }

-- Plate background (dark, cool-tinted, subtle radial dome)
local PLATE_A = { 0x24, 0x24, 0x28 }
local PLATE_B = { 0x16, 0x16, 0x1a }
local PLATE_C = { 0x10, 0x10, 0x13 }

-- ======================= STATE =======================
local st  = { mode = 'idle', last = 0, pauseAt = 0, accum = 0, goal = 0 }
local lastChime = 0
local notifiedDone = false
local breathe = 0   -- breathing animation phase (advances each frame while running)

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end

local function read_state()
    local f = io.open(SWITCH, 'r')
    if not f then return end
    local m   = f:read('*l') or 'idle'
    local l2  = f:read('*l') or '0'
    local l3  = f:read('*l') or '0'
    local l4  = f:read('*l') or '0'
    local l5  = f:read('*l') or '0'
    f:close()
    local old = st.mode
    st.mode     = m
    st.last     = tonumber(l2) or 0
    st.pauseAt  = tonumber(l3) or 0
    st.accum    = tonumber(l4) or 0
    st.goal     = tonumber(l5) or 0
    if st.mode ~= old then
        if st.mode == 'run' then
            lastChime = math.floor((st.accum or 0) / CHIME_EVERY)
            notifiedDone = false
        end
        if st.mode == 'idle' then lastChime = 0; notifiedDone = false; st.accum = 0 end
    end
end

local function elapsed_now()
    local now = os.time()
    if st.mode == 'run' then return st.accum + (now - st.last)
    else return st.accum end
end

local function hms(secs)
    secs = math.floor(secs + 0.5)
    local s = secs % 60
    local m = math.floor(secs / 60) % 60
    local h = math.floor(secs / 3600)
    return string.format('%02d:%02d:%02d', h, m, s)
end

-- ======================= GONGS =======================
local FULL = 65536  -- paplay --volume max (linear 0..65536)
local function play(path, vol)
    if path and io.open(path, 'r') then
        local v = ''
        if vol and vol > 0 then v = ' --volume=' .. math.floor(vol) end
        os.execute('paplay' .. v .. ' "' .. path .. '" >/dev/null 2>&1 &')
    end
end
local function fire_start()   play(GONG, FULL)  end
local function fire_done()
    -- three fading strikes (softer each time) = a gentle, tapering finish
    local g = string.format('paplay --volume=%d "%s" >/dev/null 2>&1 &', FULL, GONG)
    local g2 = string.format('paplay --volume=%d "%s" >/dev/null 2>&1 &', math.floor(FULL*0.70), GONG)
    local g3 = string.format('paplay --volume=%d "%s" >/dev/null 2>&1 &', math.floor(FULL*0.45), GONG)
    os.execute('(sleep 0.5; ' .. g .. ') & (sleep 1.1; ' .. g2 .. ') & (sleep 1.7; ' .. g3 .. ') &')
end
local function fire_chime()   play(CHIME, math.floor(FULL*0.6)) end

local prevMode = 'idle'

local function tick_timer()
    read_state()
    local e = elapsed_now()
    if st.mode == 'run' then
        if prevMode ~= 'run' then fire_start() end
        local mark = math.floor(e / CHIME_EVERY)
        if mark > lastChime then
            lastChime = mark
            if mark > 0 then fire_chime() end
        end
        if st.goal > 0 and e >= st.goal and not notifiedDone then
            notifiedDone = true
            fire_done()
            local f = io.open(SWITCH, 'w')
            if f then
                f:write('done\n0\n0\n' .. math.floor(st.goal) .. '\n' .. st.goal .. '\n')
                f:close()
            end
        end
    end
    prevMode = st.mode
end

-- ======================= CAIRO HELPERS =======================
local function set_c(cr, col, a)
    cairo_set_source_rgba(cr, col[1]/255, col[2]/255, col[3]/255, a)
end

local function rounded_rect(cr, x, y, w, h, r)
    if r > w / 2 then r = w / 2 end
    if r > h / 2 then r = h / 2 end
    cairo_new_path(cr)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cairo_arc(cr, x + w - r, y + r, r, 3 * math.pi / 2, 2 * math.pi)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
    cairo_close_path(cr)
end

local function text_centered(cr, cx, y, str, size, col, alpha, bold, font)
    if not str or str == '' then return end
    font = font or 'DejaVu Sans'
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL,
                           bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, str, ext)
    local x = cx - (ext.width / 2 + ext.x_bearing)
    -- soft shadow
    cairo_set_source_rgba(cr, SHADOW[1]/255, SHADOW[2]/255, SHADOW[3]/255, alpha * 0.65)
    for _, off in ipairs({ {0,0}, {1,0}, {0,1}, {1,1} }) do
        cairo_move_to(cr, x + off[1], y + off[2])
        cairo_show_text(cr, str)
    end
    -- main
    cairo_set_source_rgba(cr, col[1]/255, col[2]/255, col[3]/255, alpha)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, str)
end

-- ======================= BACKGROUND =======================
local function paint_plate(cr, w, h)
    local m = 10              -- margin
    local x, y = m, m
    local pw, ph = w - 2*m, h - 2*m
    local r = 18

    -- drop shadow under the plate
    cairo_save(cr)
    cairo_translate(cr, 0, 3)
    set_c(cr, SHADOW, 0.35)
    rounded_rect(cr, x, y, pw, ph, r)
    cairo_fill(cr)
    cairo_restore(cr)

    -- plate fill: subtle radial dome, lighter at top-center
    local p = cairo_pattern_create_radial(w/2, y + ph*0.32, 20, w/2, y + ph*0.55, ph*0.85)
    cairo_pattern_add_color_stop_rgba(p, 0,   PLATE_A[1]/255, PLATE_A[2]/255, PLATE_A[3]/255, 1)
    cairo_pattern_add_color_stop_rgba(p, 0.55, PLATE_B[1]/255, PLATE_B[2]/255, PLATE_B[3]/255, 1)
    cairo_pattern_add_color_stop_rgba(p, 1,   PLATE_C[1]/255, PLATE_C[2]/255, PLATE_C[3]/255, 1)
    cairo_set_source(cr, p)
    cairo_pattern_destroy(p)
    rounded_rect(cr, x, y, pw, ph, r)
    cairo_fill(cr)

    -- thin edge highlight (top-left understated, dark bottom-right)
    set_c(cr, { 0xaa, 0xaa, 0xb0 }, 0.14)
    cairo_set_line_width(cr, 1.2)
    rounded_rect(cr, x + 0.5, y + 0.5, pw - 1, ph - 1, r)
    cairo_stroke(cr)

    -- gold accent line (centered above the clock)
    local ax = w/2 - 45
    set_c(cr, GOLD, 0.55)
    rounded_rect(cr, ax, 26, 90, 2.5, 1.25)
    cairo_fill(cr)
end

-- ======================= LEGEND / STATIC TEXT =======================
-- (hold any fixed labels here if needed)

-- ======================= MAIN DRAW =======================
function conky_main()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(conky_window.display,
                conky_window.drawable, conky_window.visual,
                conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    local w, h = conky_window.width, conky_window.height
    local s = w / DW
    if s < 0.01 then s = 1 end

    tick_timer()
    local e = elapsed_now()

    paint_plate(cr, w, h)

    -- BREATHING HALO: while meditating, a soft gold halo behind the clock
    -- swells and recedes like a slow breath (period BREATH_PERIOD). DRAWN
    -- FIRST so text sits on top. Phase accumulates on our own FRAME_DT clock
    -- so it animates smoothly even if conkey's wall-clock jitters.
    if st.mode == 'run' or st.mode == 'done' then
        breathe = breathe + FRAME_DT
        local ph   = (breathe % BREATH_PERIOD) / BREATH_PERIOD
        local wf   = 0.5 + 0.5 * math.cos(2 * math.pi * ph)   -- 1.0 → 0.0
        local haloA = st.mode == 'done' and 0.30 or (0.16 + 0.22 * wf)   -- 0.38 → 0.16
        local haloR = (86 + 22 * wf) * s
        local p = cairo_pattern_create_radial(w/2, 118*s, 8, w/2, 118*s, haloR)
        cairo_pattern_add_color_stop_rgba(p, 0,   GOLD[1]/255, GOLD[2]/255, GOLD[3]/255, haloA * 0.5)
        cairo_pattern_add_color_stop_rgba(p, 0.55, GOLD[1]/255, GOLD[2]/255, GOLD[3]/255, haloA * 0.18)
        cairo_pattern_add_color_stop_rgba(p, 1,   GOLD[1]/255, GOLD[2]/255, GOLD[3]/255, 0)
        cairo_set_source(cr, p)
        cairo_pattern_destroy(p)
        cairo_paint(cr)
    end

    -- TIME (big, calm)
    local hh, mm = os.date('%H'), os.date('%M')
    text_centered(cr, w/2, 118 * s, hh .. ':' .. mm, 62, WHITE, 1.0, true, 'DejaVu Sans Mono')

    -- DATE
    local dt = os.date('%a %b %d'):upper()
    text_centered(cr, w/2, 150 * s, dt, 16, DIM, 0.9, false, 'DejaVu Sans')

    -- TIMER ZONE
    local modeTxt = ''
    if st.mode == 'run' then modeTxt = 'MEDITATING'
    elseif st.mode == 'pause' then modeTxt = 'PAUSED'
    elseif st.mode == 'done' then modeTxt = 'COMPLETE' end

    if modeTxt ~= '' then
        local gold_a = st.mode == 'run' and 0.95 or 0.55
        text_centered(cr, w/2, 232 * s, modeTxt, 17, GOLD, gold_a, true, 'DejaVu Sans')
        text_centered(cr, w/2, 268 * s, hms(e), 26, WHITE, 1.0, true, 'DejaVu Sans Mono')
        if st.goal and st.goal > 0 then
            local remain = st.goal - e
            if remain <= 0 then remain = 0 end
            text_centered(cr, w/2, 296 * s, 'goal ' .. hms(st.goal) .. '   left ' .. hms(remain), 12, FAINT, 0.9, false, 'DejaVu Sans')
        end
    else
        -- idle: whisper a hint so the state is readable
        if st.goal and st.goal > 0 then
            text_centered(cr, w/2, 240 * s, 'goal ' .. math.floor(st.goal/60) .. 'm', 12, FAINT, 0.7, false, 'DejaVu Sans')
        else
            text_centered(cr, w/2, 240 * s, 'zen timer', 12, FAINT, 0.5, false, 'DejaVu Sans')
        end
    end

    -- BUTTONS
    local bw, bh = 76, 28
    local labels = { 'START', 'RESET', 'GOAL off' }
    if st.mode == 'run' then labels[1] = 'PAUSE' end
    if st.goal and st.goal > 0 then labels[3] = 'GOAL ' .. math.floor(st.goal / 60) .. 'm' end
    local fills = { { 0x1e, 0x22, 0x28 }, { 0x1e, 0x22, 0x28 }, { 0x1e, 0x22, 0x28 } }
    if st.mode == 'run' then fills[1] = { 0x2a, 0x4a, 0x36 } end
    local btn_xs = { w/2 - 100, w/2, w/2 + 100 }
    local btn_y = 350 * s
    for i, bx in ipairs(btn_xs) do
        set_c(cr, SHADOW, 0.4)
        rounded_rect(cr, bx - bw/2, btn_y - bh/2 + 2, bw, bh, 6)
        cairo_fill(cr)
        set_c(cr, fills[i], 0.65)
        rounded_rect(cr, bx - bw/2, btn_y - bh/2, bw, bh, 6)
        cairo_fill(cr)
        set_c(cr, GOLD, 0.5)
        rounded_rect(cr, bx - bw/2 + 1, btn_y - bh/2 + 1, bw - 2, bh - 2, 5)
        cairo_stroke(cr)
        text_centered(cr, bx, btn_y + 4, labels[i], 12, WHITE, 0.95, false, 'DejaVu Sans')
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- ======================= BUTTON SPAWN =======================
local function spawn_button()
    local sh = "HB='" .. HOME .. "'; A=btn; B=zen; if ! pgrep -f 'zenclock/btnze[n]' >/dev/null 2>&1; then setsid python3 \"$HB/.conky/zenclock/$A$B\" </dev/null >>\"$HB/.conky/zenclock/$A$B.log\" 2>&1 & fi"
    os.execute(sh)
end

spawn_button()