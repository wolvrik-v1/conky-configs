require 'cairo'

local HOME_DIR = os.getenv('HOME')
local CACHE_PATH = HOME_DIR .. '/.cache/conky/etched_weather.lua'
local ERROR_PATH = HOME_DIR .. '/.cache/conky/etched_weather.error'

local PANEL_WIDTH = 540
local PANEL_HEIGHT = 280
local X = 14
local MARGIN = 14

local cr = nil
local surface = nil

local COLORS = {
    cyan      = {0.10, 0.58, 0.58, 0.95},
    dot_cyan  = {0.00, 1.00, 0.98, 1.00},
    line_gray = {0.30, 0.30, 0.30, 0.28},
    text_gray = {0.52, 0.54, 0.55, 0.95},
    bright    = {0.78, 0.82, 0.84, 1.00}
}

local function clean(value)
    local text = tostring(value or '')
    text = text:gsub('[%c]', ' ')
    text = text:gsub('%s+', ' ')
    text = text:gsub('^%s+', '')
    text = text:gsub('%s+$', '')
    return text
end

local function finite_number(value)
    if type(value) ~= 'number' then
        return nil
    end

    if value ~= value
        or value == math.huge
        or value == -math.huge
    then
        return nil
    end

    return value
end

-- Read the Lua cache without executing it. This also works with older
-- unbracketed cache files.
local function table_block(source, key)
    local block = source:match(
        '%[%s*"' .. key .. '"%s*%]%s*=%s*(%b{})'
    )

    if block then
        return block
    end

    return source:match(
        '"' .. key .. '"%s*=%s*(%b{})'
    )
end

local function field(block, key, quoted)
    local bracketed =
        '%[%s*"' .. key .. '"%s*%]%s*=%s*'

    local plain =
        '"' .. key .. '"%s*=%s*'

    local suffix

    if quoted then
        suffix = '"([^"]*)"'
    else
        suffix = '([%-%d%.]+)'
    end

    return block:match(bracketed .. suffix)
        or block:match(plain .. suffix)
end

local function number_field(block, key)
    local value = field(block, key, false)

    if value then
        return tonumber(value)
    end

    return nil
end

local function string_field(block, key)
    return field(block, key, true) or ''
end

local function read_cache()
    local handle = io.open(CACHE_PATH, 'r')

    if not handle then
        return {
            location = 'WEST VIEW',
            updated_text = '--:--',
            current = {},
            daily = {}
        }
    end

    local source = handle:read('*a') or ''
    handle:close()

    local current_block = table_block(source, 'current') or ''
    local daily_block = table_block(source, 'daily') or ''

    local current = {
        temp = number_field(current_block, 'temp'),
        feels_like = number_field(current_block, 'feels_like'),
        humidity = number_field(current_block, 'humidity'),
        wind_speed = number_field(current_block, 'wind_speed'),
        wind_direction = string_field(
            current_block,
            'wind_direction'
        ),
        pop = number_field(current_block, 'pop'),
        sunrise_text = string_field(
            current_block,
            'sunrise_text'
        ),
        sunset_text = string_field(
            current_block,
            'sunset_text'
        ),
        condition = string_field(current_block, 'condition'),
        icon_id = number_field(current_block, 'icon_id')
    }

    local daily = {}
    local daily_source = daily_block or ''

    local inner = daily_source:match('^%s*{(.*)}%s*$') or daily_source

    for item in inner:gmatch('%b{}') do
        local day = string_field(item, 'day')

        if day and day ~= '' then
            table.insert(daily, {
                day = day,
                condition = string_field(item, 'condition'),
                icon_id = number_field(item, 'icon_id'),
                temp_min = number_field(item, 'temp_min'),
                temp_max = number_field(item, 'temp_max'),
                pop = number_field(item, 'pop')
            })
        end
    end

    local location = string_field(source, 'location')

    if location == '' then
        location = 'WEST VIEW'
    end

    return {
        location = location,
        updated_text = string_field(source, 'updated_text'),
        current = current,
        daily = daily
    }
end

local function read_error()
    local handle = io.open(ERROR_PATH, 'r')

    if not handle then
        return ''
    end

    local value = handle:read('*a') or ''
    handle:close()

    return clean(value)
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

    local new_cr = cairo_create(new_surface)

    if new_cr == nil then
        cairo_surface_destroy(new_surface)
        return nil, nil
    end

    return new_surface, new_cr
end

local function clear_surface()
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
    cairo_set_source_rgba(cr, 0, 0, 0, 0)
    cairo_paint(cr)
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
end

local function set_color(color)
    color = color or COLORS.text_gray

    cairo_set_source_rgba(
        cr,
        color[1],
        color[2],
        color[3],
        color[4]
    )
end

local function set_font(size, bold)
    cairo_select_font_face(
        cr,
        'Ubuntu',
        CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD
            or CAIRO_FONT_WEIGHT_NORMAL
    )

    cairo_set_font_size(cr, size)
end

local function text_extents(value)
    local extents = cairo_text_extents_t:create()

    if extents == nil then
        return {width = 0, x_bearing = 0}
    end

    cairo_text_extents(
        cr,
        tostring(value or ''),
        extents
    )

    return extents
end

local function put(value, x, y, size, bold, color, align)
    local text = clean(value)

    set_font(size, bold)

    local extents = text_extents(text)

    if align == 'right' then
        x = x - extents.width - extents.x_bearing
    elseif align == 'center' then
        x = x - extents.width / 2 - extents.x_bearing
    end

    set_color(color)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, text)
end

local function draw_line(x1, y1, x2, y2, color, width)
    set_color(color)
    cairo_set_line_width(cr, width or 1)
    cairo_move_to(cr, x1, y1)
    cairo_line_to(cr, x2, y2)
    cairo_stroke(cr)
end

local function draw_dot(center_x, center_y, radius, color)
    set_color(color)
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

-- Split a string into lines that fit within max_width using the current font.
local function wrap_words(value, max_width)
    local text = clean(value)

    if text == '' then
        return {''}
    end

    local lines = {}
    local current = ''

    for word in text:gmatch('%S+') do
        local candidate = current == '' and word
            or (current .. ' ' .. word)

        local extents = text_extents(candidate)

        if extents.width + extents.x_bearing > max_width then
            if current ~= '' then
                table.insert(lines, current)
            end

            current = word
        else
            current = candidate
        end
    end

    if current ~= '' then
        table.insert(lines, current)
    end

    return lines
end

-- Draw text wrapped to a maximum width, one line per step of line_height.
local function put_wrapped(value, x, y, max_width, size, bold, color, line_height)
    set_font(size, bold)

    local lines = wrap_words(value, max_width)

    for index, line in ipairs(lines) do
        put(
            line,
            x,
            y + (index - 1) * line_height,
            size,
            bold,
            color
        )
    end

    return #lines
end

local function draw_icon(id, x, y, size, color)
    local value = tonumber(id) or 0

    set_color(color or COLORS.text_gray)
    cairo_set_line_width(cr, math.max(1, size * 0.06))
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)

    local function circle(cx, cy, radius, fill)
        cairo_new_path(cr)
        cairo_arc(cr, cx, cy, radius, 0, 2 * math.pi)

        if fill then
            cairo_fill(cr)
        else
            cairo_stroke(cr)
        end
    end

    -- Clear sky: sun
    if value == 800 then
        circle(x, y, size * 0.20, false)

        for index = 0, 7 do
            local angle = index * math.pi / 4

            cairo_new_path(cr)
            cairo_move_to(
                cr,
                x + math.cos(angle) * size * 0.30,
                y + math.sin(angle) * size * 0.30
            )
            cairo_line_to(
                cr,
                x + math.cos(angle) * size * 0.43,
                y + math.sin(angle) * size * 0.43
            )
            cairo_stroke(cr)
        end

        return
    end

    -- Cloud: separate filled shapes, so no connecting line is drawn.
    circle(x - size * 0.18, y, size * 0.15, true)
    circle(x, y - size * 0.10, size * 0.21, true)
    circle(x + size * 0.18, y, size * 0.15, true)

    cairo_new_path(cr)
    cairo_rectangle(
        cr,
        x - size * 0.27,
        y - size * 0.03,
        size * 0.54,
        size * 0.13
    )
    cairo_fill(cr)

    -- Rain
    if value >= 500 and value < 600 then
        for _, offset in ipairs({-0.16, 0, 0.16}) do
            cairo_new_path(cr)
            cairo_move_to(
                cr,
                x + size * offset,
                y + size * 0.20
            )
            cairo_line_to(
                cr,
                x + size * offset - size * 0.06,
                y + size * 0.36
            )
            cairo_stroke(cr)
        end

    -- Snow
    elseif value >= 600 and value < 700 then
        for _, offset in ipairs({-0.15, 0, 0.15}) do
            circle(
                x + size * offset,
                y + size * 0.28,
                size * 0.035,
                true
            )
        end

    -- Thunder
    elseif value >= 200 and value < 300 then
        cairo_new_path(cr)
        cairo_move_to(
            cr,
            x + size * 0.08,
            y + size * 0.18
        )
        cairo_line_to(
            cr,
            x - size * 0.08,
            y + size * 0.28
        )
        cairo_line_to(
            cr,
            x + size * 0.02,
            y + size * 0.28
        )
        cairo_line_to(
            cr,
            x - size * 0.08,
            y + size * 0.42
        )
        cairo_stroke(cr)

    -- Fog
    elseif value >= 700 and value < 800 then
        for _, offset in ipairs({-0.08, 0.08}) do
            cairo_new_path(cr)
            cairo_move_to(
                cr,
                x - size * 0.22,
                y + size * offset
            )
            cairo_line_to(
                cr,
                x + size * 0.22,
                y + size * offset
            )
            cairo_stroke(cr)
        end

    -- Unknown condition
    else
        circle(x, y, size * 0.28, false)

        cairo_new_path(cr)
        cairo_move_to(
            cr,
            x - size * 0.10,
            y + size * 0.08
        )
        cairo_line_to(
            cr,
            x + size * 0.10,
            y + size * 0.08
        )
        cairo_stroke(cr)
    end
end
local function temp_string(value)
    local number = tonumber(value)

    if number ~= nil then
        return string.format('%.0f F', number)
    end

    return '-- F'
end

local function humidity_string(value)
    local number = tonumber(value)

    if number ~= nil then
        return string.format('%.0f%%', number)
    end

    return '--%'
end

local function wind_string(current)
    local speed = tonumber(current.wind_speed) or 0
    local direction = tostring(current.wind_direction or '')

    if speed < 0.05 then
        return 'CALM'
    end

    if direction == '' then
        return string.format('%.0f mph', speed)
    end

    return string.format('%.0f mph %s', speed, direction)
end

local function precip_string(value)
    local probability = tonumber(value) or 0

    if probability < 0 then
        probability = 0
    elseif probability > 1 then
        probability = 1
    end

    return string.format('%.0f%%', probability * 100)
end

local function clock_string(value)
    value = tostring(value or '')

    if value == '' then
        return '--:--'
    end

    return value
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
    local bottom = height - MARGIN
    local right = math.max(X + 400, math.min(width - MARGIN, 616))

    local data = read_cache()
    local current = data.current or {}
    local daily = data.daily or {}

    local has_temp = finite_number(current.temp) ~= nil
    local accent = has_temp and COLORS.cyan or COLORS.text_gray
    local value_color = has_temp and COLORS.bright
        or COLORS.text_gray

    ---------------------------------------------------------------------------
    -- Header
    ---------------------------------------------------------------------------

    put(
        'WEATHER',
        X,
        24,
        12,
        true,
        accent
    )

    draw_dot(right, 17, 3.5, COLORS.dot_cyan)

    local location = clean(data.location):upper()

    if location == '' then
        location = 'WEST VIEW'
    end

    put(
        location,
        X,
        46,
        11,
        false,
        COLORS.text_gray
    )

    local updated = clean(data.updated_text)

    if updated == '' then
        updated = '--:--'
    end

    put(
        'UPDATED ' .. updated,
        right,
        46,
        9,
        false,
        COLORS.text_gray,
        'right'
    )

    draw_line(
        X,
        60,
        right,
        60,
        COLORS.line_gray,
        1
    )

    ---------------------------------------------------------------------------
    -- Current conditions (left column) + section divider
    ---------------------------------------------------------------------------

    local cur_right = X + 104
    local main_bottom = 172

    put(
        'NOW',
        X,
        78,
        10,
        true,
        COLORS.text_gray
    )

    draw_icon(
        current.icon_id,
        X,
        92,
        26,
        accent
    )

    put(
        temp_string(current.temp),
        X + 42,
        94,
        24,
        true,
        value_color
    )

    local condition = clean(current.condition)

    if condition == '' then
        condition = 'UNKNOWN'
    end

    put_wrapped(
        condition,
        X,
        118,
        cur_right - X - 4,
        10,
        false,
        COLORS.text_gray,
        12
    )

    local today = daily[1] or {}

    put(
        string.format('H %.0f F', tonumber(today.temp_max) or 0),
        X,
        150,
        10,
        false,
        COLORS.text_gray
    )

    put(
        string.format('L %.0f F', tonumber(today.temp_min) or 0),
        X + 52,
        150,
        10,
        false,
        COLORS.text_gray
    )

    draw_line(
        cur_right + 8,
        64,
        cur_right + 8,
        main_bottom,
        COLORS.line_gray,
        1
    )

    ---------------------------------------------------------------------------
    -- Details (2x3 grid, middle)
    ---------------------------------------------------------------------------

    local det_x = cur_right + 30
    local det_pitch = 108
    local det_table = {
        {'FEELS', temp_string(current.feels_like)},
        {'HUMIDITY', humidity_string(current.humidity)},
        {'WIND', wind_string(current)},
        {'PRECIP', precip_string(current.pop)},
        {'SUNRISE', clock_string(current.sunrise_text)},
        {'SUNSET', clock_string(current.sunset_text)}
    }

    for row_index = 1, 2 do
        for col_index = 1, 3 do
            local entry = det_table[(row_index - 1) * 3 + col_index]

            if entry then
                local label_x = det_x + (col_index - 1) * det_pitch

                put(
                    entry[1],
                    label_x,
                    row_index == 1 and 82 or 134,
                    10,
                    true,
                    COLORS.text_gray
                )

                put(
                    entry[2],
                    label_x,
                    row_index == 1 and 104 or 156,
                    11,
                    false,
                    COLORS.text_gray
                )
            end
        end
    end

    draw_line(
        X,
        main_bottom,
        right,
        main_bottom,
        COLORS.line_gray,
        1
    )

    ---------------------------------------------------------------------------
    -- Five-day forecast (full-width row, below everything else)
    ---------------------------------------------------------------------------

    local fc_left = X
    local fc_width = right - fc_left
    local col_width = fc_width / 5

    for index = 1, 5 do
        local item = daily[index]
        local cell_x = fc_left + (index - 0.5) * col_width

        local day = '--'

        if item then
            day = clean(item.day)

            if day == '' then
                day = '--'
            elseif day:match('^[Tt]oday$') then
                day = 'NOW'
            else
                day = day:sub(1, 3)
            end
        end

        put(
            day,
            cell_x,
            190,
            10,
            false,
            COLORS.text_gray,
            'center'
        )

        if item then
            draw_icon(
                item.icon_id,
                cell_x,
                206,
                15,
                COLORS.text_gray
            )

            put(
                string.format('%.0f', tonumber(item.temp_max) or 0),
                cell_x,
                224,
                10,
                true,
                COLORS.bright,
                'center'
            )

            put(
                string.format('%.0f', tonumber(item.temp_min) or 0),
                cell_x,
                242,
                10,
                false,
                COLORS.text_gray,
                'center'
            )
        end
    end

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------

    cairo_destroy(cr)
    cairo_surface_destroy(surface)

    cr = nil
    surface = nil
end

-- Keep the alternate name available for older Conky configurations.
render_panel = conky_render_panel
