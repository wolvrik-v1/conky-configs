-- ============================================================
--  CYBER ATC  //  flight manifest companion to Conky 1.12
--  Renders the live ADS-B picture as a sorting radar manifest:
--  one row per track = callsign + airline + type + alt + spd
--  + range, nearest first, MIL/EMER flagged. Reads the status
--  file written by ~/.config/conky/adsb_radar.py (v2 fields:
--  squawk, emergency, category appended per track line).
--  Fully procedural. No image assets.
-- ============================================================

require 'cairo'

-- ------------------------------------------------------------
--  DESIGN GRID
-- ------------------------------------------------------------
local GRID_W, GRID_H = 600, 600
local S = 1.0

-- ------------------------------------------------------------
--  PALETTE  (0..1 floats)  -- cyber family
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
--  SHARED TEXT-EXTENTS OBJECT
--  lua-cario does NOT tie a cairo_text_extents_t to the Lua garbage
--  collector, so allocating one per call leaks every measurement of
--  every frame. text() and glow_text() below are called many times
--  per frame, so this measured as a real leak. One object for the
--  whole file: cairo_text_extents() simply refills it each call.
--  Do not create another one.
-- ------------------------------------------------------------
local TEXT_EXT = cairo_text_extents_t:create()

-- ------------------------------------------------------------
--  AIRLINE ID TABLE  (callsign prefix -> operator)
--  Static, bundled, no API key. Fallback = type + country tag
--  from the aircraft hex.
-- ------------------------------------------------------------
local AIRLINES = {
  -- North America
  AAL = 'American', DAL = 'Delta', UAL = 'United', SWA = 'Southwest',
  JBU = 'JetBlue', NKS = 'Spirit', AAY = 'Allegiant', FFT = 'Frontier',
  ASA = 'Alaska', HAL = 'Hawaiian', UAL = 'United', FDX = 'FedEx',
  UPS = 'UPS', SKW = 'SkyWest', ENY = 'Envoy Air', RPA = 'Republic',
  GJS = 'GoJet', EDV = 'Endeavor', ASQ = 'Air Wisconsin', CAA = 'Chautauqua',
  PDT = 'Piedmont', JIA = 'PSA', LXJ = 'Flexjet', OOI = 'GoJet',
  MXY = 'Breeze', VXP = 'Avelo', MXA = 'Mexico-Aero',
  ACA = 'Air Canada', ROU = 'Air Canada R', JZA = 'Jazz', WJA = 'WestJet',
  AMX = 'Aeromexico', VOI = 'Volaris', VIV = 'Viva Aerobus',
  -- South America
  AVA = 'Avianca', TAM = 'LATAM Brazil', LAN = 'LATAM Chile',
  SNA = 'LATAM Arg', LPE = 'LATAM Peru', CMP = 'Copa',
  AZU = 'Azul', GLO = 'GOL', ONE = 'Avianca', ARE = 'Aeroregional',
  -- Europe
  BAW = 'British Airways', EZY = 'EasyJet', RYR = 'Ryanair',
  VLG = 'Vueling', IBS = 'Iberia', IBE = 'Iberia', AEA = 'Air Europa',
  EIN = 'Aer Lingus', BEL = 'Brussels Airl', LOT = 'LOT Polish',
  DLH = 'Lufthansa', EWU = 'Eurowings', GWI = 'Germanwings', CLH = 'Lufthansa C',
  SWR = 'Swiss', AUA = 'Austrian', KLM = 'KLM', TRA = 'Transavia',
  THY = 'Turkish', PGT = 'Pegasus', SXS = 'SunExpress', ANK = 'AnadoluJet',
  FIN = 'Finnair', SAS = 'Scandinavian', ICE = 'Icelandair',
  TAP = 'TAP Portugal', AFR = 'Air France', HOI = 'Hop!',
  AZZ = 'Alitalia', ITY = 'ITA Airways', RYR = 'Ryanair',
  NLY = 'Niki', DAI = 'Air Dolomiti', VOE = 'Volotea',
  EWG = 'Eurowings', TVF = 'Transavia F', AFL = 'Aeroflot',
  AEE = 'Aegean', EZY = 'EasyJet EU',
  -- Asia / Pacific
  UAE = 'Emirates', ETD = 'Etihad', QTR = 'Qatar', GFA = 'Gulf Air',
  FDB = 'Flydubai', QFA = 'Qantas', VOZ = 'Virgin Aus',
  JST = 'Jetstar', ANZ = 'Air NZ', SIA = 'Singapore', SIL = 'Scoot',
  KAL = 'Korean', AAR = 'Asiana', ANA = 'ANA', JAL = 'Japan Airl',
  CCA = 'Air China', CES = 'China Eastern', CSN = 'China Southern',
  CPA = 'Cathay Pac', CHH = 'Hainan', CKK = 'China Cargo',
  MAS = 'Malaysia', THA = 'Thai', PAL = 'Philippine', CEB = 'Cebu Pac',
  EVA = 'EVA Air', CAL = 'China Airl', NCA = 'Nippon Cargo',
  -- Africa / Middle East
  MEA = 'MEA', ELY = 'El Al', IAF = 'Arkia', RAM = 'Royal Air Maroc',
  MSR = 'EgyptAir', ETH = 'Ethiopian', KQA = 'Kenya',
  -- Cargo
  GTI = 'Atlas Air', CKS = 'Kalitta', ABX = 'ABX Air', TNO = 'NorthAmer C',
  PXA = 'Panlatin C', AJV = 'Amerijet', DHK = 'DHL Air', BCS = 'EAT-DHL',
  CYS = 'CMA CGM C', -- nowadays Atlas C
  -- Exec / fractional (heavy ADS-B users near airports)
  EJA = 'NetJets', EJM = 'Exec Jet Mgmt', NJE = 'NetJets EU',
  TMC = 'Tradewind', WUP = 'Wheels Up',
  -- Legecy / regional all-codes
  GGN = 'Global Aero', SCX = 'Sun Country', GXA = 'GoJet',
}

-- Military callsign prefixes (squadron/rotation calls: Reach, Copper,
-- Convoy, SPAR ...) plus the rolling US-heavy tactical calls.
local MILITARY = {
  'RCH', 'KRF', 'DUKE', 'ANGEL', 'GOLD', 'JENA', 'DEATH', 'PITT',
  'CONVOY', 'SPAR', 'COBRA', 'BULL', 'HAWK', 'SAINT', 'ROMA', 'DARK',
  'VIPER', 'MASH', 'TEXACO', 'FORCE', 'METAL', 'BRAVE', 'STEEL',
  'CHAOS', 'ARGO', 'EPIC', 'SUNDOG', 'TUFO', 'GUARD', 'DAWG',
  'ROGUE', 'SPUR', 'BLUE', 'REDEYE', 'GATOR', 'HOMER', 'KILLER',
  'MAYHEM', 'MADDOG', 'POSEID', 'PAT', 'PEDRO', 'JEEP', 'GURU',
  'DARKSTAR', 'BOBCAT', 'JAVELIN', 'RAPTOR', 'FALCON', 'TIGER',
  'GHOST', 'PHANTOM', 'RAZOR', 'WEN', 'EAM', 'SUPREME', 'QUID',
}
-- ICAO netIDs that are reliably military (US DoD block; NOT civilian
-- Canadian C0-C2 which would flag Jazz/Flexjet etc.)
local MIL_NET = { 'ae', 'adf', 'adg' }

-- rough hex->country tag for the fallback label
local function hex_country(hex)
  if not hex or hex == '' then return '' end
  local p = hex:sub(1, 2):lower()
  local map = {
    ['a0'] = 'US', ['a1'] = 'US', ['a2'] = 'US', ['a3'] = 'US',
    ['a4'] = 'US', ['a5'] = 'US', ['a6'] = 'US', ['a7'] = 'US',
    ['a8'] = 'US', ['a9'] = 'US', ['aa'] = 'US', ['ab'] = 'US',
    ['ac'] = 'US', ['ad'] = 'US', ['ae'] = 'US', ['c0'] = 'CA',
    ['c1'] = 'CA', ['c2'] = 'CA', ['c3'] = 'CA', ['e0'] = 'US',
    ['e1'] = 'US', ['e2'] = 'US', ['e3'] = 'US', ['e4'] = 'US',
    ['e5'] = 'US', ['e6'] = 'US', ['38'] = 'FR', ['39'] = 'FR',
    ['3a'] = 'FR', ['3c'] = 'DE', ['3d'] = 'DE', ['3e'] = 'DE',
    ['3f'] = 'DE', ['4c'] = 'GB',
    ['0c'] = 'AU', ['7c'] = 'AU', ['0d'] = 'MX', ['06'] = 'BO',
    ['03'] = 'AR', ['11'] = 'JP', ['12'] = 'JP', ['13'] = 'JP',
    ['48'] = 'ID',
  }
  return map[p] or ''
end

local function is_military(hex, callsign)
  local u = (callsign or ''):upper()
  for _, p in ipairs(MILITARY) do
    if u:sub(1, #p) == p then return true end
  end
  if hex then
    local p = hex:sub(1, 2):lower()
    for _, m in ipairs(MIL_NET) do
      if p == m then return true end
    end
  end
  return false
end

local function airline_of(callsign)
  local u = (callsign or ''):upper()
  -- strip trailing digits -> prefix
  local pf = u:match('^(%a+)')
  if pf then
    local name = AIRLINES[pf]
    if name then return name end
  end
  return nil
end

-- ------------------------------------------------------------
--  STATE
-- ------------------------------------------------------------
local st = {
  up = 0,
  adsb = { tracks = {}, t = 0, n = 0, link = false, ts = 0 },
  mtr = { raw = '', text = '', link = false },
}
local ADSB_RANGE = 55.0     -- nm display radius (matches the poller)
local ADSB_FILE = os.getenv('HOME') .. '/.cache/conky/cyber-adsb.status'
local ADSB_STALE = 30       -- seconds before we call the link dead
local METAR_FILE = os.getenv('HOME') .. '/.cache/conky/cyber-atc.metar'
local MTRLINK = os.getenv('HOME') .. '/.cache/conky/cyber-atc.mtrlink'
local CENTER = 'KPIT 40.49N 080.14W'
local ROWS = 11             -- manifest rows visible (grid 600x600)

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
  local ext = TEXT_EXT
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
  local ext = TEXT_EXT
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
--  DATA READ  (status v2: hex brg dist alt gs fl typ sq em cat)
-- ------------------------------------------------------------
local SQUAWK_EMERG = { ['7500'] = 'HIJACK', ['7600'] = 'RADIO FAIL',
                       ['7700'] = 'EMERGENCY' }

local function read_adsb()
  local s = readfile(ADSB_FILE)
  st.adsb.link = false
  if not s then return end
  local ts, n, seen = nil, 0, {}
  for line in s:gmatch('[^\n]+') do
    local b = line:match('^TS +(%S+)')
    if b then ts = tonumber(b) end
    local h, brg, dist, alt, gs, fl, typ, sq, em, cat =
      line:match('^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)')
    if h and h ~= 'TS' and h ~= 'N' then
      seen[h] = true
      local t = st.adsb.tracks[h] or { }
      t.hex = h
      t.brg = tonumber(brg) or 0
      t.d = math.min(1, (tonumber(dist) or 0) / ADSB_RANGE)
      t.alt = tonumber(alt) or 0
      t.gs = tonumber(gs) or 0
      t.fl = fl or '-'
      t.typ = typ or '-'
      t.sq = sq or '-'
      t.em = em or 'none'
      t.cat = cat or '-'
      st.adsb.tracks[h] = t
      n = n + 1
    end
  end
  for h in pairs(st.adsb.tracks) do
    if not seen[h] then st.adsb.tracks[h] = nil end
  end
  st.adsb.n = n
  st.adsb.ts = ts or 0
  st.adsb.link = ts ~= nil and (os.time() - ts) < ADSB_STALE
end

local function read_metar()
  local txt = readfile(METAR_FILE)
  if txt then
    st.mtr.raw = txt:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  end
  local m = ""
  for line in (readfile(MTRLINK) or ''):gmatch('[^\n]+') do m = line end
  st.mtr.link = m == 'metar ok'
end

-- METAR -> compact strip   (e.g. "W 27012G24KT VIS 3/4SM BKN008")
local function metar_strip(raw)
  local wind = raw:match('(%u?%u?%d%d%d%d%d%d?G?%d*KT)')
  local vis  = raw:match('(%d+/?%d*SM)')
  local sky  = raw:match('(FEW%d+)') or raw:match('(SCT%d+)')
    or raw:match('(BKN%d+)') or raw:match('(OVC%d+)') or raw:match('(VV%d+)')
  return 'W ' .. (wind or '--') .. ' VIS ' .. (vis or '--') .. ' ' .. (sky or 'CLR')
end

-- ------------------------------------------------------------
--  MANIFEST
-- ------------------------------------------------------------
local function draw_manifest(cr, up)
  -- collect + sort by range (nearest first)
  local list = {}
  for h, t in pairs(st.adsb.tracks) do
    list[#list + 1] = t
  end
  table.sort(list, function(a, b) return a.d < b.d end)

  -- EMER tracks (squawk 7500/7600/7700 or live emergency field)
  local emers = {}
  for _, t in ipairs(list) do
    local c = SQUAWK_EMERG[t.sq]
    local e = c or (t.em ~= 'none' and t.em:upper()) or nil
    if e then emers[#emers + 1] = { t = t, why = e } end
  end

  -- ============ EMERGENCY BANNER ============
  local pulse = 0.55 + 0.45 * math.sin(up * 5)
  if #emers > 0 then
    local by = 176 * S
    chamfer_path(cr, 18 * S, by, (GRID_W - 36) * S, 26 * S, 6 * S)
    rgba(cr, RED, 0.16 + 0.10 * pulse)
    cairo_fill(cr)
    chamfer_path(cr, 18 * S, by, (GRID_W - 36) * S, 26 * S, 6 * S)
    cairo_set_line_width(cr, 1.2 * S)
    rgba(cr, RED, 0.5 + 0.3 * pulse)
    cairo_stroke(cr)
    local first = emers[1]
    local desc = string.format('EMERG %s · %s · %.0fNM · SQ %s',
      first.why, first.t.fl, first.t.d * ADSB_RANGE, first.t.sq)
    text(cr, desc, 28 * S, by + 17 * S, F_MONO, 12 * S,
      CAIRO_FONT_WEIGHT_BOLD, RED, 0.9 + (0.1 * pulse), 'left')
    if #emers > 1 then
      text(cr, string.format('+%d MORE', #emers - 1), (GRID_W - 28) * S,
        by + 17 * S, F_MONO, 10 * S, CAIRO_FONT_WEIGHT_BOLD, RED, 0.8, 'right')
    end
  end

  -- ============ ROW HEADER ============
  local hy = 210 * S
  local hdr_y = #emers > 0 and (hy + 30 * S) or hy
  local cols = {
    { 'CALL', 50 * S },
    { 'AIRLINE', 150 * S },
    { 'TYPE', 210 * S },
    { 'FL',  470 * S },
    { 'SPD',  520 * S },
    { 'RNG',  580 * S },
  }
  for _, c in ipairs(cols) do
    local al = (c[1] == 'FL' or c[1] == 'SPD' or c[1] == 'RNG') and 'right' or 'left'
    text(cr, c[1], c[2], hdr_y, F_MONO, 9 * S, CAIRO_FONT_WEIGHT_BOLD,
      G_DIM, 0.95, al)
  end
  local rows = math.min(#list, ROWS)
  local start_y = hdr_y + 20 * S
  local row_h = 26 * S

  for i = 1, rows do
    local t = list[i]
    local y = start_y + (i - 1) * row_h
    -- zebra scanline
    if i % 2 == 0 then
      rgba(cr, G_TRACE, 0.25)
      cairo_rectangle(cr, 16 * S, y - 10 * S, (GRID_W - 32) * S, row_h)
      cairo_fill(cr)
    end
    -- MIL / EMER tag colour
    local mil = is_military(t.hex, t.fl)
    local em = SQUAWK_EMERG[t.sq] or (t.em ~= 'none') or false
    local rowcol = em and RED or (mil and AMBER or adscol(t.alt))
    -- marker diamond
    cairo_set_line_width(cr, 1.0 * S)
    rgba(cr, rowcol, em and (0.6 + 0.4 * pulse) or 0.9)
    cairo_move_to(cr, 22 * S, y - 4 * S)
    cairo_line_to(cr, 28 * S, y)
    cairo_line_to(cr, 22 * S, y + 4 * S)
    cairo_line_to(cr, 16 * S, y)
    cairo_close_path(cr)
    if em then rgba(cr, rowcol, 0.5 + 0.5 * pulse); cairo_fill(cr)
    else cairo_stroke(cr) end
    -- callsign
    local cc = em and RED or (mil and AMBER or WHITE)
    text(cr, t.fl, 50 * S, y, F_MONO, 13 * S, CAIRO_FONT_WEIGHT_BOLD, cc,
      em and (0.85 + 0.15 * pulse) or 1, 'left')
    -- airline (or fallback type + country)
    local airline = airline_of(t.fl)
    local lbl
    if airline then
      lbl = airline
    else
      local ctry = hex_country(t.hex)
      lbl = ctry ~= '' and (t.typ .. '/' .. ctry) or t.typ
    end
    text(cr, lbl, 150 * S, y, F_MONO, 10 * S, CAIRO_FONT_WEIGHT_NORMAL,
      G_MID, em and (0.8 + 0.2 * pulse) or 0.95, 'left')
    -- type
    text(cr, t.typ, 210 * S, y, F_MONO, 10 * S, CAIRO_FONT_WEIGHT_NORMAL,
      G_DIM, em and (0.8 + 0.2 * pulse) or 0.9, 'left')
    -- alt (FL style)
    local fl
    if t.alt <= 0 then fl = 'SFC'
    else fl = string.format('%03d', math.floor(t.alt / 100) % 1000)
    end
    text(cr, 'FL' .. fl, 470 * S, y, F_MONO, 11 * S, CAIRO_FONT_WEIGHT_BOLD,
      rowcol, 0.95, 'right')
    -- speed
    text(cr, t.gs > 0 and tostring(t.gs) or ' ---', 520 * S, y, F_MONO, 11 * S,
      CAIRO_FONT_WEIGHT_BOLD, rowcol, 0.95, 'right')
    -- range
    local d = t.d * ADSB_RANGE
    text(cr, string.format('%5.1f', d), 580 * S, y, F_MONO, 11 * S,
      CAIRO_FONT_WEIGHT_BOLD, rowcol, 0.95, 'right')
    -- MIL tag suffix
    if mil and not em then
      text(cr, 'MIL', 320 * S, y, F_MONO, 8 * S, CAIRO_FONT_WEIGHT_BOLD,
        AMBER, 0.85, 'left')
    end
  end
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
    read_metar()
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
  glow_text(cr, 'CYBER ATC', 24 * S, 40 * S, F_TITLE, 24 * S, G_MAIN, 'left')
  text(cr, os.date('%H:%M:%S'), (GRID_W - 24) * S, 34 * S, F_MONO, 14 * S,
    CAIRO_FONT_WEIGHT_BOLD, G_MID, 0.9, 'right')
  text(cr, os.date('%d %b %y') .. '  ·  ' .. CENTER, (GRID_W - 24) * S,
    50 * S, F_MONO, 9 * S, CAIRO_FONT_WEIGHT_NORMAL, G_DIM, 0.85, 'right')
  -- divider
  cairo_set_line_width(cr, 0.8 * S)
  rgba(cr, G_DIM, 0.6)
  cairo_move_to(cr, 24 * S, 60 * S); cairo_line_to(cr, (GRID_W - 24) * S, 60 * S)
  cairo_stroke(cr)

  -- ============ STATUS STRIP ============
  if st.adsb.link then
    text(cr, string.format('LINK OK · %02d TRK · RANGE %dNM', st.adsb.n,
         ADSB_RANGE), 24 * S, 84 * S, F_MONO, 10 * S, CAIRO_FONT_WEIGHT_BOLD,
      G_MID, 0.95, 'left')
  else
    text(cr, 'LINK DOWN · NO FEED', 24 * S, 84 * S, F_MONO, 10 * S,
      CAIRO_FONT_WEIGHT_BOLD, RED, 0.95, 'left')
  end
  -- METAR compact strip on the right
  local mtr_txt
  if st.mtr.raw ~= '' then
    mtr_txt = metar_strip(st.mtr.raw)
  else
    mtr_txt = 'MTR --'
  end
  text(cr, mtr_txt, (GRID_W - 288) * S, 84 * S, F_MONO, 10 * S,
    CAIRO_FONT_WEIGHT_NORMAL, st.mtr.link and CYAN or G_DIM, st.mtr.link and 0.95 or 0.6, 'right')

  -- ============ MANIFEST ============
  draw_manifest(cr, up)

  -- ============ FOOTER ============
  cairo_set_line_width(cr, 0.8 * S)
  rgba(cr, G_DIM, 0.5)
  cairo_move_to(cr, 24 * S, (GRID_H - 40) * S)
  cairo_line_to(cr, (GRID_W - 24) * S, (GRID_H - 40) * S)
  cairo_stroke(cr)
  if st.adsb.link then
    text(cr, 'AUTO-MANIFEST · SORT: RANGE · ADSB via adsb.lol',
      24 * S, (GRID_H - 24) * S, F_MONO, 9 * S, CAIRO_FONT_WEIGHT_NORMAL,
      G_DIM, 0.8, 'left')
  else
    text(cr, 'AWAITING DATA FEED', 24 * S, (GRID_H - 24) * S, F_MONO, 9 * S,
      CAIRO_FONT_WEIGHT_NORMAL, RED, 0.8, 'left')
  end
  local bl = 0.5 + 0.5 * math.sin(up * 2)
  text(cr, bl > 0.5 and '■' or '□', (GRID_W - 24) * S, (GRID_H - 24) * S,
    F_MONO, 9 * S, CAIRO_FONT_WEIGHT_NORMAL, G_MID, bl, 'right')

  cairo_destroy(cr)
  cairo_surface_destroy(surface)
end

-- ------------------------------------------------------------
--  ADS-B LINK MANAGER  (one-shot, pgrep-guarded)
-- ------------------------------------------------------------
local function spawn_adsb_link()
  local home = os.getenv('HOME') or '.'
  os.execute('A="' .. home .. '/.conky/cyber-atc/scripts/adsb"; B="_radar.py"; '
    .. 'if ! pgrep -f "adsb_radar.p[y]" >/dev/null 2>&1; then '
    .. 'setsid python3 "$A$B" </dev/null >>/tmp/adsb_daemon.log 2>&1 & fi')
end
spawn_adsb_link()