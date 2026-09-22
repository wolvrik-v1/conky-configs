require 'cairo'

-- Detect the active wireless interface (avoid hardcoding a MAC-derived name).
local WDEV = 'wlan0'
for line in io.lines('/proc/net/wireless') do
    local name = line:match('^%s*([%w]+):%s+')
    if name then WDEV = name break end
end

function conky_render_panel()
    if conky_window == nil then return end
    
    local cs = cairo_xlib_surface_create(
        conky_window.display, 
        conky_window.drawable, 
        conky_window.visual, 
        conky_window.width, 
        conky_window.height
    )
    local cr = cairo_create(cs)
    
    -- Color Palette
    local alert_yellow = {1.0, 1.0, 0.0, 1.0}
    local alert_red    = {1.0, 0.22, 0.22, 1.0}
    local track_cyan   = {0.0, 1.0, 0.98, 1.0}
    local line_gray    = {0.3, 0.3, 0.3, 0.4}
    local text_gray    = {0.47, 0.47, 0.47, 1.0}

    -- Metric Fetching
    local time_str    = conky_parse("${time %I:%M}")
    local cpu         = tonumber(conky_parse("${cpu cpu0}")) or 0
    local ram         = tonumber(conky_parse("${memperc}")) or 0
    local temp        = tonumber(conky_parse("${hwmon 3 temp 1}")) or 0
    local system      = tonumber(conky_parse("${fs_free_perc /}")) or 0
    local home        = tonumber(conky_parse("${fs_free_perc /home}")) or 0
    local up_speed    = conky_parse("${upspeedf " .. WDEV .. "}") or "0.0"
    local down_speed  = conky_parse("${downspeedf " .. WDEV .. "}") or "0.0"
    
    local updates_str = conky_parse("${exec tail -n 1 ~/.up 2>/dev/null}") or "0"
    local updates     = tonumber(updates_str:match("%d+")) or 0

    local hour        = tonumber(conky_parse("${time %H}")) or 0
    local is_pm       = hour >= 12

    -- Helper Functions
    local function draw_text(text, x, y, font_name, font_size, is_bold, color)
        cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4])
        local weight = is_bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL
        cairo_select_font_face(cr, font_name, CAIRO_FONT_SLANT_NORMAL, weight)
        cairo_set_font_size(cr, font_size)
        cairo_move_to(cr, x, y)
        cairo_show_text(cr, text)
    end

    local function draw_dot(center_x, center_y, radius, color)
        cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4])
        cairo_arc(cr, center_x, center_y, radius, 0, 2 * math.pi)
        cairo_fill(cr)
    end

    local function draw_line(x1, y1, x2, y2, color)
        cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4])
        cairo_set_line_width(cr, 1.2)
        cairo_move_to(cr, x1, y1)
        cairo_line_to(cr, x2, y2)
        cairo_stroke(cr)
    end

    ---------------------------------------------------------------------------
    -- CANVAS RENDERING (Scaled ~1.4x)
    ---------------------------------------------------------------------------

    -- 0. Clock & AM/PM (True Center Alignment)
    -- Calculate centered X position for dynamic clock digits
    cairo_select_font_face(cr, "Ubuntu", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr, 42)
    local extents = cairo_text_extents_t:create()
    cairo_text_extents(cr, time_str, extents)
    local clock_x = (conky_window.width - extents.width) / 2 - extents.x_bearing

    -- Draw Centered Clock
    draw_text(time_str, clock_x, 43, "Ubuntu", 42, true, {1.0, 1.0, 1.0, 1.0})

    -- Draw Centered AM / PM Labels
    draw_text("AM", 38, 66, "Ubuntu", 11, false, text_gray)
    draw_text("PM", 84, 66, "Ubuntu", 11, false, text_gray)

    -- Centered AM/PM Indicator Dot
    local am_pm_x = is_pm and 92 or 46
    draw_dot(am_pm_x, 78, 3.0, track_cyan)

    -- Centered Divider Line
    draw_line(20, 94, 120, 94, line_gray)

    -- 1. CPU Usage
    draw_text("Cpu", 14, 116, "Ubuntu", 12, false, text_gray)
    draw_text(cpu .. "%", 46, 142, "Ubuntu", 24, true, text_gray)
    draw_line(28, 156, 118, 156, line_gray)
    local cpu_x = 28 + ((cpu / 100) * 90)
    local cpu_color = cpu > 80 and alert_red or (cpu > 50 and alert_yellow or track_cyan)
    draw_dot(cpu_x, 156, 3.5, cpu_color)
    draw_line(45, 178, 128, 178, line_gray)

    -- 2. RAM Usage
    draw_text("Ram", 14, 200, "Ubuntu", 12, false, text_gray)
    draw_text(ram .. "%", 46, 226, "Ubuntu", 24, true, text_gray)
    draw_line(28, 240, 118, 240, line_gray)
    local ram_x = 28 + ((ram / 100) * 90)
    local ram_color = ram > 80 and alert_red or (ram > 50 and alert_yellow or track_cyan)
    draw_dot(ram_x, 240, 3.5, ram_color)
    draw_line(45, 262, 128, 262, line_gray)

    -- 3. CPU Temp
    draw_text("Cpu", 14, 284, "Ubuntu", 12, false, text_gray)
    draw_text(temp .. " C", 32, 312, "Ubuntu", 22, true, text_gray)
    draw_text("Temp", 96, 308, "Ubuntu", 11, false, text_gray)
    local temp_color = temp > 55 and alert_red or (temp > 45 and alert_yellow or track_cyan)
    draw_dot(114, 324, 3.5, temp_color)
    draw_line(68, 340, 128, 340, line_gray)

    -- 4. System Free
    draw_text("System", 14, 362, "Ubuntu", 12, false, text_gray)
    draw_text(system .. "%", 32, 390, "Ubuntu", 22, true, text_gray)
    draw_text("Free", 98, 386, "Ubuntu", 11, false, text_gray)
    local sys_color = system < 15 and alert_red or (system < 35 and alert_yellow or track_cyan)
    draw_dot(114, 402, 3.5, sys_color)
    draw_line(62, 418, 128, 418, line_gray)

    -- 5. Home Free
    draw_text("Home", 14, 440, "Ubuntu", 12, false, text_gray)
    draw_text(home .. "%", 32, 468, "Ubuntu", 22, true, text_gray)
    draw_text("Free", 98, 464, "Ubuntu", 11, false, text_gray)
    local home_color = home < 15 and alert_red or (home < 35 and alert_yellow or track_cyan)
    draw_dot(114, 480, 3.5, home_color)
    draw_line(62, 496, 128, 496, line_gray)

    -- 6. Net (Up & Down)
    draw_text("Net", 14, 518, "Ubuntu", 12, false, text_gray)
    draw_text(up_speed, 30, 544, "Ubuntu", 20, true, text_gray)
    draw_text("Up", 106, 532, "Ubuntu", 11, false, text_gray)
    draw_dot(114, 548, 3.5, track_cyan)

    draw_text(down_speed, 30, 580, "Ubuntu", 20, true, text_gray)
    draw_text("Down", 92, 568, "Ubuntu", 11, false, text_gray)
    draw_dot(114, 584, 3.5, track_cyan)
    draw_line(56, 602, 128, 602, line_gray)

    -- 7. Packages / Update
    draw_text("Update", 14, 624, "Ubuntu", 12, false, text_gray)
    draw_text(tostring(updates), 36, 652, "Ubuntu", 24, true, text_gray)
    draw_text("PACKAGES", 68, 650, "Ubuntu", 10, true, text_gray)
    draw_text("New", 98, 672, "Ubuntu", 11, false, text_gray)
    local update_color = updates > 0 and alert_red or track_cyan
    draw_dot(114, 688, 3.5, update_color)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
