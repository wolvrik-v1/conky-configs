require 'cairo'

local HOME_DIR = os.getenv('HOME') or '.'
local CACHE_PATH = HOME_DIR .. '/.cache/conky/pianobar-widget.status'
local COVER_JPG  = HOME_DIR .. '/.config/pianobar/coverArt.jpg'
local COVER_PNG  = HOME_DIR .. '/.cache/conky/etched_pianobar_cover.png'
local COVER_MARKER = COVER_PNG .. '.mtime'

local STATUS_CMD = string.format(
    '${execi 1 /bin/cat "%s" 2>/dev/null}',
    CACHE_PATH
)

local STATUS_PATTERN = '^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$'

local PANEL_WIDTH = 440
local PANEL_HEIGHT = 290

local X = 24
local MARGIN = 24
local COVER_X = 24
local COVER_Y = 58
local COVER_SIZE = 120

local cr = nil
local surface = nil

-- Paused and stopped intentionally avoid bright yellow and red.
local COLORS = {
    cyan       = {0.00, 1.00, 0.98, 1.00},
    line_gray  = {0.30, 0.30, 0.30, 0.40},
    text_gray  = {0.47, 0.47, 0.47, 1.00},
    bright     = {0.82, 0.86, 0.88, 1.00},
    background = {0.025, 0.035, 0.045, 0.78},
    cover      = {0.045, 0.055, 0.065, 0.92},
    paused     = {0.18, 0.42, 0.43, 0.90},
    inactive   = {0.20, 0.22, 0.23, 0.90}
}

local function clean(value)
    return tostring(value or '')
        :gsub('[%c]', ' ')
        :gsub('%s+', ' ')
        :gsub('^%s+', '')
        :gsub('%s+$', '')
end

local function finite_number(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function read_cache_line()
    local handle = io.open(CACHE_PATH, 'r')

    if not handle then
        return ''
    end

    local value = handle:read('*l') or ''
    handle:close()

    return value
end

local function read_status()
    local raw = clean(read_cache_line())

    -- Fallback for Conky builds that do not need or support execi here.
    if raw == '' then
        raw = clean(conky_parse(STATUS_CMD) or '')
    end

    local title, artist, album, duration, position, state =
        raw:match(STATUS_PATTERN)

    if not title then
        raw = clean(read_cache_line())
        title, artist, album, duration, position, state =
            raw:match(STATUS_PATTERN)
    end

    if not title then
        return {
            title = '',
            artist = '',
            album = '',
            duration = 0,
            position = 0,
            state = 'stopped',
            active = false
        }
    end

    duration = tonumber(duration) or 0
    position = tonumber(position) or 0

    if not finite_number(duration) then
        duration = 0
    end

    if not finite_number(position) then
        position = 0
    end

    if duration < 0 then
        duration = 0
    end

    if position < 0 then
        position = 0
    end

    state = clean(state):lower()

    if state ~= 'playing'
        and state ~= 'paused'
        and state ~= 'waiting'
        and state ~= 'stopped'
    then
        state = 'stopped'
    end

    local active = state ~= 'stopped'
        and (title ~= '' or artist ~= '')

    return {
        title = clean(title),
        artist = clean(artist),
        album = clean(album),
        duration = duration,
        position = position,
        state = state,
        active = active
    }
end

local function utf8_chars(text)
    local characters = {}
    local index = 1
    text = tostring(text or '')

    while index <= #text do
        local byte = text:byte(index) or 0
        local count = 1

        if byte >= 240 then
            count = 4
        elseif byte >= 224 then
            count = 3
        elseif byte >= 194 then
            count = 2
        end

        if index + count - 1 > #text then
            count = 1
        end

        characters[#characters + 1] = text:sub(
            index,
            index + count - 1
        )

        index = index + count
    end

    return characters
end

local function set_font(family, size, bold)
    cairo_select_font_face(
        cr,
        family,
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL
    )

    cairo_set_font_size(cr, size)
end

local function measure(text)
    local extents = cairo_text_extents_t:create()

    cairo_text_extents(
        cr,
        tostring(text or ''),
        extents
    )

    return extents
end

local function width_of(text, family, size, bold)
    set_font(family, size, bold)
    return measure(text).width
end

local function fit_text(text, maximum_width, family, size, bold)
    text = tostring(text or '')

    if text == '' or maximum_width <= 0 then
        return ''
    end

    set_font(family, size, bold)

    local characters = utf8_chars(text)

    if #characters == 0 then
        return ''
    end

    local low = 0
    local high = #characters

    while low < high do
        local middle = math.floor((low + high + 1) / 2)
        local candidate = table.concat(
            characters,
            '',
            1,
            middle
        )

        if measure(candidate).width <= maximum_width then
            low = middle
        else
            high = middle - 1
        end
    end

    local result = table.concat(characters, '', 1, low)

    if low < #characters then
        result = result .. '…'
    end

    while result ~= '' and measure(result).width > maximum_width do
        local result_characters = utf8_chars(result)
        table.remove(result_characters)
        result = table.concat(result_characters, '')
    end

    return result
end

local function make_context()
    if conky_window == nil
        or conky_window.display == nil
        or conky_window.drawable == nil
        or conky_window.visual == nil
    then
        return nil, nil
    end

    local width = tonumber(conky_window.width) or PANEL_WIDTH
    local height = tonumber(conky_window.height) or PANEL_HEIGHT

    local new_surface = cairo_xlib_surface_create(
        conky_window.display,
        conky_window.drawable,
        conky_window.visual,
        width,
        height
    )

    if new_surface == nil then
        return nil, nil
    end

    local context = cairo_create(new_surface)

    if context == nil then
        cairo_surface_destroy(new_surface)
        return nil, nil
    end

    return new_surface, context
end

local function clear_surface()
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
    cairo_set_source_rgba(cr, 0, 0, 0, 0)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
end

local function draw_text(text, x, y, family, size, bold, color)
    color = color or COLORS.text_gray

    set_font(family, size, bold)

    cairo_set_source_rgba(
        cr,
        color[1],
        color[2],
        color[3],
        color[4]
    )

    cairo_move_to(cr, x, y)
    cairo_show_text(cr, tostring(text or ''))
end

local function draw_line(x1, y1, x2, y2, color, width)
    color = color or COLORS.line_gray

    cairo_set_source_rgba(
        cr,
        color[1],
        color[2],
        color[3],
        color[4]
    )

    cairo_set_line_width(cr, width or 1)
    cairo_move_to(cr, x1, y1)
    cairo_line_to(cr, x2, y2)
    cairo_stroke(cr)
end

local function draw_dot(center_x, center_y, radius, color)
    color = color or COLORS.cyan

    cairo_set_source_rgba(
        cr,
        color[1],
        color[2],
        color[3],
        color[4]
    )

    cairo_arc(
        cr,
        center_x,
        center_y,
        radius,
        0,
        2 * math.pi
    )

    cairo_fill(cr)
end

local function draw_background(width, height)
    -- Minimal style: transparent panel, no tint, no outline rectangle.
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function file_mtime(path)
    local handle = io.popen(
        'stat -c %Y ' .. shell_quote(path) .. ' 2>/dev/null'
    )

    if not handle then
        return 0
    end

    local value = tonumber(handle:read('*a') or '') or 0
    handle:close()

    return value
end

local function file_exists(path)
    local handle = io.open(path, 'rb')

    if handle then
        handle:close()
        return true
    end

    return false
end

local function ensure_art()
    local jpg_mtime = file_mtime(COVER_JPG)

    if jpg_mtime <= 0 then
        os.remove(COVER_PNG)
        os.remove(COVER_MARKER)
        return
    end

    local marker_handle = io.open(COVER_MARKER, 'r')
    local marker_value = ''

    if marker_handle then
        marker_value = marker_handle:read('*l') or ''
        marker_handle:close()
    end

    if marker_value ~= tostring(jpg_mtime) or not file_exists(COVER_PNG) then
        os.remove(COVER_PNG)

        local command = string.format(
            'convert %s -resize 240x240^ -gravity center '
                .. '-extent 240x240 %s 2>/dev/null',
            shell_quote(COVER_JPG),
            shell_quote(COVER_PNG)
        )

        os.execute(command)

        if file_exists(COVER_PNG) then
            marker_handle = io.open(COVER_MARKER, 'w')

            if marker_handle then
                marker_handle:write(tostring(jpg_mtime))
                marker_handle:close()
            end
        else
            os.remove(COVER_MARKER)
        end
    end
end

local function draw_placeholder()
    local center_x = COVER_X + COVER_SIZE / 2
    local center_y = COVER_Y + COVER_SIZE / 2

    -- Low-light standby artwork. No bright status color is used here.
    cairo_set_source_rgba(cr, 0.035, 0.045, 0.05, 1.00)
    cairo_rectangle(
        cr,
        COVER_X + 1,
        COVER_Y + 1,
        COVER_SIZE - 2,
        COVER_SIZE - 2
    )
    cairo_fill(cr)

    cairo_set_source_rgba(cr, 0.18, 0.21, 0.22, 0.82)
    cairo_set_line_width(cr, 1)
    cairo_arc(cr, center_x, center_y, 38, 0, 2 * math.pi)
    cairo_stroke(cr)

    local bars = { 9, 18, 28, 18, 9 }

    for index, height in ipairs(bars) do
        local x = center_x + (index - 3) * 11

        cairo_set_source_rgba(cr, 0.22, 0.25, 0.26, 0.72)
        cairo_rectangle(
            cr,
            x - 2,
            center_y - height / 2,
            4,
            height
        )
        cairo_fill(cr)
    end
end

local function draw_cover_frame(show_album_art, dim_art)
    cairo_rectangle(
        cr,
        COVER_X,
        COVER_Y,
        COVER_SIZE,
        COVER_SIZE
    )

    cairo_set_source_rgba(
        cr,
        COLORS.cover[1],
        COLORS.cover[2],
        COLORS.cover[3],
        COLORS.cover[4]
    )

    cairo_fill(cr)

    if show_album_art then
        ensure_art()

        local art = nil

        if file_exists(COVER_PNG) then
            local loaded_ok, loaded_art = pcall(
                cairo_image_surface_create_from_png,
                COVER_PNG
            )

            if loaded_ok then
                art = loaded_art
            end
        end

        local has_art = false

        if art then
            local width_ok, iw = pcall(
                cairo_image_surface_get_width,
                art
            )

            local height_ok, ih = pcall(
                cairo_image_surface_get_height,
                art
            )

            if width_ok
                and height_ok
                and type(iw) == 'number'
                and type(ih) == 'number'
                and iw > 0
                and ih > 0
            then
                has_art = true

                cairo_save(cr)
                cairo_rectangle(
                    cr,
                    COVER_X,
                    COVER_Y,
                    COVER_SIZE,
                    COVER_SIZE
                )
                cairo_clip(cr)

                cairo_translate(cr, COVER_X, COVER_Y)
                cairo_scale(cr, COVER_SIZE / iw, COVER_SIZE / ih)
                cairo_set_source_surface(cr, art, 0, 0)
                cairo_pattern_set_filter(
                    cairo_get_source(cr),
                    CAIRO_FILTER_BILINEAR
                )
                cairo_paint(cr)
                cairo_restore(cr)
            end

            cairo_surface_destroy(art)
        end

        if has_art and dim_art then
            cairo_set_source_rgba(cr, 0.02, 0.03, 0.035, 0.58)
            cairo_rectangle(
                cr,
                COVER_X,
                COVER_Y,
                COVER_SIZE,
                COVER_SIZE
            )
            cairo_fill(cr)
        end

        if not has_art then
            draw_placeholder()
        end
    else
        -- Do not load or display cached album art while stopped.
        draw_placeholder()
    end

    cairo_rectangle(
        cr,
        COVER_X,
        COVER_Y,
        COVER_SIZE,
        COVER_SIZE
    )

    cairo_set_source_rgba(
        cr,
        COLORS.line_gray[1],
        COLORS.line_gray[2],
        COLORS.line_gray[3],
        COLORS.line_gray[4]
    )

    cairo_set_line_width(cr, 1)
    cairo_stroke(cr)
end

local function draw_progress(x, y, width, ratio, color)
    local safe_ratio = 0

    if type(ratio) == 'number' and finite_number(ratio) then
        safe_ratio = math.max(0, math.min(1, ratio))
    end

    local end_x = x + (width * safe_ratio)

    draw_line(
        x,
        y,
        x + width,
        y,
        COLORS.line_gray,
        3
    )

    if safe_ratio > 0 then
        draw_line(
            x,
            y,
            end_x,
            y,
            color,
            3
        )
    end

    draw_dot(end_x, y, 4, color)
end

local function format_time(value)
    local seconds = tonumber(value) or 0

    if not finite_number(seconds) then
        seconds = 0
    end

    seconds = math.max(0, seconds)

    local total = math.floor(seconds)
    local minutes = math.floor(total / 60)
    local remainder = total % 60

    return string.format('%d:%02d', minutes, remainder)
end

local function state_style(state, active)
    state = tostring(state or ''):lower()

    if active and state == 'playing' then
        return COLORS.cyan, 'PLAYING'
    elseif active and state == 'paused' then
        return COLORS.paused, 'PAUSED'
    elseif active and state == 'waiting' then
        return COLORS.inactive, 'WAITING'
    elseif state == 'stopped' then
        return COLORS.inactive, 'STOPPED'
    end

    return COLORS.inactive, 'NO MUSIC'
end

function conky_render_panel()
    surface, cr = make_context()

    if cr == nil then
        return
    end

    cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    clear_surface()

    local width = tonumber(conky_window.width) or PANEL_WIDTH
    local height = tonumber(conky_window.height) or PANEL_HEIGHT
    local right = math.max(X + 120, width - MARGIN)

    local data = read_status()
    local state_color, status_label = state_style(
        data.state,
        data.active
    )

    local is_playing = data.active and data.state == 'playing'
    local header_label = is_playing and 'NOW PLAYING' or 'PIANOBAR'
    local track_visible = data.active and data.state ~= 'stopped'
    local content_color = is_playing and COLORS.bright or COLORS.text_gray

    ---------------------------------------------------------------------------
    -- Panel background
    ---------------------------------------------------------------------------

    draw_background(width, height)

    ---------------------------------------------------------------------------
    -- Header
    ---------------------------------------------------------------------------

    draw_text(
        header_label,
        X,
        29,
        'Ubuntu',
        10,
        true,
        state_color
    )

    draw_dot(right, 21, 3.5, state_color)
    draw_line(X, 43, right, 43, COLORS.line_gray, 1)

    ---------------------------------------------------------------------------
    -- Cover art frame
    ---------------------------------------------------------------------------

    draw_cover_frame(track_visible, not is_playing)	
    ---------------------------------------------------------------------------
    -- Metadata
    ---------------------------------------------------------------------------

    local text_x = 176
    local content_width = math.max(40, right - text_x)

    local title = track_visible and data.title or 'No Music Playing'

    local artist = track_visible and data.artist
        or 'Pianobar is not reporting a track'

    local album_line = 'ALBUM   —'

    if track_visible and data.album ~= '' then
        album_line = 'ALBUM   ' .. data.album
    end

    draw_text(
        'TRACK',
        text_x,
        63,
        'Ubuntu',
        9,
        true,
        COLORS.text_gray
    )

    draw_text(
        fit_text(title, content_width, 'Ubuntu', 18, false),
        text_x,
        86,
        'Ubuntu',
        18,
        false,
        content_color
    )

    draw_text(
        'ARTIST',
        text_x,
        109,
        'Ubuntu',
        9,
        true,
        COLORS.text_gray
    )

    draw_text(
        fit_text(artist, content_width, 'Ubuntu', 14, false),
        text_x,
        130,
        'Ubuntu',
        14,
        false,
        COLORS.text_gray
    )

    draw_text(
        'ALBUM',
        text_x,
        153,
        'Ubuntu',
        9,
        true,
        COLORS.text_gray
    )

    draw_text(
        fit_text(album_line, content_width, 'Ubuntu', 11, false),
        text_x,
        174,
        'Ubuntu',
        11,
        false,
        COLORS.text_gray
    )

    ---------------------------------------------------------------------------
    -- Cairo progress bar
    ---------------------------------------------------------------------------

    draw_text(
        'PROGRESS',
        X,
        201,
        'Ubuntu',
        9,
        true,
        COLORS.text_gray
    )

    local ratio = 0

    if track_visible and data.duration > 0 then
        ratio = math.max(
            0,
            math.min(1, data.position / data.duration)
        )
    end

    draw_progress(
        X,
        213,
        right - X,
        ratio,
        state_color
    )

    local elapsed_text = '--:--'
    local total_text = '--:--'

    if track_visible then
        elapsed_text = format_time(data.position)

        if data.duration > 0 then
            total_text = format_time(data.duration)
        end
    end

    draw_text(
        elapsed_text,
        X,
        241,
        'DS-Digital',
        15,
        true,
        COLORS.text_gray
    )

    local total_width = width_of(
        total_text,
        'DS-Digital',
        15,
        true
    )

    draw_text(
        total_text,
        right - total_width,
        241,
        'DS-Digital',
        15,
        true,
        COLORS.text_gray
    )

    ---------------------------------------------------------------------------
    -- Footer
    ---------------------------------------------------------------------------

    draw_line(X, 256, right, 256, COLORS.line_gray, 1)

    draw_text(
        'PIANOBAR',
        X,
        271,
        'Ubuntu',
        9,
        true,
        COLORS.text_gray
    )

    local status_width = width_of(
        status_label,
        'Ubuntu',
        9,
        true
    )

    draw_text(
        status_label,
        right - status_width,
        271,
        'Ubuntu',
        9,
        true,
        state_color
    )

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------

    cairo_destroy(cr)
    cairo_surface_destroy(surface)

    cr = nil
    surface = nil
end

-- Auto-start the status tracker once per widget launch. It is flock-guarded,
-- so double-spawning (e.g. across conky restarts) is harmless.
local function spawn_control()
    local dir = HOME_DIR .. '/.config/etched-pianobar'
    os.execute(string.format(
        'pgrep -f "etched-pianobar/cont[r]ol\\.py$" >/dev/null 2>&1 || '
            .. 'setsid %s/control.py </dev/null '
            .. '>>%s/control.log 2>&1 &',
        dir, dir
    ))
end
spawn_control()
