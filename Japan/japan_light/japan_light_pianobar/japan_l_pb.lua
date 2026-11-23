require 'cairo'
pcall(require, 'cairo_xlib')

local HOME_DIR     = os.getenv('HOME') or '.'
local CACHE_PATH   = HOME_DIR .. '/.cache/conky/pianobar-widget.status'
local COVER_JPG    = HOME_DIR .. '/.config/pianobar/coverArt.jpg'
local COVER_PNG    = HOME_DIR .. '/.cache/conky/japan_light_pianobar_cover.png'
local COVER_MARKER = COVER_PNG .. '.mtime'
local STATUS_PATTERN = '^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$'

local GRID_W = 460
local GRID_H = 260
local DEG = math.pi / 180
local TEXT_EXT = cairo_text_extents_t:create()

local LACQUER_BLACK = { 0.541, 0.467, 0.369 }
local INK_STEEL     = { 0.424, 0.400, 0.349 }
local GRAPHITE      = { 0.302, 0.259, 0.208 }
local LEMON_CHIFFON = { 0.098, 0.086, 0.067 }
local BODHI_BRONZE  = { 0.851, 0.667, 0.388 }
local CINNABAR      = { 0.72, 0.23, 0.18 }

local cr = nil

local function set_c(c, a)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], a or 1)
end

local function rrect(x, y, w, h, r)
    if r > w / 2 then r = w / 2 end
    if r > h / 2 then r = h / 2 end
    cairo_new_path(cr)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -math.pi / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, math.pi / 2)
    cairo_arc(cr, x + r, y + h - r, r, math.pi / 2, math.pi)
    cairo_arc(cr, x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cairo_close_path(cr)
end

local function set_font(family, size, bold)
    cairo_select_font_face(cr, family, CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
end

local function utf8_chars(text)
    local chars, i = {}, 1
    text = tostring(text or '')
    while i <= #text do
        local b = text:byte(i) or 0
        local n = 1
        if b >= 240 then n = 4 elseif b >= 224 then n = 3 elseif b >= 194 then n = 2 end
        if i + n - 1 > #text then n = 1 end
        chars[#chars + 1] = text:sub(i, i + n - 1)
        i = i + n
    end
    return chars
end

local function fit_text(text, maxw, family, size, bold)
    text = tostring(text or '')
    if text == '' or maxw <= 0 then return '' end
    set_font(family, size, bold)
    local chars = utf8_chars(text)
    local lo, hi = 0, #chars
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        cairo_text_extents(cr, table.concat(chars, '', 1, mid), TEXT_EXT)
        if TEXT_EXT.width <= maxw then lo = mid else hi = mid - 1 end
    end
    local out = table.concat(chars, '', 1, lo)
    if lo < #chars then out = out .. '…' end
    return out
end

local function text_at(text, x, y, size, c, alpha, align, bold, family)
    text = tostring(text or '')
    if text == '' then return end
    family = family or 'Noto Sans CJK JP'
    set_font(family, size, bold)
    cairo_text_extents(cr, text, TEXT_EXT)
    local tx = x
    if align == 'center' then
        tx = x - (TEXT_EXT.width + TEXT_EXT.x_bearing) / 2
    elseif align == 'right' then
        tx = x - TEXT_EXT.width - TEXT_EXT.x_bearing
    end
    set_c(c, alpha)
    cairo_move_to(cr, tx, y)
    cairo_show_text(cr, text)
end

local function clean(v)
    return (tostring(v or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function read_status()
    local h = io.open(CACHE_PATH, 'r')
    local raw = ''
    if h then raw = clean(h:read('*l') or ''); h:close() end

    local title, artist, album, dur, pos, state = raw:match(STATUS_PATTERN)
    if not title then
        return { title='', artist='', album='', duration=0, position=0, state='stopped', active=false }
    end
    dur = tonumber(dur) or 0
    pos = tonumber(pos) or 0
    if dur ~= dur or dur < 0 then dur = 0 end
    if pos ~= pos or pos < 0 then pos = 0 end
    state = clean(state):lower()
    if state ~= 'playing' and state ~= 'paused' and state ~= 'waiting' and state ~= 'stopped' then
        state = 'stopped'
    end
    return {
        title = clean(title), artist = clean(artist), album = clean(album),
        duration = dur, position = pos, state = state,
        active = state ~= 'stopped' and (title ~= '' or artist ~= ''),
    }
end

local function format_time(v)
    local t = math.floor(math.max(0, tonumber(v) or 0))
    return string.format('%d:%02d', math.floor(t / 60), t % 60)
end

local function shell_quote(v)
    return "'" .. tostring(v):gsub("'", "'\\''") .. "'"
end

local function file_exists(p)
    local h = io.open(p, 'rb')
    if h then h:close() return true end
    return false
end

local function file_mtime(p)
    local h = io.popen('stat -c %Y ' .. shell_quote(p) .. ' 2>/dev/null')
    if not h then return 0 end
    local v = tonumber(h:read('*a') or '') or 0
    h:close()
    return v
end

local art_surface, art_key, last_check = nil, nil, 0

local function drop_art()
    if art_surface then cairo_surface_destroy(art_surface) end
    art_surface, art_key = nil, nil
end

local function refresh_art()
    local now = os.time()
    if now - last_check < 3 then return end
    last_check = now

    local mt = file_mtime(COVER_JPG)
    if mt <= 0 then
        drop_art()
        os.remove(COVER_PNG)
        os.remove(COVER_MARKER)
        return
    end
    if art_surface and art_key == mt then return end

    local mh = io.open(COVER_MARKER, 'r')
    local marker = ''
    if mh then marker = mh:read('*l') or ''; mh:close() end

    if marker ~= tostring(mt) or not file_exists(COVER_PNG) then
        os.remove(COVER_PNG)
        os.execute(string.format(
            'convert %s -resize 280x280^ -gravity center -extent 280x280 %s 2>/dev/null',
            shell_quote(COVER_JPG), shell_quote(COVER_PNG)))
        if file_exists(COVER_PNG) then
            local w = io.open(COVER_MARKER, 'w')
            if w then w:write(tostring(mt)); w:close() end
        else
            os.remove(COVER_MARKER)
        end
    end

    drop_art()
    if file_exists(COVER_PNG) then
        local ok, surf = pcall(cairo_image_surface_create_from_png, COVER_PNG)
        if ok and surf then
            local wok, iw = pcall(cairo_image_surface_get_width, surf)
            if wok and iw and iw > 0 then
                art_surface, art_key = surf, mt
            else
                cairo_surface_destroy(surf)
            end
        end
    end
end

local function paint_plate()
    local g = cairo_pattern_create_linear(0, 0, 448, 248)
    cairo_pattern_add_color_stop_rgba(g, 0.00, 0.671, 0.655, 0.588, 0.94)
    cairo_pattern_add_color_stop_rgba(g, 0.55, 0.600, 0.588, 0.537, 0.96)
    cairo_pattern_add_color_stop_rgba(g, 1.00, 0.424, 0.400, 0.349, 0.98)
    rrect(6, 6, 448, 248, 16)
    cairo_set_source(cr, g)
    cairo_fill(cr)
    cairo_pattern_destroy(g)

    set_c(BODHI_BRONZE, 0.28)
    cairo_set_line_width(cr, 1.4)
    rrect(7, 7, 446, 246, 15)
    cairo_stroke(cr)

    set_c(LEMON_CHIFFON, 0.08)
    cairo_set_line_width(cr, 0.8)
    rrect(12, 12, 436, 236, 12)
    cairo_stroke(cr)
end

local function draw_placeholder(x, y, size)
    set_c(LACQUER_BLACK, 0.92)
    rrect(x, y, size, size, 10)
    cairo_fill(cr)
    set_c(GRAPHITE, 0.35)
    cairo_set_line_width(cr, 0.8)
    rrect(x + 6, y + 6, size - 12, size - 12, 7)
    cairo_stroke(cr)
    text_at('NO COVER', x + size / 2, y + size - 14, 7, BODHI_BRONZE, 0.62, 'center', false, 'DejaVu Sans Mono')
end

local function draw_art(show, dim)
    local x, y, size = 30, 66, 150

    set_c(INK_STEEL, 0.85)
    rrect(x - 4, y - 4, size + 8, size + 8, 12)
    cairo_fill(cr)

    set_c(BODHI_BRONZE, 0.62)
    cairo_set_line_width(cr, 1.6)
    rrect(x - 2, y - 2, size + 4, size + 4, 11)
    cairo_stroke(cr)

    local drew = false
    if show then
        refresh_art()
        if art_surface then
            local iw = cairo_image_surface_get_width(art_surface)
            local ih = cairo_image_surface_get_height(art_surface)
            if iw > 0 and ih > 0 then
                cairo_save(cr)
                rrect(x, y, size, size, 8)
                cairo_clip(cr)
                cairo_translate(cr, x, y)
                cairo_scale(cr, size / iw, size / ih)
                cairo_set_source_surface(cr, art_surface, 0, 0)
                cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_BILINEAR)
                cairo_paint(cr)
                cairo_restore(cr)
                drew = true
                if dim then
                    cairo_save(cr)
                    set_c(LACQUER_BLACK, 0.44)
                    rrect(x, y, size, size, 8)
                    cairo_fill(cr)
                    cairo_restore(cr)
                end
            end
        end
    end
    if not drew then draw_placeholder(x, y, size) end

    set_c(BODHI_BRONZE, 0.74)
    cairo_set_line_width(cr, 0.9)
    rrect(x, y, size, size, 8)
    cairo_stroke(cr)
end

local function state_seal(state)
    local x, y, w, h = 384, 20, 52, 28
    set_c(LACQUER_BLACK, 0.92)
    rrect(x, y, w, h, 5)
    cairo_fill(cr)

    set_c(CINNABAR, 0.78)
    cairo_set_line_width(cr, 1.0)
    rrect(x, y, w, h, 5)
    cairo_stroke(cr)

    local kanji = {
        playing = '再生', paused = '休止', waiting = '待機', stopped = '停止',
    }
    local labels = {
        playing = 'PLAYING', paused = 'PAUSED', waiting = 'WAITING', stopped = 'STOPPED',
    }
    text_at(kanji[state] or kanji.stopped, x + w / 2, y + 18, 12, CINNABAR, 0.96, 'center', true)
    text_at(labels[state] or labels.stopped, x + w / 2, y + 26, 5.5, LEMON_CHIFFON, 0.72, 'center', false, 'DejaVu Sans Mono')
end

local function progress_rail(ratio, state)
    local x, y, w, h = 206, 174, 224, 4

    set_c(GRAPHITE, 0.42)
    rrect(x, y, w, h, 2)
    cairo_fill(cr)

    if ratio > 0 then
        local g = cairo_pattern_create_linear(x, y, x + w, y)
        cairo_pattern_add_color_stop_rgba(g, 0.00, BODHI_BRONZE[1], BODHI_BRONZE[2], BODHI_BRONZE[3], 0.55)
        cairo_pattern_add_color_stop_rgba(g, 1.00, LEMON_CHIFFON[1], LEMON_CHIFFON[2], LEMON_CHIFFON[3], 0.82)
        rrect(x, y, math.max(3, w * ratio), h, 2)
        cairo_set_source(cr, g)
        cairo_fill(cr)
        cairo_pattern_destroy(g)
    end

    local px = x + w * ratio
    set_c(state == 'playing' and CINNABAR or BODHI_BRONZE, 0.98)
    cairo_new_path(cr)
    cairo_arc(cr, px, y + h / 2, 3.2, 0, 2 * math.pi)
    cairo_fill(cr)
end

function conky_render_panel()
    if conky_window == nil or conky_window.display == nil then return end
    local w = tonumber(conky_window.width) or GRID_W
    local h = tonumber(conky_window.height) or GRID_H
    if w < 8 or h < 8 then return end
    local s = math.min(w / GRID_W, h / GRID_H)
    local ox = (w - GRID_W * s) / 2
    local oy = (h - GRID_H * s) / 2

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, w, h)
    if cs == nil then return end
    cr = cairo_create(cs)
    if cr == nil then cairo_surface_destroy(cs) return end

    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
    cairo_translate(cr, ox, oy)
    cairo_scale(cr, s, s)

    local d = read_status()
    local ratio = 0
    if d.active and d.duration > 0 then
        ratio = math.max(0, math.min(1, d.position / d.duration))
    end

    local title = d.active and d.title or 'No Music Playing'
    local artist = d.active and d.artist or 'Pianobar is idle'
    local album = (d.active and d.album ~= '') and d.album or ''
    local elapsed = d.active and format_time(d.position) or '--:--'
    local total = (d.active and d.duration > 0) and format_time(d.duration) or '--:--'

    paint_plate()
    text_at('音', 38, 31, 13, LEMON_CHIFFON, 0.82, 'center', true)
    text_at('楽', 38, 49, 13, LEMON_CHIFFON, 0.82, 'center', true)

    draw_art(d.active, d.state ~= 'playing')

    text_at('NOW PLAYING', 206, 32, 8.5, { 0.898, 0.894, 0.886 }, 0.98, 'left', true, 'DejaVu Sans Mono')
    state_seal(d.state)

    text_at(fit_text(title, 224, 'Noto Sans CJK JP', 18.5, true), 206, 78, 18.5, LEMON_CHIFFON, 0.96, 'left', true)
    text_at(fit_text(artist, 224, 'Noto Sans CJK JP', 13, false), 206, 104, 13, GRAPHITE, 0.98, 'left', false)
    text_at(fit_text(album, 224, 'Noto Sans CJK JP', 11, false), 206, 130, 11, { 0.898, 0.894, 0.886 }, 0.98, 'left', false)

    set_c(GRAPHITE, 0.30)
    cairo_set_line_width(cr, 0.8)
    cairo_new_path(cr)
    cairo_move_to(cr, 206, 148)
    cairo_line_to(cr, 430, 148)
    cairo_stroke(cr)

    progress_rail(ratio, d.state)
    text_at(elapsed, 206, 202, 10, LEMON_CHIFFON, 0.92, 'left', true, 'DejaVu Sans Mono')
    text_at(total, 430, 202, 10, GRAPHITE, 0.92, 'right', true, 'DejaVu Sans Mono')

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    cr = nil
end
