-- ============================================================
--  THE ORRERY (BRASS)  --  rebuilt from scratch, one element
--  at a time, each step verified visually by the user.
--
--  STEP 1: bare plate only.
--    - deep-space vignette
--    - outer rim rings + inner groove rings
--    - graduation track (1/5/30 deg ticks, hairline tracks)
--    - corner + mid rivets
--  STEP 2: starfield.        STEP 3: six orbits.
--  STEP 4: sun + six planets (the clock; see the TIME section).
--  STEP 5: calendar, as TWO concentric rings sharing one day-of-year map --
--    inner band 252-272: day ticks, month boundaries, tenth-day numerals;
--    outer ring 285-306: month letters, joined to the inner band by
--    month-boundary spokes; plus the brass date hand.
--  Still to add, one at a time: astrological rings, plaques/HUD.
--  Deliberately nothing else yet, so each step is judged on its own.
--
--  The previous full implementation is preserved beside this file as
--  orrery-brass.lua.pre-rebuild-<timestamp> and in ~/conky-backup/.
-- ============================================================
require 'cairo'

local GRID_W, GRID_H = 720, 780
  local CX, CY = 360, 390
  local S = 1.0
  local EXT = cairo_text_extents_t:create()  -- shared text extents for arc_text (leak-safe)

-- Supersample factor. Bodies at these orbital radii move a fraction of a pixel
-- per frame (Mercury 0.18px, Venus 0.005px at 0.03s). At 1x Cairo renders that
-- change as well under one 8-bit colour level, so consecutive frames are
-- identical to the eye and the body appears to jump a whole pixel. Rendering
-- the canvas larger and downscaling gives the sub-pixel motion somewhere to
-- land. 1 disables it.
local SUPERSAMPLE = 1

local function col(r,g,b) return {r/255,g/255,b/255} end
local B1=col(0xd8,0xb8,0x6a)  local B2=col(0xb0,0x8f,0x4e)
local B3=col(0x8a,0x6f,0x38)  local B4=col(0x5e,0x4c,0x28)
local GOLD=col(0xe8,0xc8,0x7c)
local SPACE1=col(0x09,0x0d,0x12)  local SPACE2=col(0x02,0x04,0x06)

local DEG=math.pi/180

local function rgba(cr,c,a) cairo_set_source_rgba(cr,c[1],c[2],c[3],a or 1) end
local function radial(cr,x,y,r0,r1,stops)
  local g=cairo_pattern_create_radial(x,y,r0,x,y,r1)
  for _,st in ipairs(stops) do cairo_pattern_add_color_stop_rgba(g,st[1],st[2][1],st[2][2],st[2][3],st[3] or 1) end
  cairo_set_source(cr,g); cairo_pattern_destroy(g)
end

-- ------------------------------------------------------------
--  PLATE
-- ------------------------------------------------------------
local function plate(cr)
  -- deep-space vignette. Kept as the very first thing drawn so the window is
  -- never a bare transparent rectangle (Moksha renders unpainted dock pixels
  -- black, which is its own kind of artifact).
  radial(cr,CX*S,CY*S,0,340*S,
    {{0,SPACE1,0.92},{0.55,SPACE1,0.72},{0.80,SPACE2,0.30},{1,SPACE2,0}})
  cairo_paint(cr)
end

-- ------------------------------------------------------------
--  FRAME: outer rim, inner groove, graduation track, rivets
-- ------------------------------------------------------------
local function frame(cr)
  cairo_save(cr)

  -- outer rim: triple ring, structurally unbroken all the way round
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,339*S,0,2*math.pi)
  cairo_set_line_width(cr,1.2*S); rgba(cr,B4,0.70); cairo_stroke(cr)
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,342*S,0,2*math.pi)
  cairo_set_line_width(cr,2.6*S); rgba(cr,B2,0.90); cairo_stroke(cr)
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,344*S,0,2*math.pi)
  cairo_set_line_width(cr,1.2*S); rgba(cr,B1,0.55); cairo_stroke(cr)

  -- inner groove rings
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,279*S,0,2*math.pi)
  cairo_set_line_width(cr,1.2*S); rgba(cr,B4,0.65); cairo_stroke(cr)
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,276*S,0,2*math.pi)
  cairo_set_line_width(cr,0.8*S); rgba(cr,B1,0.40); cairo_stroke(cr)

  -- Machined bezel band, r307..317 -- the substrate the HUD plaques bolt onto.
  --
  -- WHY: measured across the empty quadrants (45/135/225/315 deg), the band
  -- between the month-letter ring and the graduation track was DEAD BLACK --
  -- luma 0-1 from r307 to r317, all the way round. The plaques span r292..332,
  -- so until now they bridged that gap with nothing underneath them. A full
  -- circle of grooves closes the void BY CONSTRUCTION, which is the whole
  -- lesson of the old wedge artefact: a symmetric frame makes voids impossible.
  --
  -- INNER EDGE IS 307, NOT 306, ON PURPOSE. The month-letter ring's outer edge
  -- circle is already drawn at exactly r306, so an edge line at 306 would land
  -- on top of it and read as one thick doubled ring. 307 leaves 1 unit of plate
  -- between them. The outer edge at 317 likewise stays 2 units clear of the
  -- graduation hairline at r319.
  --
  -- The recipe is the calendar band's, unchanged: gn grooves on an even step,
  -- alternating alpha 0.22/0.15, with brighter edge lines at each end. With
  -- gn=4 over 10 units the step is 2.0, which is the SAME rhythm the calendar
  -- band's grooves already use (20 units / 9 grooves), so the two machined
  -- areas read as one language rather than two.
  --
  -- This is drawn here, inside frame(), which is why it lands UNDER the plaques:
  -- conky_main calls frame(cr) before hud_readout(...).
  --
  -- ONE RISK, checked before shipping: a band this dark can become a NEW void
  -- instead of filling the old one. That is why the groove alphas are lifted
  -- above the calendar band's if the measured luma comes back near zero.
  -- Drawn inline rather than via orbit(), which is defined ~150 lines BELOW
  -- this function and is therefore still a nil global when frame() first runs.
  local BEZ_BAND_IN,BEZ_BAND_OUT=307.0,317.0
  local function bandline(rad,c,a,w)
    cairo_new_path(cr)
    cairo_arc(cr,CX*S,CY*S,rad*S,0,2*math.pi)
    cairo_set_line_width(cr,w*S)
    rgba(cr,c,a)
    cairo_stroke(cr)
  end
  -- THE FILL IS THE WHOLE FIX, and it is worth recording why. The calendar band
  -- reads at luma ~159 on the SAME B3@0.22 groove recipe because it has NO fill
  -- and sits where the plate vignette is still bright (r252..272). Out here at
  -- r307..317 the vignette has fallen away, so the identical recipe composited
  -- to 55 and the band was invisible. The band needed its own GROUND, not a
  -- different groove colour -- alpha alone could never have got there, since a
  -- bare B3 line cannot exceed its own luma (113) over near-black.
  -- Drawn as a WIDE STROKE rather than an even-odd annulus path: a stroke
  -- centred on (IN+OUT)/2 with line width (OUT-IN) covers exactly IN..OUT, and
  -- it needs no cairo_arc_negative (whose presence in this binding is not
  -- verified). ring_sector_sq would do it too but is defined ~670 lines BELOW
  -- frame() and would be a nil global here, the same trap as orbit().
  cairo_set_line_width(cr,(BEZ_BAND_OUT-BEZ_BAND_IN)*S)
  radial(cr,CX*S,CY*S,BEZ_BAND_IN*S,BEZ_BAND_OUT*S,
    {{0,col(0x6e,0x59,0x30),0.98},{0.42,col(0xa8,0x89,0x46),0.98},
     {0.58,col(0xa8,0x89,0x46),0.98},{1,col(0x6e,0x59,0x30),0.98}})
  cairo_new_path(cr)
  cairo_arc(cr,CX*S,CY*S,(BEZ_BAND_IN+BEZ_BAND_OUT)/2*S,0,2*math.pi)
  cairo_stroke(cr)
  local bg_n=4
  local bg_step=(BEZ_BAND_OUT-BEZ_BAND_IN)/(bg_n+1)
  for i=1,bg_n do
    local a=(i%2==1) and 0.34 or 0.24
    bandline(BEZ_BAND_IN+bg_step*i,B2,a,0.6)
  end
  bandline(BEZ_BAND_IN ,B3,0.85,0.9)
  bandline(BEZ_BAND_OUT,B3,0.90,1.0)

  -- graduation track: inner + outer hairline tracks
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,319*S,0,2*math.pi)
  cairo_set_line_width(cr,0.7*S); rgba(cr,B4,0.50); cairo_stroke(cr)
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,336*S,0,2*math.pi)
  cairo_set_line_width(cr,0.7*S); rgba(cr,B2,0.55); cairo_stroke(cr)

  -- graduation tick train: 30 deg major / 5 deg mid / 1 deg faint.
  -- Batched into three strokes rather than 360 separate ones.
  cairo_set_line_cap(cr,CAIRO_LINE_CAP_BUTT)
  local function grad_style(kind,tw,al,c)
    cairo_new_path(cr)
    for i=0,359 do
      local major,mid=(i%30==0),(i%5==0)
      local m=(kind==1 and major) or (kind==2 and (mid and not major)) or (kind==3 and not mid)
      if m then
        local a=i*DEG; local sa,ca=math.sin(a),math.cos(a)
        local r0=(kind==1) and 319 or ((kind==2) and 321 or 323)
        local r1=(kind==3) and 334 or 336
        cairo_move_to(cr,CX*S+sa*r0*S,CY*S-ca*r0*S)
        cairo_line_to(cr,CX*S+sa*r1*S,CY*S-ca*r1*S)
      end
    end
    cairo_set_line_width(cr,tw*S); rgba(cr,c,al); cairo_stroke(cr)
  end
  grad_style(1,1.6,0.85,B1)
  grad_style(2,1.1,0.50,B2)
  grad_style(3,0.6,0.25,B4)
  cairo_set_line_cap(cr,CAIRO_LINE_CAP_ROUND)

  -- rivets on the rim
  local function rivet(a,rmid,rad)
    local bx,by=CX*S+math.sin(a)*rmid*S, CY*S-math.cos(a)*rmid*S
    cairo_set_source_rgba(cr,B4[1],B4[2],B4[3],0.9)
    cairo_arc(cr,bx,by,rad*S,0,2*math.pi); cairo_fill(cr)
    cairo_set_source_rgba(cr,B1[1],B1[2],B1[3],0.7)
    cairo_arc(cr,bx-0.4*S,by-0.4*S,rad*0.42*S,0,2*math.pi); cairo_fill(cr)
  end
  for _,a in ipairs({45*DEG,135*DEG,225*DEG,315*DEG}) do rivet(a,341,2.2) end

  cairo_restore(cr)
end

-- ------------------------------------------------------------
--  STEP 2: starfield
--  Seeded PRNG so the sky is identical every frame and every restart
--  (no "shimmering" from re-rolling). Two depth layers: the nearer stars
--  drift faster and brighter than the far ones, which is what gives the
--  field depth instead of a flat scatter.
-- ------------------------------------------------------------
local function mulberry32(seed)
  local s0=seed
  return function()
    s0=(s0+0x6D2B79F5)%4294967296
    local t=s0
    t=(t*(0x03214B06))%4294967296
    t=(t*(0xBC2B54B6))%4294967296
    return t%1
  end
end

local STAR_N=220
local function draw_starfield(cr,now)
  -- Fixed seed: the same sky every launch, so nothing twitches on restart.
  --
  -- *** PARKED 2026-10-02 -- THE STARFIELD IS NOT VISIBLE. NOT A TUNING PROBLEM.
  --
  -- Values below are back to the ORIGINAL 0.42/0.20 and r1.15/0.75 after a
  -- diagnostic run at flat alpha 1.00 with radius 2.60/1.80 -- roughly 3x the
  -- diameter, every star at full brightness -- produced NO visible change to the
  -- user's eye. So brightness and size are both ruled out: at alpha 1.00 these are
  -- opaque discs and they still do not appear. Do not 'fix' this by raising alpha
  -- again; that avenue is closed.
  --
  -- What is known:
  --   - The loop is reached and runs (a stale screen capture from an earlier build
  --     does contain star-like specks in the r62..84 annulus, peaking near luma
  --     180, so stars have been composited onto the window at some point).
  --   - draw_starfield() is called immediately after plate(cr) in both the
  --     supersampled and plain branches of conky_main.
  --   - The plate is genuinely dark where the stars sit (luma 3.6-10.7 outside
  --     r30), so there is no washout to blame. The centre IS bright (luma 93.7 at
  --     r10-30) because of the sun's glow, but that is a small area.
  --
  -- Next hypotheses, in order, for whoever picks this up:
  --   1. OVERPAINT. Something drawn after draw_starfield covers them. Prime
  --      suspects: frame() (called after the moving layer), the bodies() glows,
  --      and hud_readout(). Test by returning early right after draw_starfield so
  --      the starfield is the LAST thing painted -- if they appear, it is
  --      overpaint and the fix is draw order, not brightness.
  --   2. Verify draw_starfield is actually being entered at runtime, by having it
  --      write a counter to a file (instrument the live Lua -- never trust a
  --      screenshot on this desktop, import -window returns STALE frames here).
  --   3. Only then consider the display itself.
  --
  -- The user has a starry wallpaper meanwhile and is content to leave this.
  local rng=mulberry32(947265240)   -- fixed seed: same sky every launch
  for i=1,STAR_N do
    local a=rng()*2*math.pi
    local depth=rng()                 -- >0.7 = near layer
    local rmax=272*S
    local r=math.sqrt(rng())*rmax     -- sqrt = even areal density, no clumping
    local drift=(depth>0.7) and 0.0038 or 0.0016
    local base=(depth>0.7) and 0.42 or 0.20
    local tw=0.72+0.28*math.sin(now*1.7+i*2.399)   -- gentle twinkle
    local rad=(depth>0.7) and 1.15 or 0.75
    local px=CX*S+math.sin(a+now*drift)*r
    local py=CY*S-math.cos(a+now*drift)*r
    local al=base*tw
    cairo_set_source_rgba(cr,B1[1],B1[2],B1[3],al)
    cairo_arc(cr,px,py,rad*S,0,2*math.pi); cairo_fill(cr)
    -- the near layer gets a faint halo so it reads as brighter, not just bigger
    if depth>0.7 then
      cairo_set_source_rgba(cr,B1[1],B1[2],B1[3],al*0.22)
      cairo_arc(cr,px,py,rad*S*2.6,0,2*math.pi); cairo_fill(cr)
    end
  end
end

-- ------------------------------------------------------------
--  ORBITS
--  Radii are FIXED here and must not be nudged: the planets ride these
--  circles, so a change here moves every body on the dial. Kept at the
--  original spacing (55/88/122/150/186/216) which is deliberately even, so
--  no sector of the dial is emptier than another.
-- ------------------------------------------------------------
local OR={MERCURY=55,VENUS=88,EARTH=122,MARS=150,JUPITER=186,SATURN=216}

-- Plain arc + stroke. No gradient pattern and no text, so this function has
-- no cairo_pattern_* ownership to manage and cannot leak. Keep it that way:
-- if a fill or gradient is ever added here, it MUST create the pattern,
-- cairo_set_source, then cairo_pattern_destroy immediately (cairo takes its
-- own reference and keeps drawing with it).
local function orbit(cr,rad,c,a,w)
  cairo_new_path(cr)
  cairo_arc(cr,CX*S,CY*S,rad*S,0,2*math.pi)
  cairo_set_line_width(cr,(w or 0.7)*S)
  rgba(cr,c,a)
  cairo_stroke(cr)
end

local function orbits(cr)
  cairo_save(cr)
  cairo_set_line_cap(cr,CAIRO_LINE_CAP_BUTT)
  -- inner orbits slightly brighter than outer ones, which reads as depth.
  -- Alphas raised ~0.10 across the board (user: "a touch brighter"); widths
  -- deliberately unchanged, so this is a brightness change and not a weight one.
  orbit(cr,OR.MERCURY,B3,0.70,0.9)
  orbit(cr,OR.VENUS,  B3,0.66,0.8)
  orbit(cr,OR.EARTH,  B3,0.62,0.8)
  orbit(cr,OR.MARS,   B3,0.56,0.7)
  orbit(cr,OR.JUPITER,B4,0.66,0.7)
  orbit(cr,OR.SATURN, B4,0.70,0.7)
  cairo_restore(cr)
end

-- ------------------------------------------------------------
--  TIME
--  Smooth sub-second time for the moving bodies.
--
--  MUST NOT use os.clock(): that is CPU time, so it runs at a different rate
--  from the wall clock, drifts out of phase with d.sec, and wraps backwards
--  every whole second -- which makes the seconds hand and Mercury stutter.
--  /proc/uptime is monotonic, so it is the right thing to DERIVE a rate from,
--  but its fraction must never be added to a wall-clock field (see below).
-- ------------------------------------------------------------
local function uptime()
  local f=io.open('/proc/uptime','r')
  if not f then return nil end
  local s=f:read('*l'); f:close()
  -- /proc/uptime is "uptime idle", TWO numbers on one line. tonumber() parses the
  -- WHOLE string and stops at the space, so it returns nil on the raw line --
  -- pull the first field out first or this silently degrades to a nil.
  return tonumber(s and s:match('^(%S+)'))
end

-- ONE continuous LOCAL-epoch second, for every moving body. Built from three
-- pieces, all fixed at init:
--   now_anchor -- os.time() + the local UTC offset (see below)
--   up_anchor  -- the uptime reading taken at the same instant
--   delta      -- current uptime minus up_anchor, per frame
--
-- os.time() returns UTC epoch seconds -- it is the same number as `date +%s`, NOT
-- local time. So now_anchor must have the offset added, or every derived field is
-- UTC: hh would be the UTC hour (Earth 4h fast on EDT) and mm the UTC minute. Only
-- s survives, because a whole-hour offset shifts minutes and hours but not seconds
-- within the minute. Measured on this box: (os.time()/3600)%24 = 11.92 while
-- os.date('*t').hour = 7.
--
-- The offset comes from os.date's own local fields, so it is correct for whatever
-- zone and DST state is in effect at init -- no `date -u` and no popen handle to
-- leak. (An earlier claim that os.time() was "already local" was wrong, and it
-- silently put Earth 4 hours ahead.)
--
-- Why not just add the uptime fraction to a wall-clock field? Because the two
-- clocks are not in phase. /proc/uptime counts from boot, so its second boundary
-- sits at an arbitrary offset from the wall-clock boundary (measured ~0.9s here).
-- d.sec ticks on the wall boundary and the fraction wraps on the uptime boundary,
-- so for a stretch of every second equal to that offset the sum is wrong by one
-- full second of dial travel -- ~5.9px on r=56. Measured: 9 backward deltas in 90
-- draws, each a -5.33px snap-back.
--
-- And returning the bare fraction is worse: it only ever spans 0..1, so the body
-- sweeps 1/60th of its orbit and restarts from the same pixel every second -- the
-- original sawtooth (5.3px amplitude, a_s spanning 0.095 of 6.2832 rad).
--
-- Deriving one value from one anchor sidesteps the whole phase question: there is
-- nothing to disagree with anything else. All three bodies read this, so they can
-- never be internally inconsistent either.
local now_anchor,up_anchor

-- os.time() is UTC; the local fields tell us by how much. Computed once, and
-- renormalised into [-12h,+14h] so a zone either side of the date line still lands
-- on the small offset.
local function local_offset(t)
  local d=os.date('*t',t)
  local off=(d.hour*3600+d.min*60+d.sec)-(t%86400)
  if off>14*3600 then off=off-86400
  elseif off<-12*3600 then off=off+86400 end
  return off
end

local function anchor()
  local t=os.time()
  now_anchor=t+local_offset(t)
  up_anchor=uptime() or 0
end

-- os.time() is a whole second, so anchoring straight onto it leaves a constant
-- error of up to 1s for the whole session: the hands would be perfectly smooth
-- but never line up with the real clock. Waiting out the rest of the current
-- second once, at init, lands the anchor on a true boundary so the error is zero.
-- One short-lived subprocess does the waiting -- os.execute returns when the child
-- exits, so there is no handle to leak and no core-pinning spin. Init only: the
-- drift re-anchor below must never stall a frame.
local function await_second_boundary(t)
  if os.execute then
    os.execute(string.format('while [ "$(date +%%s)" = "%d" ]; do sleep 0.05; done',t))
  end
end

local function clock_now()
  if not now_anchor then
    local t=os.time()
    await_second_boundary(t)
    anchor()
  end
  local up=uptime()
  if not up then return now_anchor end
  local d=up-up_anchor
  if d<0 then d=0 end
  local now=now_anchor+d
  -- This is a laptop: uptime does not advance across suspend, and NTP steps the
  -- wall clock without moving uptime, so the derived time silently diverges from
  -- the real clock. Whenever the two disagree by more than 1.5s, trust the wall
  -- clock and re-anchor. A rare one-off jump is correct -- a hand that never
  -- corrects is worse than one that steps once after a resume.
  --
  -- Compare against the DERIVED now, never against now_anchor. now_anchor is
  -- frozen at init, so testing it here makes the difference grow by 1s every
  -- second and trips the guard forever: measured 127 re-anchors in 254s, i.e.
  -- every 2s, each one snapping the hands back to a whole second and undoing
  -- the sub-second smoothness the anchor exists to provide.
  --
  -- The offset is recomputed here every frame, so a DST change (2026-11-01 moves
  -- the offset from -4h to -5h, a 3600s step) trips this same threshold, with no
  -- extra machinery and no frozen offset to go stale.
  if math.abs((os.time()+local_offset(os.time()))-now)>1.5 then
    anchor()
    return now_anchor
  end
  return now
end

-- ------------------------------------------------------------
--  LUNAR
--  Synodic phase, from a known new moon. Same constants as the earlier
--  verified implementation; only used for the terminator shading on the
--  Earth's moon, so precision beyond ~a few hours is not required.
-- ------------------------------------------------------------
local LUNAR_SYNODIC=29.530588853
local NEW_MOON_EPOCH=947265240      -- 2000-01-06 18:14 UTC

local function lunar_age(t)
  local d=(t-NEW_MOON_EPOCH)/86400
  return d%LUNAR_SYNODIC
end
-- illuminated fraction 0..1, via the standard phase-angle cosine
local function lit_frac(age)
  return (1-math.cos(2*math.pi*age/LUNAR_SYNODIC))/2
end

-- Eight-stellar names, every one exactly two words so the 3:00 plaque can
-- split it across two stacked lines. Thresholds are the conventional
-- quarter/phase boundaries.
local function phase_name(age)
  local a=age%LUNAR_SYNODIC
  if a<1.0 or a>=28.5 then return 'NEW MOON'
  elseif a<5.5     then return 'WAXING CRESCENT'
  elseif a<9.0     then return 'FIRST QUARTER'
  elseif a<13.5    then return 'WAXING GIBBOUS'
  elseif a<16.5    then return 'FULL MOON'
  elseif a<21.0    then return 'WANING GIBBOUS'
  elseif a<24.5    then return 'LAST QUARTER'
  end
  return 'WANING CRESCENT'
end

-- ------------------------------------------------------------
--  BODIES
-- ------------------------------------------------------------
local function pos(rad,a) return CX*S+math.sin(a)*rad*S, CY*S-math.cos(a)*rad*S end

-- A lit sphere: gradient offset toward the sun (the dial centre) so each body
-- has a bright limb on the sun side and a dark one opposite. The gradient is
-- created, set as source, and destroyed immediately -- cairo takes its own
-- reference, so this is correct and is the whole ownership discipline.
local function planet(cr,x,y,r,lightc,darkc,glow)
  if glow then
    local g=cairo_pattern_create_radial(x,y,r*0.4,x,y,r*3.1)
    cairo_pattern_add_color_stop_rgba(g,0,lightc[1],lightc[2],lightc[3],0.30)
    cairo_pattern_add_color_stop_rgba(g,1,lightc[1],lightc[2],lightc[3],0)
    cairo_set_source(cr,g); cairo_pattern_destroy(g)
    cairo_new_path(cr); cairo_arc(cr,x,y,r*3.1,0,2*math.pi); cairo_fill(cr)
  end
  local g=cairo_pattern_create_radial(x-r*0.42*S,y-r*0.42*S,0,x,y,r*1.18*S)
  cairo_pattern_add_color_stop_rgba(g,0,lightc[1],lightc[2],lightc[3],1)
  cairo_pattern_add_color_stop_rgba(g,0.55,lightc[1],lightc[2],lightc[3],0.85)
  cairo_pattern_add_color_stop_rgba(g,1,darkc[1],darkc[2],darkc[3],1)
  cairo_set_source(cr,g); cairo_pattern_destroy(g)
  cairo_new_path(cr); cairo_arc(cr,x,y,r,0,2*math.pi); cairo_fill(cr)
end

-- The moon: lit fraction shaded along a soft terminator offset by (1-2*lit),
-- rotated to face the sun. Blended rather than hard-clipped, so the phase
-- boundary is a gradient instead of a straight cut.
local function crescent_moon(cr,x,y,r,lit)
  local off=(1-2*lit)*r
  local MOON_LIT=col(0xd9,0xdb,0xe6)
  local MOON_MID=col(0x1a,0x1c,0x24)
  local MOON_DARK=col(0x10,0x11,0x18)
  -- terminator position: 0.5 at half-lit, sliding to 0 (full) / 1 (new). Clamped
  -- so the stop never inverts at the extremes.
  local term=math.max(0.02,math.min(0.98,0.5+(0.5-lit)*0.9))
  local g=cairo_pattern_create_radial(x-off,y-off*0.6,r*0.1,x,y,r*1.25)
  cairo_pattern_add_color_stop_rgba(g,0,MOON_LIT[1],MOON_LIT[2],MOON_LIT[3],1)
  cairo_pattern_add_color_stop_rgba(g,term,MOON_MID[1],MOON_MID[2],MOON_MID[3],1)
  cairo_pattern_add_color_stop_rgba(g,1,MOON_DARK[1],MOON_DARK[2],MOON_DARK[3],1)
  cairo_set_source(cr,g); cairo_pattern_destroy(g)
  cairo_new_path(cr); cairo_arc(cr,x,y,r,0,2*math.pi); cairo_fill(cr)
end

-- ------------------------------------------------------------
--  CALENDAR
--  A year engraved around the dial: a day tick for every day of the
--  year, heavier ticks and a letter at each month boundary, every
--  tenth day numbered, and a brass date hand on today.
--
--  NO SOLID FILL. The dark annular band is exactly what produced the
--  "black wedge" in the previous implementation. Pixel forensics showed
--  the fill was geometrically PERFECTLY symmetric -- the wedge was a
--  perceptual/contrast artefact, the flat dark annulus between two
--  bright plaques reading as a void. Nine fine concentric grooves give
--  the same sense of a recessed track with no flat mass to anchor on.
--
--  ONE module-level text-extents struct for the whole file, reused by
--  every label. Allocating one per call inside a per-label loop is the
--  worst leak in this codebase: lua-cairo does not tie that userdata's
--  lifetime to the Lua GC, so every glyph of every frame leaked
--  (~1 MB/s, gigabytes/hour) while the widget looked perfect.
-- ------------------------------------------------------------
local TEXT_EXT=cairo_text_extents_t:create()

-- IMPORTANT: y is a BASELINE. Glyphs ascend toward smaller screen-y, so on a
-- ring the cap height shifts the radius by CAP*cos(a) -- outward at 12
-- o'clock, inward at 6, tangential at 3 and 9. For any text placed ON a ring,
-- pass a baseline radius of MID-(CAP/2)*cos(a) with CAP=size*0.73, or it will
-- be centred at the top and pushed off the inner edge at the bottom.
local function label(cr,str,x,y,size,c,a,font)
  cairo_select_font_face(cr,font or "DejaVu Sans Mono",CAIRO_FONT_SLANT_NORMAL,CAIRO_FONT_WEIGHT_BOLD)
  cairo_set_font_size(cr,size*S)
  cairo_text_extents(cr,str,TEXT_EXT)
  rgba(cr,c,a or 1)
  cairo_move_to(cr,x-TEXT_EXT.width/2-TEXT_EXT.x_bearing,y)
  cairo_show_text(cr,str)
end

local CAL_IN,CAL_OUT=252,272
-- Baseline for the day numerals, centred in the calendar band. Derived from
-- CAL_IN/CAL_OUT rather than hardcoded so the row can never drift off the
-- band's midpoint when those constants change. label() uses its y argument
-- as the BASELINE and glyphs extend upward from it, so the baseline is
-- pushed below the band midpoint by roughly half the cap height (8pt DejaVu
-- Sans Mono Bold caps are ~6.2 units) to centre the ink rather than the
-- baseline. That puts the row at r258..r264 inside a band spanning r252..r272.
local CAL_MID=(CAL_IN+CAL_OUT)/2
local CAL_NCAP=8*0.73          -- cap height of the 8pt day numerals, ~0.73 em
-- The month letters get their OWN ring, out in the free annulus between the
-- inner groove (279) and the graduation track (319). The calendar band is
-- only 20 units wide and cannot carry a 12-letter row and a 36-number row at
-- a legible size at the same time -- cramming both is what made the earlier
-- single-ring version unreadable.
local ML_RING_IN,ML_RING_OUT=285,306
-- The month initials need an angle-dependent baseline radius, not a fixed one.
-- label() takes y as the BASELINE and glyphs always ascend toward smaller
-- screen y, so the cap height adds h*cos(a) to the radius: outward at 12
-- o'clock, inward at 6 o'clock, purely sideways at 3 and 9. A single fixed
-- baseline therefore centres the letters at the top and pushes them off the
-- inner edge at the bottom. Placing the baseline at MID - CAP/2*cos(a) keeps
-- the middle of the cap-height block on the ring centreline at every angle.
local ML_MID=(ML_RING_IN+ML_RING_OUT)/2
local ML_CAP=15*0.73          -- DejaVu Sans cap height, ~0.73 em
local MDAYS={31,28,31,30,31,30,31,31,30,31,30,31}
local MON1='JFMAMJJASOND'

local function leap(y) return (y%4==0 and y%100~=0) or y%400==0 end
local function mdays(y,i) return MDAYS[i]+((i==2 and leap(y)) and 1 or 0) end

-- yday on which each month begins, leap-safe
local function month_starts(y)
  local t={} local acc=1
  for i=1,12 do t[i]=acc; acc=acc+mdays(y,i) end
  return t
end

local function calendar_ring(cr,d)
  local y=d.year
  local nd=leap(y) and 366 or 365
  local ms=month_starts(y)
  cairo_save(cr)
  cairo_set_line_cap(cr,CAIRO_LINE_CAP_BUTT)

  -- nine concentric machined grooves in place of a solid dark band
  local gn=9
  local gstep=(CAL_OUT-CAL_IN)/(gn+1)
  for i=1,gn do
      local a=(i%2==1) and 0.22 or 0.15
      orbit(cr,CAL_IN+gstep*i,B3,a,0.6)
    end
    orbit(cr,CAL_IN ,B3,0.70,0.9)
    orbit(cr,CAL_OUT,B3,0.75,1.0)

  -- one stroke for all 365/366 day ticks: a path with many subpaths,
  -- which is far cheaper than 366 separate arc+stroke pairs
    cairo_set_line_width(cr,0.7*S); rgba(cr,B2,0.60)
  cairo_new_path(cr)
  for day=1,nd do
    local ang=((day-0.5)/nd)*2*math.pi
    local x1,y1=pos(CAL_OUT-0.5,ang)
    local x2,y2=pos(CAL_OUT-3.2,ang)
    cairo_move_to(cr,x1,y1); cairo_line_to(cr,x2,y2)
  end
  cairo_stroke(cr)

  -- month boundaries: longer and brighter
    -- Month boundaries: longer and brighter than the day ticks. The inner end
    -- stops at r268.2, clear of the day numerals' worst-case ink edge (r267.8
    -- at 6 o'clock). This matters because 1 March IS day 60 in a common year,
    -- so the March boundary tick and the "60" numeral land on the SAME angle
    -- and used to overprint each other.
    cairo_set_line_width(cr,1.5*S); rgba(cr,B1,0.85)
    cairo_new_path(cr)
    for i=1,12 do
      local ang=((ms[i]-0.5)/nd)*2*math.pi
      local x1,y1=pos(CAL_OUT-0.5,ang)
      local x2,y2=pos(CAL_OUT-3.8,ang)
    cairo_move_to(cr,x1,y1); cairo_line_to(cr,x2,y2)
  end
  cairo_stroke(cr)

  -- month boundary spokes bridging the two calendar rings, so every letter
  -- is visibly tethered to the span of days it governs
    cairo_set_line_width(cr,1.2*S); rgba(cr,B1,0.75)
  cairo_new_path(cr)
  for i=1,12 do
    local ang=((ms[i]-0.5)/nd)*2*math.pi
    local x1,y1=pos(CAL_OUT-0.5,ang)
    local x2,y2=pos(ML_RING_IN+0.5,ang)
    cairo_move_to(cr,x1,y1); cairo_line_to(cr,x2,y2)
  end
  cairo_stroke(cr)

  -- the month-letter ring, closed top and bottom so it reads as a chapter
  -- rather than as loose type floating in a gap
    orbit(cr,ML_RING_IN,B3,0.70,0.9)
    orbit(cr,ML_RING_OUT,B3,0.75,1.0)

  -- WHICH MONTH. Only INITIALS are drawn (MON1 = 'JFMAMJJASOND'), so the ring on
  -- its own is ambiguous: J three times (Jan/Jun/Jul), M twice (Mar/May), A
  -- twice (Apr/Aug). The boundaries and spokes are what really identify a
  -- sector, so "which month is it" meant counting spokes. The CURRENT month's
  -- initial is therefore drawn at full brightness and the other eleven recede.
  --
  -- PURE BRIGHTNESS: same GOLD hue, same 15.0 size, so nothing moves radially
  -- or angularly and the highlight cannot disturb the plaque clearances that
  -- were tuned against these letters. 1.0 vs 0.28 composites to roughly luma
  -- 201 vs 101 over the near-black plate (GOLD = rgb(232,200,124), luma
  -- = 255*(0.2126R+0.7152G+0.0722B) with alpha already applied). 0.28 was
  -- tried first and read as too dim at luma 56, so the eleven now sit at 101 --
  -- clearly recessed, still comfortably legible as letters.
  -- month initials, centred in their own month, on the letter ring. The
  -- baseline radius follows the angle so the ink stays centred in the band
  -- all the way round (see ML_MID/ML_CAP above).
  for i=1,12 do
    local mid=ms[i]-1+mdays(y,i)/2
    local a=((mid-0.5)/nd)*2*math.pi
    local x,y=pos(ML_MID-(ML_CAP/2)*math.cos(a),a)
    local am=(i==d.month) and 1.0 or 0.50
    label(cr,MON1:sub(i,i),x,y,15.0,GOLD,am)
  end

  -- Every tenth day numbered, ink centred in the calendar band. Same
  -- angle-dependent baseline as the month initials (see ML_MID/ML_CAP):
  -- without the cos(a) term these sit correctly at 6 o'clock and crowd the
  -- outer edge at 12, because glyphs ascend toward smaller screen y.
  for day=10,nd,10 do
    local a=((day-0.5)/nd)*2*math.pi
    local x,y=pos(CAL_MID-(CAL_NCAP/2)*math.cos(a),a)
    label(cr,tostring(day),x,y,8.0,B1,0.62)
  end

  -- THE DATE HAND, now a SINGLE stroke. It was two: a thin dim taper in front
  -- of the bright hand, visible only from r0 to r3 because the bright stroke is
  -- wider and covers the rest. The user read that dim segment as a TAIL coming
  -- off the back (inward) end, so the taper and the r0/r3 pair are gone and the
  -- hand now starts bluntly at r0. The arrowhead below is untouched.
  -- r0 is the inner end -- a LARGER radius pulls the hand back toward the centre
  -- and shortens it. TIP_R is a separate knob, so the approved point stays put.
  local ang=((d.yday-0.5)/nd)*2*math.pi
  local r1=258                       -- tip end, where the bright hand stops
  local r0=172                       -- inner end (was a 162->172 dim taper)
  local x0,y0=pos(r0,ang)
  local x2,y2=pos(r1,ang)
  cairo_set_line_width(cr,1.9*S); rgba(cr,GOLD,0.60)
  cairo_new_path(cr); cairo_move_to(cr,x0,y0); cairo_line_to(cr,x2,y2); cairo_stroke(cr)
  -- The arrowhead: a slender dart aligned to the needle axis. Every radius is
  -- derived from the tip so the shape can be re-proportioned without the point
  -- drifting -- the old version hard-coded the centre at 262, so simply growing
  -- the head pushed the tip outwards.
  -- Two knobs set "how sharp", and they pull against each other:
  --   included angle at the tip = 2*atan(TIP_W / (TIP_LEN*TIP_SH))
  -- so RAISING TIP_SH (shoulder further back from the tip) and LOWERING TIP_W
  -- both make it sharper. Shrinking TIP_LEN alone does NOT -- it shortens the
  -- point and the taper together, leaving the angle unchanged. That is why the
  -- first dart (TIP_SH 0.38, W 4.4) measured 79 deg and the "sharpened" one
  -- measured 79.6: I had cut length and width in the same proportion, which is
  -- a resize, not a sharpening.
  -- NOTE the perpendicular is needed because the old version offset the
  -- lozenge in SCREEN axes, so it sat at 45 degrees to the hand for all but
  -- four days of the year and its radial extent wobbled +/-1.9 units as the
  -- hand turned.
  local TIP_R=269.0                   -- outer point (was 266.4, lengthened)
  local TIP_LEN=16                    -- tip back to the tail point
  local TIP_SH=0.42                   -- shoulder this far back from the tip
  local TIP_W=3.6                     -- lateral HALF-width at that shoulder
  local px,py=pos(TIP_R,ang)
  local bx,by=pos(TIP_R-TIP_LEN,ang)
  local sx,sy=pos(TIP_R-TIP_LEN*TIP_SH,ang)
  local ox,oy=math.cos(ang)*TIP_W*S,math.sin(ang)*TIP_W*S
  cairo_new_path(cr)
  cairo_move_to(cr,px,py)
  cairo_line_to(cr,sx+ox,sy+oy)
  cairo_line_to(cr,bx,by)
  cairo_line_to(cr,sx-ox,sy-oy)
  cairo_close_path(cr)
  rgba(cr,GOLD,0.95); cairo_fill(cr)
  cairo_set_line_width(cr,0.9*S); rgba(cr,B4,0.85); cairo_stroke(cr)
  cairo_restore(cr)
end

-- ------------------------------------------------------------
--  HUD PLAQUES.  12 o'clock ONLY so far -- one element at a time.
--
--  Same language as the cyber orrery (hud_plate + arc_text), but ported by hand
--  onto ONE shared cairo_text_extents_t (EXT, declared near the top). The cyber
--  file allocated a fresh extents object PER GLYPH at 6 call sites, which is
--  documented leak class #1 in this codebase, so this must never be a blind
--  copy/paste of that file. Cairo writes into the struct on every call and
--  keeps no reference, so reusing EXT is correct.
--
--  NOTE on radial budget: the month initials already own r285..306 all the way
--  round (ML_RING_IN/OUT), and January's sits 14.79 deg from 12 o'clock. The
--  plaque therefore has to stay clear of it in ANGLE, not radius -- its radial
--  span deliberately reaches across the letter ring and the graduation track
--  (319..336) the way the cyber plaques did.
-- ------------------------------------------------------------
-- Radial inset (INT_D) and angular lip (LIP_D) of the plate frame. Only the
-- ANGULAR padding is tuned here: the radial extent stays riw..row, so the
-- plaque keeps its full height and gets narrower, not squatter.
--
-- PLAQUE_RI / PLAQUE_RO are the plaque frame's radial extent, and they are
-- pinned to the letter-ring geometry rather than left as bare literals, because
-- they have to agree with it to the unit.
--
-- THE RING THIS SITS ON. calendar_ring() draws the month-letter band's edge
-- rings at ML_RING_IN+0.5 = 285.5 and ML_RING_OUT = 306 (lines 534-535), and
-- the letters themselves are ink-centred on ML_MID = 295.5 with a cap height of
-- ML_CAP = 15*0.73 = 10.95. So a letter's ink spans r290..r301 while the ring
-- under it sits at 285.5 -- the letters overhang their own ring by 4.5 units
-- and sit only 4.5 units clear of it. THAT is the "bottom of the F is almost
-- touching the ring" relationship, and it is the ring the plaque frame belongs
-- against.
--
-- Getting this wrong is expensive. The dial has four other rings a plaque edge
-- could be aimed at -- 276 and 279 (the frame() inner pair) and 319/336 (the
-- graduation tracks) -- and an earlier pass pinned the lip to 279, six units
-- further in than intended. It looked right in the arithmetic and was wrong on
-- screen. The identifying feature is the overhanging letters: only the 285.5
-- ring has month initials sitting on top of it.
--
-- The lip now stands OFF that ring by RING_GAP rather than sitting on it, so the
-- ring reads as its own bright line with bare plate showing between it and the
-- plaques all the way round. A gap of 0 made the two merge; 4 units (~4px) is
-- enough to separate them and still reads as a groove, not a void.
--
-- THE COUPLING THIS CREATES, which is why the text radii in hud_readout() move
-- with it: hud_plate derives the dark inset's inner edge as PLAQUE_RI - INT_D,
-- so the frame edge and the inset edge move TOGETHER. Push the frame out and
-- the inset's inner edge follows it out, and any text still sitting at the old
-- radius ends up drawn over the brass lip and then over bare plate -- the text
-- is drawn after the plaque, so nothing would error, it would just look wrong.
-- Every innermost line (12:00 date, 3:00 inner word, 6/9 titles) is therefore
-- held at least 2 units inside the new inset edge. Those radii are NOT
-- independently tunable: moving one without the other reintroduces the fault.
--
-- Outer edge unchanged at 332: the plaques deliberately span the letter band and
-- the graduation track (319..336) to cover them, and pulling the outer edge in
-- would open dark sectors where the old wedge used to be.
local RING_GAP=4.0
local PLAQUE_RI=285.5+RING_GAP+2.6
local PLAQUE_RO=332.0
local INT_D=2.6*S
local LIP_D=1.0*DEG
local FMONO="DejaVu Sans Mono"

local function seg_reverse_arc(cr,cx,cy,r,a1,a2,n)
  for i=1,n do
    local a=a1+(a2-a1)*i/n
    cairo_line_to(cr,cx+math.cos(a)*r,cy+math.sin(a)*r)
  end
end

local function ring_sector_sq(cr,ri,ro,t0,t1)
  cairo_new_path(cr)
  cairo_arc(cr,CX*S,CY*S,ro*S,t0-math.pi/2,t1-math.pi/2)
  cairo_line_to(cr,CX*S+math.sin(t1)*ri*S,CY*S-math.cos(t1)*ri*S)
  seg_reverse_arc(cr,CX*S,CY*S,ri*S,t1-math.pi/2,t0-math.pi/2,16)
  cairo_close_path(cr)
end

-- dark plate + brass frame + two corner glints
--
-- PALETTE, second attempt. The first pass filled the face with neutral
-- near-black (0x030302 etc.), borrowed from the cyber orrery where a black
-- panel suits a green scope. Here it read as a hole punched through a brass
-- dial -- wrong material, not just wrong colour. Everything is now a darkened
-- member of the SAME B1..B4 brass family that frame() and orbits() use, so the
-- plaque is the same metal as the rest of the instrument: brass frame, dark
-- warm bronze face for the text to sit on. Alpha is 0.97 so the graduation
-- ticks behind do not show through the face.
local function hud_plate(cr,riw,row,t0,t1)
  local r0,r1=riw-INT_D,row+INT_D
  local a0,a1=t0-LIP_D,t1+LIP_D
  ring_sector_sq(cr,r0,r1,a0,a1)
  radial(cr,CX*S,CY*S,r0*S,r1*S,
    {{0,col(0x4a,0x3a,0x1e),0.97},{0.50,col(0x2a,0x21,0x10),0.97},
     {0.95,col(0x5e,0x4c,0x28),0.97},{1,col(0x6e,0x59,0x30),0.97}})
  cairo_fill(cr)
  cairo_set_line_width(cr,0.8*S); rgba(cr,B1,0.75)
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,r1*S,a0-math.pi/2,a1-math.pi/2); cairo_stroke(cr)
  cairo_set_line_width(cr,0.7*S); rgba(cr,B3,0.70)
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,r0*S,a0-math.pi/2,a1-math.pi/2); cairo_stroke(cr)
  -- inner face, darker, so text has a ground to sit on
  ring_sector_sq(cr,riw,row,t0,t1)
  radial(cr,CX*S,CY*S,riw*S,row*S,
    {{0,col(0x26,0x1e,0x10),0.97},{0.55,col(0x16,0x11,0x07),0.97},
     {1,col(0x0d,0x09,0x04),0.97}})
  cairo_fill(cr)
  cairo_set_line_width(cr,0.7*S); rgba(cr,B2,0.70)
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,row*S,t0-math.pi/2,t1-math.pi/2); cairo_stroke(cr)
  cairo_set_line_width(cr,0.7*S); rgba(cr,B3,0.60)
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,riw*S,t0-math.pi/2,t1-math.pi/2); cairo_stroke(cr)
  local rmid=(r0+r1)/2
  -- Glints sit centred in the lip band. They used to be a flat 1.0 deg from
  -- the plate edge, which put them exactly ON the inner lip once LIP_D dropped
  -- to 1.0 deg -- now they track the lip instead of a hard-coded offset.
  for _,ga in ipairs({a0+LIP_D*0.55,a1-LIP_D*0.55}) do
    local bx,by=CX*S+math.sin(ga)*rmid*S,CY*S-math.cos(ga)*rmid*S
    rgba(cr,GOLD,0.85)
    cairo_new_path(cr); cairo_arc(cr,bx,by,1.5*S,0,2*math.pi); cairo_fill(cr)
  end
end

-- angular width of a set of strings, in radians. Uses the shared EXT.
local function arc_span(cr,rad,segs)
  local total=0
  for _,sg in ipairs(segs) do
    cairo_select_font_face(cr,FMONO,CAIRO_FONT_SLANT_NORMAL,CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr,sg.size*S)
    for i=1,#sg.str do
      cairo_text_extents(cr,sg.str:sub(i,i),EXT)
      total=total+EXT.x_advance
    end
  end
  return total/(rad*S)
end

-- Per-glyph text laid along a circle, each glyph rotated to the ring and its
-- INK BOX centred (y0 = -beary - h/2). Centring the ink in the glyph's own
-- rotated space is radial centring, at every angle and any radius -- so this
-- idiom needs NO cos(a) baseline fudge. See AGENTS.md TEXT-ON-A-RING.
local function arc_text(cr,cx,cy,rad,ang_center,segs,rot_off)
  rot_off=rot_off or 0
  local midx,midy=cx+math.sin(ang_center)*rad*S,cy-math.cos(ang_center)*rad*S
  local chars={}
  for _,sg in ipairs(segs) do
    cairo_select_font_face(cr,FMONO,CAIRO_FONT_SLANT_NORMAL,CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr,sg.size*S)
    for i=1,#sg.str do
      cairo_text_extents(cr,sg.str:sub(i,i),EXT)
      chars[#chars+1]={ch=sg.str:sub(i,i),adv=EXT.x_advance,bearx=EXT.x_bearing,
        w=EXT.width,h=EXT.height,beary=EXT.y_bearing,sg=sg}
    end
  end
  local total=0
  for _,cc in ipairs(chars) do total=total+cc.adv end
  local dir=(rot_off==0) and 1 or -1
  local a=ang_center-dir*(total/(rad*S))/2
  for _,cc in ipairs(chars) do
    a=a+dir*(cc.adv/(rad*S))/2
    local px,py=cx+math.sin(a)*rad*S,cy-math.cos(a)*rad*S
    cairo_save(cr)
    cairo_translate(cr,px,py)
    cairo_rotate(cr,a+rot_off)
    cairo_select_font_face(cr,FMONO,CAIRO_FONT_SLANT_NORMAL,CAIRO_FONT_WEIGHT_BOLD)
    cairo_set_font_size(cr,cc.sg.size*S)
    local x0,y0=-cc.bearx-cc.w/2,-cc.beary-cc.h/2
    local sg=cc.sg
    if sg.lip then                      -- engraved: dark lip offset, then body
      cairo_set_source_rgba(cr,sg.lip[1],sg.lip[2],sg.lip[3],sg.lipA or 0.7)
      cairo_move_to(cr,x0+(sg.depth or 1.1)*S,y0+(sg.depth or 1.1)*S)
      cairo_show_text(cr,cc.ch)
      cairo_set_source_rgba(cr,sg.body[1],sg.body[2],sg.body[3],sg.bodyA or 0.9)
    end
    cairo_move_to(cr,x0,y0)
    cairo_show_text(cr,cc.ch)
    cairo_restore(cr)
    a=a+dir*(cc.adv/(rad*S))/2
  end
end

-- Angular brass margin between the outermost glyph ink and the plate edge.
-- This is the plaque's only horizontal-fit knob, and it is deliberately small:
-- at 4.2 deg (+1.5 lip) there was 5.7 deg of empty brass either side of the
-- text, ~31 grid units at r310, which read as a wide pillowy plate and left
-- the month letters with almost no air. 2.2 deg still leaves a visible border
-- (~13 grid units at r310) while opening the corridor to the letter ring.
local BEZ_PM=2.2*DEG

  -- ---------------------------------------------------------------------
  -- PER-LINE CENTERING NUDGES
  --
  -- Each text line on the dial can be shifted ALONG its arc independently, in
  -- degrees, without touching any of the geometry or sizing maths below. This
  -- exists because a single global "centering" fix cannot be right for all
  -- nine lines: they differ in font size, in radius, and in how their glyph
  -- side-bearings fall, so each needs its own nudge rather than a shared one.
  --
  -- ONE unit nudge per plaque, moving BOTH rows together, in two components:
  --     radius = radius + NUDGE.nXX[1]      -- grid units,  + = outward
  --     angle  = angle  + NUDGE.nXX[2]*DEG   -- degrees,     + = clockwise
  --
  -- WHY TWO COMPONENTS. The radial axis came first, because "this line sits too
  -- high / too low in the plaque" is a radial fault. The next observation at 12:00
  -- was "down AND to the right", and "to the right" is a tangential move that no
  -- amount of radial nudge can produce -- they are independent axes, not two names
  -- for one. So the tangential component came back on purpose, instead of being
  -- faked by shoving a radial value around and calling it a sideways move.
  --
  -- THE UNITS DIFFER ON PURPOSE: slot 1 is grid units (~1px each), slot 2 is
  -- degrees. At r~300 one degree spans about 5.2 grid units, so 1.0 and 1.0 are
  -- the same visual size in either slot.
  --
  -- SIGN WARNING for slot 2: + is CLOCKWISE, and clockwise does not read as
  -- "right" at every seat -- it goes right at 12:00, down at 3:00, LEFT at 6:00
  -- and up at 9:00. Slot 1 has no such trap: + is always outward.
  --
  -- Safe range for slot 1 is about -3.5..+3, and the INNER END is the binding
  -- limit, not the outer one. The 12:00 date is the innermost line on the whole
  -- dial, and arc_text INK-CENTRES each glyph, so its ink spans
  -- (T12_DATE + slot1) +/- capheight/2 with capheight = 13*0.73 = 9.49.
  -- The binding edge is the plate's inner lip LINE -- stroked at riw = PLAQUE_RI
  -- = 292.1 with width 0.7, so it OCCUPIES r291.75..r292.45 and it is the INNER
  -- EDGE of that stroke, 291.75, that the text must clear, not the centre:
  --     slot1 = -3.0 -> ink bottom 292.255  (0.505 clear of the stroke)
  --     slot1 = -3.5 -> ink bottom 291.755  (0.005 clear: exact contact)
  --     slot1 = -4.0 -> ink bottom 291.255  (0.495 ONTO the stroke)
  -- So -3.5 is free and is the real floor; -4.0 rides the lip and would need the
  -- plate's inner edge moved, which is a PLATE change, not a text change -- ask
  -- before going there rather than quietly letting the text ride the frame.
  -- Moving both rows together preserves their 5.0-unit ink-to-ink gap exactly.
  -- Outward is roomier: +3 still leaves ~3 units before the plaque's outer lip.
  --
  --   n12 12:00 time+date   n3 3:00 phase words
  --   n6  6:00 ORRERY+day   n9 9:00 LUNA+age
  -- ---------------------------------------------------------------------
  -- Room budget, measured from the ink edges to the lip STROKES (inner lip
  -- occupies r291.75..292.45, outer lip r331.65..332.35). Ink = anchor +/-
  -- capheight/2, capheight = size*0.73:
  --   3:00  inner ink 294.62 -> 2.87 in / outer ink 317.38 -> 14.27 out
  --   6:00  inner ink 295.43 -> 3.68 in / outer ink 324.02 ->  7.63 out
  --   9:00  inner ink 295.43 -> 3.68 in / outer ink 324.02 ->  7.63 out
  -- So 9:00's inward move is the tightest of the three: -2.5 still leaves 1.18
  -- units to the lip. Push past about -3.6 there and the title rides the frame.
  -- 6:00 IS NEARLY OUT OF ROOM OUTWARD. The binding line is the DAY line
  -- (P6_DAY_R=320, size 11, ink outer edge 324.02), so the hard ceiling is
  -- 331.65 - 324.02 = +7.63 by pure arithmetic. At +7.75 the ink edge sits at
  -- 331.77, i.e. ~0.12 grid units (~0.1 px) PAST the lip's inner edge -- a
  -- deliberate overshoot the user judged acceptable by eye. Past that the text
  -- visibly rides the frame. Any further outward travel would require stopping
  -- the title and the day line moving as one block; the plate's radial extent
  -- (PLAQUE_RI..PLAQUE_RO, 292.1..332) is shared by all four plaques and must
  -- not be changed, since it would move the other three with it.
  -- 3:00 has no such problem: at +11.0 its outer ink is 328.02, 3.64 clear,
  -- and inward it has 13.9 spare. Its binding line is the DAY line, same as 6:00.
  -- NB the cap-height box over-estimates by the glyphs' side bearing, which is
  -- why +7.75 on 6:00 reads with visible air where the arithmetic said none.
  --
  -- SLOT 2 is degrees, positive CLOCKWISE, and only arc_text receives it --
  -- hud_plate stays centred on the seat axis, so a tangential nudge slides the
  -- TEXT WITHIN its plate and the plate's clearance against the month letters
  -- does not move. Built-in margin between text and plate edge is BEZ_PM
  -- (2.2 deg) plus whatever the text is narrower than the 8-char reference span.
  -- 9:00 is the tightest tangentially: its plate half-width is 6.32 deg, so -1.0
  -- leaves ~1.2 deg before the text reaches the plate edge; -1.5 would leave 0.7.
  -- 3:00 and 6:00 have room for a good deal more in either direction.
  local NUDGE={
    n12={-3.5, 0.8},   -- 12:00: inward 3.5, clockwise 0.8  (down & right)
    n3 ={11.0, 1.5},   -- 3:00: out 11.0 (up) + 1.5 deg CW (toward April's A)
    n6 ={ 7.75,-1.5},  -- 6:00: out 7.75 (up) + 1.5 deg CCW (toward June's J)
    n9 ={-2.5,-1.0},   -- 9:00: in 2.5  (down) + 1.0 deg CCW
  }
local WD={'SUN','MON','TUE','WED','THU','FRI','SAT'}

local function hud_readout(cr,d,now)
  -- Both radii moved OUTWARD, because PLAQUE_RI moved outward and the 12:00
  -- date is the innermost line on the dial (was 290, ink reaching r285.3 -- it
  -- was already overrunning the inset edge). The pair was also squeezed
  -- together: ink-to-ink gap 8.0 -> 5.0 units, using the empty space at the
  -- OUTER end of the plaque rather than the crowded inner end.
  local T12_TIME=317      -- HH:MM (.SS)
  local T12_DATE=300      -- WD MM/DD
  local body,lip=GOLD,B4
  local tstr=string.format('%02d:%02d',d.hour,d.min)
  local sstr=string.format('.%02d',math.floor(now%60))
  local dstr=string.format('%s %02d/%02d',WD[d.wday],d.month,d.day)

  -- Plate is sized from the WIDER of the two rows, so the plate never
  -- pinches around whichever line is shorter.
  local h12=math.max(
    arc_span(cr,T12_TIME,{{str=tstr,size=20},{str=sstr,size=10}}),
    arc_span(cr,T12_DATE,{{str=dstr,size=13}})
  )/2+BEZ_PM
  hud_plate(cr,PLAQUE_RI,PLAQUE_RO,-h12,h12)

  arc_text(cr,CX,CY,T12_TIME+NUDGE.n12[1],NUDGE.n12[2]*DEG,{
    {str=tstr,size=20,body=body,bodyA=1.0,lip=lip,lipA=0.7,depth=1.4},
    {str=sstr,size=10,body=body,bodyA=0.9,lip=lip,lipA=0.6,depth=1.1},
  })
  arc_text(cr,CX,CY,T12_DATE+NUDGE.n12[1],NUDGE.n12[2]*DEG,{
    {str=dstr,size=13,body=body,bodyA=0.85,lip=lip,lipA=0.5,depth=1.2},
  })

  -- 3:00 -- moon phase on two stacked lines. This is the position the old
  -- wedge was reported in, so note what the geometry actually allows:
  --   March's letter ends at 73.86 deg, April's starts at 102.19 deg, giving
  --   a 28.3 deg corridor centred on 90 deg. Because the plaque spans the
  --   letter ring radially, it has to clear those two letters in ANGLE, which
  --   caps the text half-width at 12.19 - (4.2 margin + 1.5 lip) = 6.49 deg.
  --   A one-line "WAXING GIBBOUS" breaks that at every usable size; two
  --   stacked lines fit.
  --
  -- The plate is FIXED width, sized for the longest phase word ("CRESCENT",
  -- 8 chars) measured through the real font metrics rather than an assumed
  -- advance, so it does not breathe as the phase changes. A plate whose edges
  -- moved against April's letter would read as a defect, and an unstable
  -- silhouette is the last thing this band needs.
  --
  -- 12 pt is chosen to MATCH the 12:00 plaque's letter clearance. At 3:00 the
  -- plate half-width may not exceed 12.19 deg (April's letter starts at
  -- 102.19, the axis is at 90), and half of that is the 3.2 deg brass border,
  -- leaving 8.99 deg for ink. "CRESCENT" burns 0.4669 deg per point, so:
  --   19.26 pt = plate exactly TOUCHES April  -> unusable
  --   12.83 pt = 3.0 deg clearance
  --   12.00 pt = 3.39 deg clearance, vs 3.47 deg at 12:00  <- matched, hence 12
  -- P3_IR is the innermost line (inset margin 2.52) so it tracks PLAQUE_RI;
  -- the pair closes from an 11.2-unit ink gap to 5.2. h3 below is derived from
  -- P3_IR, but a larger radius SHRINKS an arc span, so the plate gets a shade
  -- narrower and the neighbouring month letters gain clearance.
  local P3_OR,P3_IR,P3_SZ=313,299,12.0
  local P3_A=math.pi/2
  local h3=arc_span(cr,P3_IR,{{str='88888888',size=P3_SZ}})/2+BEZ_PM+LIP_D
  hud_plate(cr,PLAQUE_RI,PLAQUE_RO,P3_A-h3,P3_A+h3)
  local w1,w2=phase_name(lunar_age(now)):match('^(%S+)%s+(%S+)$')
  arc_text(cr,CX,CY,P3_OR+NUDGE.n3[1],P3_A+NUDGE.n3[2]*DEG,{
    {str=w1,size=P3_SZ,body=body,bodyA=0.92,lip=lip,lipA=0.55,depth=1.1},
  })
  arc_text(cr,CX,CY,P3_IR+NUDGE.n3[1],P3_A+NUDGE.n3[2]*DEG,{
    {str=w2,size=P3_SZ,body=body,bodyA=0.85,lip=lip,lipA=0.45,depth=1.1},
  })

-- 6:00 -- ORRERY over the day-of-year, tying the plaque to the gold date
  -- needle pointing into the calendar ring above it.
  --
  -- CORRIDOR. Tightest on the dial, and asymmetric: June's letter ends 15.89
  -- deg from the axis but July's starts only 12.44 deg away, so JULY binds and
  -- the plate half-width may not exceed 12.44 deg.
  --
  -- ORDER. At 6:00 pos() gives y = CY + r, so a SMALLER radius sits HIGHER on
  -- screen -- the opposite of 12:00. "Day under the title" therefore means the
  -- title takes the SMALLER radius (296) and the day the larger (320).
  -- That inverts the usual trade, because glyph half-width scales as 1/r: the
  -- title now sits nearer the centre and so claims MORE angle, not less.
  -- Keeping "THE ORRERY" (10 chars) there caps the title at 14pt with only
  -- +1.18 deg to July. Dropping "THE" frees 6 characters, which buys BOTH a
  -- much larger title and a healthier plate:
  --     "THE ORRERY" 13pt r296 -> plate half 10.79  clearance +1.65 deg
  --     "ORRERY"     18pt r296 -> plate half  9.50  clearance +2.94 deg
  -- 18pt glyphs are 38% taller than 13pt AND the plate is roomier.
  --
  -- %02d keeps the day string at 11 chars for days 1-9, so the plate width
  -- does not shrink nine days a year; /366 in a leap year is also 11 chars, so
  -- the width is identical in either year.
  --
  -- NOTE: the full planet legend (46 chars) cannot live here at ANY readable
  -- size -- it overruns July by 17 deg at 10 pt and still overlaps at 7 pt.
  -- If the legend is wanted it needs a wider corridor, or shorter planet names.
  -- Title is the innermost line (inset margin 3.33) so it tracks PLAQUE_RI;
  -- this pair had the loosest spacing on the dial and closes 13.4 -> 7.4.
  local P6_TITLE_R,P6_DAY_R,P6_TITLE,P6_DAY=302,320,18.0,11.0
  local P6_A=math.pi
  local y6=d.year
  local d6=string.format('DAY %02d/%d',d.yday,leap(y6) and 366 or 365)
  local h6=math.max(
    arc_span(cr,P6_TITLE_R,{{str='ORRERY',size=P6_TITLE}}),
    arc_span(cr,P6_DAY_R,{{str=d6,size=P6_DAY}})
  )/2+BEZ_PM
  hud_plate(cr,PLAQUE_RI,PLAQUE_RO,P6_A-h6,P6_A+h6)
  -- rot_off=PI is REQUIRED at 6:00, and it does two jobs, not one.
  -- arc_text rotates each glyph by its own angle a, so at 6:00 a=PI would put
  -- the text upside down (0 deg at 12:00, 90 deg sideways at 3:00, 180 deg here).
  -- But un-rotating alone is not enough either: at the bottom of the dial
  -- x = CX + sin(a)*r and d/da(sin a) = cos(a) = -1, so advancing in +a moves
  -- LEFTWARD on screen and the text would read right-to-left. Passing a
  -- non-zero rot_off flips dir to -1 as well as the rotation, so the line both
  -- sits upright and reads left-to-right. This is the standard watch-dial rule:
  -- tops outward above 6, tops inward below it.
  arc_text(cr,CX,CY,P6_TITLE_R+NUDGE.n6[1],P6_A+NUDGE.n6[2]*DEG,{
    {str='ORRERY',size=P6_TITLE,body=body,bodyA=1.0,lip=lip,lipA=0.65,depth=1.5},
  },math.pi)
  arc_text(cr,CX,CY,P6_DAY_R+NUDGE.n6[1],P6_A+NUDGE.n6[2]*DEG,{
    {str=d6,size=P6_DAY,body=body,bodyA=0.80,lip=lip,lipA=0.45,depth=1.1},
  },math.pi)

  -- 9:00 -- the lunar age, completing the ring of four plaques.
  --
  -- CORRIDOR. Roomy compared with the other three seats. October's letter is
  -- the binding one at 12.88 deg from the axis (September sits at 15.51), so
  -- the plate half-width may not exceed 12.88 deg -- and unlike 6:00's July
  -- there is enough room for a full-size title AND a detail line without
  -- either being cut down:
  --     "LUNA"     18pt r296 -> plate half  7.40   (+5.48 to October)
  --     "AGE 12.4D" 11pt r320 -> plate half  8.54   (+4.34 to October)
  -- So 9:00 needs no compromise on type size the way 6:00 did, and no
  -- abbreviation the way the 46-char planet legend would have needed.
  --
  -- ORDER. At 9:00 the axis is horizontal, so unlike 6:00 the two radii are
  -- side by side rather than stacked, and the line order does not depend on
  -- which way y grows. The title takes the inner radius (296) and the detail
  -- the outer (320), matching 3:00's outer-detail / inner-title reading.
  --
  -- rot_off stays 0 here: at a = 3PI/2 the glyph rotation is -90 deg, so the
  -- text runs bottom-to-top with its tops facing outward, which is the
  -- standard watch-dial treatment for the 9 o'clock seat. Only 6:00 needs the
  -- PI offset (tops inward) because only there is the axis vertical.
  -- Same treatment as 6:00, and the same reason: LUNA is the innermost line.
  local P9_TITLE_R,P9_DET_R,P9_TITLE,P9_DET=302,320,18.0,11.0
  local P9_A=3*math.pi/2
  local age9=lunar_age(now)
  local a9=string.format('AGE %04.1fD',age9)
  local h9=math.max(
    arc_span(cr,P9_TITLE_R,{{str='LUNA',size=P9_TITLE}}),
    arc_span(cr,P9_DET_R,{{str=a9,size=P9_DET}})
  )/2+BEZ_PM
  hud_plate(cr,PLAQUE_RI,PLAQUE_RO,P9_A-h9,P9_A+h9)
  arc_text(cr,CX,CY,P9_TITLE_R+NUDGE.n9[1],P9_A+NUDGE.n9[2]*DEG,{
    {str='LUNA',size=P9_TITLE,body=body,bodyA=1.0,lip=lip,lipA=0.65,depth=1.5},
  })
  arc_text(cr,CX,CY,P9_DET_R+NUDGE.n9[1],P9_A+NUDGE.n9[2]*DEG,{
    {str=a9,size=P9_DET,body=body,bodyA=0.80,lip=lip,lipA=0.45,depth=1.1},
  })
end

-- RESTRAINED SUN CORONA (feature 6). Radially symmetric by construction, so it
-- cannot form the asymmetric mass that caused the old wedge. Lives in r24..50:
-- outside the sun disc (r18) and clear of Mercury's orbit (r55). Deliberately
-- thin and low-alpha -- this should read as heat shimmer, not as a bright ring.
local COR_IN,COR_OUT=24.0,50.0
local COR_RAYS=16
local function sun_corona(cr,now)
  local spin=now*0.03
  for i=0,COR_RAYS-1 do
    local a=(i/COR_RAYS)*2*math.pi+spin
    local k=0.5+0.5*math.sin(now*0.45+i*1.7)
    cairo_set_line_width(cr,(0.5+0.5*k)*S)
    cairo_set_source_rgba(cr,1.0,0.86,0.55,0.05+0.11*k)
    cairo_new_path(cr)
    cairo_move_to(cr,CX*S+math.sin(a)*COR_IN*S, CY*S-math.cos(a)*COR_IN*S)
    cairo_line_to(cr,CX*S+math.sin(a)*COR_OUT*S, CY*S-math.cos(a)*COR_OUT*S)
    cairo_stroke(cr)
  end
  for _,r in ipairs({46.0,51.0}) do
    cairo_set_line_width(cr,0.6*S)
    cairo_set_source_rgba(cr,1.0,0.86,0.55,0.10)
    cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,r*S,0,2*math.pi); cairo_stroke(cr)
  end
end

local function bodies(cr,now,d)
  local s  =now%60                       -- 0..60
  local mm =(now/60)%60                   -- 0..60
  local hh =(now/3600)%12                 -- 0..12
  local a_s=(s/60)*2*math.pi              -- mercury = seconds
  local a_m=(mm/60)*2*math.pi             -- venus   = minutes
  local a_hs=(hh/12)*2*math.pi            -- earth   = hours

  -- SUN at the centre: corona first so the halo veils the rays, then the halo
  sun_corona(cr,now)
  local sg=cairo_pattern_create_radial(CX*S,CY*S,0,CX*S,CY*S,40*S)
  cairo_pattern_add_color_stop_rgba(sg,0,1,0.95,0.78,0.90)
  cairo_pattern_add_color_stop_rgba(sg,0.5,0.95,0.75,0.40,0.50)
  cairo_pattern_add_color_stop_rgba(sg,1,0.90,0.60,0.30,0)
  cairo_set_source(cr,sg); cairo_pattern_destroy(sg)
  cairo_new_path(cr); cairo_arc(cr,CX*S,CY*S,40*S,0,2*math.pi); cairo_fill(cr)
  planet(cr,CX*S,CY*S,18*S,col(0xff,0xeb,0xb7),col(0xe0,0x9e,0x52))

  -- MERCURY, with a comet-trail gradient behind it along its own orbit
  do
    local x,y=pos(OR.MERCURY,a_s)
    for _,t in ipairs({{0.28,5,0.07},{0.15,3.3,0.18},{0.06,2,0.38}}) do
      cairo_set_line_width(cr,t[2]*S)
      cairo_set_source_rgba(cr,0.95,0.90,0.75,t[3])
      cairo_new_path(cr)
      cairo_arc(cr,CX*S,CY*S,OR.MERCURY*S,a_s-t[1]-math.pi/2,a_s-math.pi/2)
      cairo_stroke(cr)
    end
    -- Mercury is the fastest body AND the smallest: 0.59 px per frame at 10 fps.
    -- Checked two ways, because a slow body looks identical whether it is being
    -- quantised or merely slow. Headless pycairo, disc r=6.6: a 0.1 px edge shift
    -- moves edge pixels by up to 10.7 levels, so the rasteriser does respond to
    -- fractional positions. Separately, every coordinate-bearing cairo call in
    -- the body path is float -- no floor/ceil, no integer formatting, glow
    -- anchored on the same fractional x,y. So the motion is continuous; it just
    -- reads slowly. See ANTIALIASING GOTCHA in AGENTS.md.
    planet(cr,x,y,5.2*S,col(0xce,0xce,0xd4),col(0x7a,0x7a,0x84),true)
  end

  -- VENUS
  do local x,y=pos(OR.VENUS,a_m); planet(cr,x,y,6.6*S,col(0xe4,0xd9,0xb0),col(0x8c,0x7a,0x52),true) end

  -- EARTH, carrying the moon
  do
    local x,y=pos(OR.EARTH,a_hs)
    planet(cr,x,y,7.6*S,col(0x74,0xa8,0xd8),col(0x24,0x4a,0x74),true)
    local age=lunar_age(os.time()); local lit=lit_frac(age)
    local mo=(age/LUNAR_SYNODIC)*2*math.pi+a_hs
    crescent_moon(cr,x+math.sin(mo)*22*S,y-math.cos(mo)*22*S,3.7*S,lit)
  end

  -- MARS: rides the day-of-year, so it tracks the calendar ring
  do
    local doy=d.yday
    local x,y=pos(OR.MARS,(doy-0.5)/365.2425*2*math.pi)
    planet(cr,x,y,5*S,col(0xd0,0x6a,0x52),col(0x6e,0x2e,0x22),true)
  end

  -- JUPITER: slow decorative drift on an 11.9-year cycle
  do
    local x,y=pos(OR.JUPITER,((d.month-1)/12)*2*math.pi)
    planet(cr,x,y,9*S,col(0xd8,0xc0,0x9a),col(0x6a,0x56,0x3a),true)
  end

  -- SATURN: 84-year drift, with its ring
  do
    local x,y=pos(OR.SATURN,((d.year%84)/84)*2*math.pi)
    cairo_save(cr)
    cairo_translate(cr,x,y); cairo_rotate(cr,-0.45); cairo_scale(cr,1,0.42)
    cairo_set_line_width(cr,1.8*S/0.42); rgba(cr,B1,0.62)
    cairo_new_path(cr); cairo_arc(cr,0,0,9.5*S,0,2*math.pi); cairo_stroke(cr)
    cairo_restore(cr)
    planet(cr,x,y,6.4*S,col(0xd2,0xc8,0xa8),col(0x72,0x64,0x42),true)
  end
end

-- ------------------------------------------------------------
--  DRAW
-- ------------------------------------------------------------
-- 30-DEGREE NUMERALS (feature 2). Proportional DejaVu Sans, NOT the mono
-- face label() defaults to: at 15pt mono a 4-glyph numeral (IIII/VIII) is
-- 27-37 units wide and reached r270, 18 units INTO the calendar ring. The
-- proportional face at 12pt keeps every glyph inside r219..245. In the empty annulus between Saturn's orbit
-- (r216) and the calendar ring (r252). Drawn in the static plate layer so the
-- date needle, drawn later, correctly sweeps over them.
local NUM_R=234.0
local NUM_SIZE=12.0
local NUM_CAP=NUM_SIZE*0.73
local ROMAN={[1]='XII',[2]='I',[3]='II',[4]='III',[5]='IIII',[6]='V',
             [7]='VI',[8]='VII',[9]='VIII',[10]='IX',[11]='X',[12]='XI'}
local function hour_numerals(cr)
  for i=1,12 do
    local a=((i-1)/12)*2*math.pi
    local x,y=pos(NUM_R-(NUM_CAP/2)*math.cos(a),a)
    label(cr,ROMAN[i],x,y,NUM_SIZE,GOLD,0.62,"DejaVu Sans")
  end
end

function conky_main()
  -- conky_window is nil on the very first hook call; guard it or this throws
  if not conky_window then return end
  local w,h=conky_window.width,conky_window.height
  if not w or not h or w<8 or h<8 then return end
  S=math.max(0.01,math.min(w/GRID_W,h/GRID_H))
  local ss=SUPERSAMPLE

  -- The plate and the frame are static for a given window size, so they are
  -- drawn straight onto the window at 1x. Only the moving content (starfield,
  -- orbits, bodies) is rendered supersampled and filtered down over the top.
  -- Supersampling the whole canvas instead costs ~99ms/frame, because the
  -- full-window radial vignette then has to be evaluated at 2x resolution.
  local cs=cairo_xlib_surface_create(conky_window.display,conky_window.drawable,conky_window.visual,w,h)
  if not cs then return end
  local cr=cairo_create(cs)
  if not cr then cairo_surface_destroy(cs); return end

  plate(cr)
  hour_numerals(cr)

  if ss>1 then
    -- note the three-argument form: cairo_image_surface_create(format,w,h).
    -- Called with only two it returns a surface in an error state, and every
    -- draw onto it is silently discarded rather than throwing.
    local img=cairo_image_surface_create(CAIRO_FORMAT_ARGB32,w*ss,h*ss)
    if img and cairo_surface_status(img)==CAIRO_STATUS_SUCCESS then
      local ictx=cairo_create(img)
      if ictx then
        cairo_scale(ictx,ss,ss)   -- draw in 1x units
        -- cleared to fully transparent: this layer sits over the plate, and
        -- an image surface starts out holding uninitialised memory.
        cairo_set_source_rgba(ictx,0,0,0,0); cairo_paint(ictx)
        local d=os.date('*t')
        draw_starfield(ictx,os.time()%100000)
        orbits(ictx)
        calendar_ring(ictx,d)
        bodies(ictx,clock_now(),d)
        cairo_destroy(ictx)
        local p=cairo_pattern_create_for_surface(img)
        cairo_pattern_set_filter(p,CAIRO_FILTER_BILINEAR)
        -- Scale the destination by 1/ss so the larger buffer is filtered DOWN
        -- onto the window. Without this the pattern is sampled 1:1 and the
        -- top-left quarter of the supersampled layer lands on the window
        -- unscaled, putting everything in the wrong place.
        cairo_save(cr)
        cairo_scale(cr,1/ss,1/ss)
        cairo_set_source(cr,p)
        cairo_paint(cr)
        cairo_restore(cr)
        cairo_pattern_destroy(p)
      end
      cairo_surface_destroy(img)
    end
  else
    local d=os.date('*t')
    draw_starfield(cr,os.time()%100000)
    orbits(cr)
    calendar_ring(cr,d)
    bodies(cr,clock_now(),d)
  end

frame(cr)
    -- Drawn AFTER frame() on purpose: the plaque is meant to ride over the
    -- graduation track (319..336), the way the cyber plaques did. Called before
    -- it, frame's tick train would print straight over the readout.
    hud_readout(cr,os.date('*t'),clock_now())
    cairo_destroy(cr)
  cairo_surface_destroy(cs)
end
