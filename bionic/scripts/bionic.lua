require 'cairo'

-- Bionic / "Steel" reimagined (Mucas 2010 -> modern Lua/Cairo).
-- Everything procedural: brushed steel plate, recessed dial wells and the
-- wlourf-style sector rings are all drawn here, centered on the wells, so
-- alignment can never drift on any machine/user.

-- Well centres taken verbatim from the ORIGINAL rings.lua (Mucas 2010) --
-- they are expressed on the ORIGINAL 160x590 design grid. The regenerated
-- plate (pix/bg.png, 243x887) redraws every well at ~1.5x those grid
-- positions, so KX/KY (art_size / design_grid) remap them onto the art
-- below. This is the ground truth; do NOT "improve" these numbers.

local GRID_W = 160
local GRID_H = 590
local DIALS = {
  { cx=49.5, cy=93.5,  r=18, th=5, sn=30, gap=1, c1={0.42,0.95,0.45}, c2={1.0,0.30,0.30}, max=100, get='cpu'  },
  { cx=103.5,cy=189,   r=18, th=5, sn=30, gap=1, c1={0.42,0.95,0.45}, c2={1.0,0.30,0.30}, max=100, get='mem'  },
  { cx=57.5, cy=274.5, r=18, th=5, sn=30, gap=1, c1={1.0,0.90,0.20}, c2={0.35,0.50,1.0}, max=100, get='wifi' },
  -- time ring trio (same center, drawn separately; no label)
  { cx=112.5,cy=348.5, r=18, th=3, sn=30, gap=1, c1={0.42,0.95,0.45}, c2={0.42,0.95,0.45}, max=60,  get='sec'  },
  { cx=112.5,cy=348.5, r=14, th=3, sn=30, gap=1, c1={1.0,0.90,0.20}, c2={1.0,0.90,0.20}, max=60,  get='min'  },
  { cx=112.5,cy=348.5, r=10, th=3, sn=6,  gap=1, c1={1.0,0.30,0.30}, c2={1.0,0.30,0.30}, max=12,  get='hr'   },
  -- battery: tightened (r 18->15.5) and lifted so the ring seats on the engraved well face
  { cx=70,   cy=426,   r=15.5, th=5, sn=30, gap=1, c1={1.0,0.30,0.30}, c2={0.42,0.95,0.45}, max=100, get='bat'  },
  { cx=96,   cy=513.5, r=18, th=5, sn=30, gap=1, c1={1.0,0.90,0.20}, c2={1.0,0.30,0.30}, max=100, get='vol'  },
}

-- the ORIGINAL plate artwork (160x590). Keep it as-is.
local BG_PATH = os.getenv('HOME') .. '/.conky/bionic/pix/bg-blue2.png'

local F_RINGS = 'hooge 05_54'
local F_MONO  = 'DejaVu Sans Mono'
local F_SANS  = 'DejaVu Sans'

local TXT_BRIGHT = {0xf2,0xf3,0xf5}
local TXT_GREY   = {0x8b,0x8e,0x94}
local TXT_DIM    = {0x55,0x57,0x5b}

local net_prev = nil
local net_t    = 0

local BG_SURF = nil
local BG_W, BG_H = 0, 0

local function load_bg()
  local ok, err = pcall(function()
    BG_SURF = cairo_image_surface_create_from_png(BG_PATH)
  end)
  if not ok or not BG_SURF or cairo_image_surface_get_width(BG_SURF) < 8 then
    BG_SURF = nil
    return
  end
  BG_W = cairo_image_surface_get_width(BG_SURF)
  BG_H = cairo_image_surface_get_height(BG_SURF)
end
load_bg()

-- art/grid mapping: the redesigned plate redraws the 160x590 design at its
-- own pixel size; derive the per-axis factor so dials/text land on the wells.
local KX = (BG_W and BG_W > 0) and BG_W/GRID_W or 1.518
local KY = (BG_H and BG_H > 0) and BG_H/GRID_H or 1.503
local KS = (KX + KY)/2

-- paint the plate image to fill the window (preserve aspect, keep native look)
local function paint_bg(cr, w, h)
  if not BG_SURF then return end
  local s = math.min(w/BG_W, h/BG_H)
  local bx = (w - BG_W*s)/2
  local by = (h - BG_H*s)/2
  cairo_save(cr)
  cairo_translate(cr, bx, by)
  cairo_scale(cr, s, s)
  cairo_set_source_surface(cr, BG_SURF, 0, 0)
  cairo_paint(cr)
  cairo_restore(cr)
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function cset(cr, col, a)
  cairo_set_source_rgba(cr, (col[1] or 0)/255, (col[2] or 0)/255, (col[3] or 0)/255, a or 1)
end

local function lerp_col(c1, c2, t)
  return { c1[1]+(c2[1]-c1[1])*t, c1[2]+(c2[2]-c1[2])*t, c1[3]+(c2[3]-c1[3])*t }
end

local function draw_text(cr, cx, cy, str, size, col, alpha, font, align, vcenter)
  if not str or str=='' then return end
  cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, str, ext)
  local x = cx
  if align=='center' then x = cx - ext.width/2
  elseif align=='right' then x = cx - ext.width end
  local ty
  if vcenter then
    ty = cy - ext.y_bearing - ext.height/2
  else
    ty = cy + ext.height*(0.85)
  end
  cairo_move_to(cr, x, ty)
  cset(cr, col, alpha or 1)
  cairo_show_text(cr, str)
end

-- text with a soft dark shadow (readable over engraved/bright plate zones)
local function draw_text_shadow(cr, cx, cy, str, size, col, alpha, font, align, shadow)
  cairo_save(cr)
  if shadow then
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, str, ext)
    local x = cx
    if align=='center' then x = cx - ext.width/2
    elseif align=='right' then x = cx - ext.width end
    local ty = cy + ext.height*(0.85)
    -- offset shadow pass
    cairo_move_to(cr, x+shadow[1], ty+shadow[2])
    cairo_set_source_rgba(cr, 0.02, 0.02, 0.03, 0.85)
    cairo_show_text(cr, str)
  end
  cairo_restore(cr)
  draw_text(cr, cx, cy, str, size, col, alpha, font, align)
end

-- rounded-rect path helper
local function draw_roundrect(cr, x, y, w, h, r)
  r = r or math.min(w, h)/4
  cairo_new_path(cr)
  cairo_move_to(cr, x+r, y)
  cairo_line_to(cr, x+w-r, y)
  cairo_arc(cr, x+w-r, y+r, r, -math.pi/2, 0)
  cairo_line_to(cr, x+w, y+h-r)
  cairo_arc(cr, x+w-r, y+h-r, r, 0, math.pi/2)
  cairo_line_to(cr, x+r, y+h)
  cairo_arc(cr, x+r, y+h-r, r, math.pi/2, math.pi)
  cairo_line_to(cr, x, y+r)
  cairo_arc(cr, x+r, y+r, r, math.pi, 3*math.pi/2)
  cairo_close_path(cr)
end

-- date: a subtle dark rounded shading plate sized to the text, then the
-- bright shadowed text on top (keeps it readable over the engraved pill)
local function draw_date(cr, cx, cy, str, size, col, font)
  cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, str, ext)
  local padX = 5*size/6
  local padY = 3.2*size/6
  local bw = ext.width + 2*padX
  local bh = ext.height + 2*padY
  local bxx = cx - bw/2
  local byy = cy + ext.height*0.85 - ext.height/2 - bh/2
  -- dark shade plate
  draw_roundrect(cr, bxx, byy, bw, bh, 4*size/6)
  cset(cr, {0x05,0x07,0x0b}, 0.55)
  cairo_fill(cr)
  cset(cr, {0x02,0x03,0x05}, 0.65)
  draw_roundrect(cr, bxx, byy, bw, bh, 4*size/6)
  cairo_set_line_width(cr, 1)
  cairo_stroke(cr)
  -- text with dark shadow
  draw_text_shadow(cr, cx, cy, str, size, col, 1, font, 'center', {1*size/6, 1.2*size/6})
end

-- scrolling ticker clipped inside a pill (stadium) shape box
local tick = { text='', offset=0 }
local function pill_path(cr, x, y, w, h, r, S)
  if r > h/2 then r = h/2 end
  if r > w/2 then r = w/2 end
  local seg = 10
  local function arc(cx, cy, a1, a2)
    for i = 1, seg do
      local a = a1 + (a2-a1)*i/seg
      cairo_line_to(cr, cx + r*math.cos(a), cy + r*math.sin(a))
    end
  end
  cairo_new_path(cr)
  cairo_move_to(cr, x+r, y)
  cairo_line_to(cr, x+w-r, y)
  if r > 0 then arc(x+w-r, y+r, -math.pi/2, 0) end
  cairo_line_to(cr, x+w, y+h-r)
  if r > 0 then arc(x+w-r, y+h-r, 0, math.pi/2) end
  cairo_line_to(cr, x+r, y+h)
  if r > 0 then arc(x+r, y+h-r, math.pi/2, math.pi) end
  cairo_line_to(cr, x, y+r)
  if r > 0 then arc(x+r, y+r, math.pi, 3*math.pi/2) end
  cairo_close_path(cr)
end
-- subtle dark fill behind text on the bright engraved oval (same language as
-- draw_date's shade plate, but lighter so the metal still shows). radius
-- defaults to a full stadium; pass a small radius for a gentle slab.
local function pill_shade(cr, x, y, w, h, alpha, radius)
  radius = radius or h/2
  cairo_save(cr)
  cairo_new_path(cr)
  pill_path(cr, x, y, w, h, radius)
  cset(cr, {0x05,0x07,0x0b}, alpha)
  cairo_fill(cr)
  cset(cr, {0x02,0x03,0x05}, 0.30)
  cairo_set_line_width(cr, 1)
  cairo_stroke(cr)
  cairo_restore(cr)
end

local function scroll_text(cr, boxx, boxy, boxw, boxh, str, size, col, alpha, font, S)
  if not str or str=='' then return end
  cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, size)
  local ext = cairo_text_extents_t:create()
  cairo_text_extents(cr, str, ext)
  if tick.text ~= str then
    tick.text = str
    tick.offset = 0
  end
  local speed = 8*S          -- grid per second (scaled)
  local gap = 12*S
  local period = ext.width + boxw + 2*gap
  tick.offset = (tick.offset + speed*0.2) % period
  local x0 = boxx + boxw + gap - tick.offset
  cairo_save(cr)
  pill_path(cr, boxx, boxy, boxw, boxh, boxh/2, S)
  cairo_clip(cr)
  cairo_move_to(cr, x0, boxy + boxh/2 - ext.y_bearing - ext.height/2 + ext.height*0.15)
  cset(cr, col, alpha or 1)
  cairo_show_text(cr, str)
  cairo_restore(cr)
end

-- wlourf-style sector ring (stroked arcs, round caps)
local function sector_ring(cr, cx, cy, r, th, sn, gap, c1, c2, frac, S)
  frac = clamp(frac, 0, 1)
  local step = 2*math.pi/sn
  local ga = math.atan(gap/(2*r*S))
  cairo_set_line_width(cr, th*S)
  cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
  -- background
  cairo_set_source_rgba(cr, 0.85, 0.88, 0.95, 0.10)
  for i=0,sn-1 do
    local a0 = -math.pi/2 + i*step
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, r*S, a0+ga, a0+step-ga)
    cairo_stroke(cr)
  end
  -- foreground (color sweeps c1->c2 across sectors)
  local fullSec = math.floor(frac*sn)
  for i=1,fullSec do
    local t = (i-1)/(sn-1)
    local col = lerp_col(c1, c2, t)
    cairo_set_source_rgba(cr, col[1], col[2], col[3], 0.6)
    local a0 = -math.pi/2 + (i-1)*step
    cairo_new_path(cr)
    cairo_arc(cr, cx, cy, r*S, a0+ga, a0+step-ga)
    cairo_stroke(cr)
  end
  local rem = frac*sn - fullSec
  if rem > 0.02 then
    local i = fullSec+1
    local t = (i-1)/(sn-1)
    local col = lerp_col(c1, c2, t)
    cairo_set_source_rgba(cr, col[1], col[2], col[3], 0.6)
    local a0 = -math.pi/2 + (i-1)*step
    local a1 = a0 + step*rem
    local a1s = math.max(a0+ga, a1-ga)
    if a1s > a0+ga then
      cairo_new_path(cr)
      cairo_arc(cr, cx, cy, r*S, a0+ga, a1s)
      cairo_stroke(cr)
    end
  end
end

local function read_net()
  local rx, tx = 0, 0
  local f = io.open('/proc/net/dev', 'r')
  if f then
    for line in f:lines() do
      if line:find('wlx', 1) then
        local b = tonumber(line:match(':%s*(%d+)'))
        local t = tonumber(line:match(':%s*%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)'))
        if b then rx = b end
        if t then tx = t end
      end
    end
    f:close()
  end
  return rx, tx
end

local function read_wifi()
  local f = io.open('/proc/net/wireless', 'r')
  local q = 0
  if f then
    for line in f:lines() do
      if line:find('wlx', 1) then
        q = tonumber(line:match(':%s+%d+%s+([%d%.]+)')) or 0
      end
    end
    f:close()
  end
  return q
end

local function read_bat()
  local f = io.open('/sys/class/power_supply/BAT1/capacity', 'r')
  local v = 0
  if f then v = tonumber(f:read('*l')) or 0 f:close() end
  return v
end

local function read_vol()
  local f = io.popen('amixer -M sget Master 2>/dev/null | tail -1')
  local v = 0
  if f then
    local l = f:read('*l')
    f:close()
    if l then v = tonumber(l:match('%[(%d+)%%%]')) or 0 end
  end
  return v
end

local function read_pianobar()
  local running = conky_parse('${if_running pianobar}1${else}0${endif}') == '1'
  if not running then return false, '', '', '' end
  local function rf(p)
    local f = io.open(p, 'r')
    if not f then return '' end
    local s = f:read('*l') or ''
    f:close()
    return s
  end
  return true, rf(os.getenv('HOME')..'/.config/pianobar/title'),
               rf(os.getenv('HOME')..'/.config/pianobar/artist'),
               rf(os.getenv('HOME')..'/.config/pianobar/album')
end

local function fmt_net(b)
  local k = b/1024
  if k >= 1000 then return string.format('%.0fM', k/1024) end
  if k >= 10 then return string.format('%.0fK', k) end
  return string.format('%.1fK', k)
end

local function fmt_size(s)
  if not s then return '' end
  s = s:gsub(' +', '')
  return s:gsub('GiB','G'):gsub('MiB','M'):gsub('TiB','T'):gsub('KiB','K'):gsub('B','')
end

local function fmt_uptime()
  local f = io.open('/proc/uptime')
  if not f then return '' end
  local up = tonumber(f:read('*n')) or 0
  f:close()
  local d = math.floor(up/86400); up = up - d*86400
  local h = math.floor(up/3600);  up = up - h*3600
  local m = math.floor(up/60)
  if d > 0 then return string.format('%dd%dh', d, h) end
  return string.format('%dh%dm', h, m)
end

local function draw_net_block(cr, down, up, fs_free, fs_size, uptime, S)
  -- contained inside the vertically-ribbed gauge plate (grid interior
  -- ~x104..151, y214..280); rows packed tighter so they read as one block.
  local x = 105*KX*S
  local lines = {
    { 'IN  '..fmt_net(down), TXT_BRIGHT },
    { 'OUT '..fmt_net(up),   TXT_BRIGHT },
    { 'HDD '..fmt_size(fs_free)..'/'..fmt_size(fs_size), TXT_BRIGHT },
    { 'UPS '..uptime,        TXT_BRIGHT },
  }
  local y = 226*KY*S
  -- shade the whole ribbed gauge-plate recess (art ~x148..227, y320..424) with a
  -- VERTICAL ROUNDED RECTANGLE (small corner radius) tucked just inside the
  -- recess dome rims, so the bright metal rim frames it like the date pill.
  pill_shade(cr, 95*KX*S, 213*KY*S, 58*KS*S, 65*KS*S, 0.40, 8*KS*S)
  for _, l in ipairs(lines) do
    draw_text(cr, x, y, l[1], 6*KS*S, l[2], 1, F_MONO, 'left')
    y = y + 13*KS*S
  end
end

function conky_main()
  if conky_window == nil then return end
  if not conky_parse then return end
  local w = conky_window.width
  local h = conky_window.height
  if w < 8 or h < 8 then return end
  -- rings + text must share the SAME transform as the plate image
  -- (min-scale + centering offsets), else they drift low on the wells.
  local S = math.max(0.01, math.min(w/BG_W, h/BG_H))
  local cx0, cy0 = (w - BG_W*S)/2, (h - BG_H*S)/2

  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                       conky_window.visual, w, h)
  local cr = cairo_create(cs)
  cairo_set_operator(cr, CAIRO_OPERATOR_OVER)

  paint_bg(cr, w, h)

  -- data
  local cpu  = tonumber(conky_parse('${cpu cpu0}')) or 0
  local mem  = tonumber(conky_parse('${memperc}')) or 0
  local wifi = read_wifi()
  local bat  = read_bat()
  local vol  = read_vol()

  local now = os.date('*t')
  local secFrac = now.sec/60
  local minFrac = (now.min + now.sec/100)/60
  local hrFrac  = ((now.hour % 12) + now.min/100)/12

  -- net speed
  local rx, tx = read_net()
  local t = os.time()
  local down, up = 0, 0
  if net_prev then
    local dt = t - net_t
    if dt > 0 then
      down = (rx - net_prev[1])/dt
      up   = (tx - net_prev[2])/dt
    end
  end
  net_prev, net_t = {rx, tx}, t

  -- rings (wells are engraved in the plate image itself)
  for _, d in ipairs(DIALS) do
    local v = 0
    if d.get=='cpu' then v = cpu
    elseif d.get=='mem' then v = mem
    elseif d.get=='wifi' then v = wifi
    elseif d.get=='sec' then v = secFrac*60
    elseif d.get=='min' then v = minFrac*60
    elseif d.get=='hr' then v = hrFrac*12
    elseif d.get=='bat' then v = bat
    elseif d.get=='vol' then v = vol
    end
    sector_ring(cr, cx0+d.cx*KX*S, cy0+d.cy*KY*S, d.r*KS, d.th*KS, d.sn, d.gap, d.c1, d.c2, v/d.max, S)
  end

  -- hollow values + labels: percentages for the instrument dials
  -- (CPU/MEM/WLAN per the original); words for BAT and VOL.
  local per_dials = {
    { d=DIALS[1], txt=string.format('%d%%', cpu) },
    { d=DIALS[2], txt=string.format('%d%%', mem) },
    { d=DIALS[3], txt=string.format('%d%%', wifi) },
    { d=DIALS[7], txt='BAT' },
    { d=DIALS[8], txt='VOL' },
  }
  for _, p in ipairs(per_dials) do
    local d = p.d
    draw_text(cr, cx0+d.cx*KX*S, cy0+d.cy*KY*S, p.txt, 9*KS*S, TXT_BRIGHT, 1, F_MONO, 'center', true)
  end

  -- header: clock + date — etched on the top-right engraved plaque (design grid y53..83, art pill x146..216)
  draw_text_shadow(cr, cx0+119*KX*S, cy0+61*KY*S, os.date('%H:%M'), 9*KS*S, TXT_BRIGHT, 1, F_RINGS, 'center',
                   {0.9*KS*S, 1.0*KS*S})
  draw_date(cr, cx0+119*KX*S, cy0+70*KY*S, os.date('%a %d/%b/%Y'), 5.5*KS*S, TXT_BRIGHT, F_SANS)

  -- data mini-block: HDD + UPS in a dark slash-plaque on the right of wifi dial
  local fs_free = conky_parse('${fs_free}')
  local fs_size = conky_parse('${fs_size}')

  -- net in/out block right column
  draw_net_block(cr, down, up, fs_free, fs_size, fmt_uptime(), S)

  -- pianobar now playing — scrolling marquee in the recessed rect
  -- between the BAT and VOL dials (art grid interior ~x106..148, y461..478)
  local pb, pb_t, pb_a, pb_al = read_pianobar()
  local pwin = {}
  if pb then
    pwin = (pb_t ~= '' and pb_t or '') .. (pb_a ~= '' and ' - '..pb_a or '')
  else
    pwin = ''
  end
  -- shade the ENTIRE recessed marquee pill (art ~x52..218, y684..720) whether
  -- the marquee or the PWR fallback is shown
  pill_shade(cr, 34*KX*S, 455*KY*S, 110*KS*S, 24*KS*S, 0.40)
  if pwin ~= '' then
    local bxR = cx0 + 51*KX*S
    local byR = cy0 + 460*KY*S
    scroll_text(cr, bxR, byR, 90*KS*S, 15*KS*S, pwin, 6.7*KS*S, TXT_BRIGHT, 1, F_MONO, S)
  else
    draw_text(cr, cx0+96*KX*S, cy0+468*KY*S, 'PWR', 5.5*KS*S, TXT_DIM, 1, F_MONO, 'center', true)
  end

  cairo_surface_destroy(cs)
  cairo_destroy(cr)
end
