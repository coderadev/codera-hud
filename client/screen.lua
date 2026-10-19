
HudScreen = {}
CoderaHud = CoderaHud or {}

local cachedScreen = nil   -- last measured screen table
local radarLayoutFromNui = false
local radarNuiInfo = 'n/a'
local radarLayout = nil    -- NUI-provided radar cx/cy/diameter override
local revision = 0         -- bumped every time the screen geometry changes

local RADAR_REFERENCE = { cx = 0.5, cy = 0.5, width = 1.0, height = 1.0 }

local FULL_RECT = { left = 0, top = 0, width = 1, height = 1 }

local function clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

local function isNumber(value)
    return type(value) == 'number' and value == value
end

local function measureGfxRect(alignX, alignY)
    SetScriptGfxAlign(string.byte(alignX), string.byte(alignY))
    SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)
    local x, y = GetScriptGfxPosition(0.0, 0.0)
    local x2, y2 = GetScriptGfxPosition(1.0, 1.0)
    ResetScriptGfxAlign()
    return { x = x, y = y, sx = x2 - x, sy = y2 - y }
end

local function getAspectRatio(screen)
    if isNumber(screen.aspect) and screen.aspect > 0 then
        return screen.aspect
    end
    return screen.width / screen.height
end

local function getRadarReference(screen)
    if radarLayout then
        return radarLayout
    end
   
    local diameter = 0.105 * screen.width
    radarLayout = {
        cx = 0.8975,
        cy = 0.10 + (diameter / 2) / screen.height,
        diameter = diameter
    }
    return radarLayout
end

function HudScreen.Get()
    if cachedScreen then
        return cachedScreen
    end
    HudScreen.Refresh(true)
    return cachedScreen
end

function HudScreen.Refresh(force)
    local width, height = GetActiveScreenResolution()
    if width < 1 or height < 1 then
        return
    end

    local aspect = GetAspectRatio(false)
    local physicalAspect = GetAspectRatio(true)
    local safezone = GetSafeZoneSize()
    local transform = measureGfxRect('L', 'T')

    if not (isNumber(transform.sx) and isNumber(transform.sy)
        and math.abs(transform.sx) >= 1e-5 and math.abs(transform.sy) >= 1e-5) then
        return
    end

    if not force and cachedScreen
        and cachedScreen.width == width
        and cachedScreen.height == height
        and math.abs(cachedScreen.aspect - aspect) < 1e-5
        and math.abs(cachedScreen.physicalAspect - physicalAspect) < 1e-5
        and math.abs(cachedScreen.safezone - safezone) < 1e-5
        and math.abs(cachedScreen.transform.x - transform.x) < 1e-5
        and math.abs(cachedScreen.transform.y - transform.y) < 1e-5
        and math.abs(cachedScreen.transform.sx - transform.sx) < 1e-5
        and math.abs(cachedScreen.transform.sy - transform.sy) < 1e-5 then
        return
    end

    revision = revision + 1
    local inset = (1 - clamp(safezone, 0.0, 1.0)) * 0.5
    cachedScreen = {
        width = width,
        height = height,
        aspect = aspect,
        physicalAspect = physicalAspect,
        safezone = safezone,
        revision = revision,
        transform = transform,
        safe = { left = inset, right = inset, top = inset, bottom = inset }
    }
    radarLayout = nil
    radarLayoutFromNui = false

    SendNUIMessage({ action = 'hudScreen', screen = cachedScreen })
    TriggerEvent('codera-hud:applyMinimapLayout')
    TriggerEvent('codera-hud:screenChanged')
end


function HudScreen.MinimapRect(x, y, width, height)
    local screen = HudScreen.Get()
    if not screen then
        return x, y, width, height
    end

    local reference = getRadarReference(screen)
    local transform = screen.transform
    local aspectRatio = getAspectRatio(screen)

    -- GTA minimap X units are fractions of a 16:9 wide area (height * 16/9), not of the
    -- real screen width, so on 16:10 / 4:3 / ultrawide X must be rescaled.
    local scaleX = transform.sy * (16.0 / 9.0) / (screen.width / screen.height)
    local diameter = reference.diameter * 0.9771428571428571
    local unitX = diameter / (screen.width * scaleX * RADAR_REFERENCE.width)
    local unitY = diameter / (screen.height * transform.sy * RADAR_REFERENCE.height)

    local cx = (reference.cx - transform.x) / scaleX + (x - RADAR_REFERENCE.cx) * unitX
    local cy = (reference.cy - transform.y) / transform.sy + (y - RADAR_REFERENCE.cy) * unitY
    return cx, cy, width * unitX, height * unitY
end


local function projectRadarRect(rect, zoom, offsetX, offsetY)
    local screen = HudScreen.Get()
    if not screen then
        return 0.0, 0.0, 0.0, 0.0
    end

    local reference = getRadarReference(screen)
    local transform = screen.transform
    local zoomK = clamp(tonumber(zoom) or 1.0, 0.5, 2.0)

    -- Ring size in REAL game pixels. The UI viewport can differ from the game
    -- resolution (e.g. 1920x1080 UI on a 1440x900 game), which squashes the ring
    -- into an ellipse, so width and height are taken separately.
    local wpx = (reference.wFrac and reference.wFrac * screen.width or reference.diameter) * zoomK
    local hpx = (reference.hFrac and reference.hFrac * screen.height or reference.diameter) * zoomK

    -- Engine calibration. The engine draws the map slightly differently depending on
    -- aspect ratio, so by default the correction is interpolated from two measured
    -- points (16:10 and 16:9). Set Config.RadarAutoCalibrate = false (or use /vhudmap
    -- sx|sy|ox|oy) to use the manual values from config.lua instead.
    local engX = tonumber(Config.RadarEngineScaleX) or 1.0
    local engY = tonumber(Config.RadarEngineScaleY) or 1.0
    local offX, offY = tonumber(offsetX) or 0.0, tonumber(offsetY) or 0.0
    if Config.RadarAutoCalibrate ~= false then
        local t = clamp(16.0 / 9.0 - screen.aspect, 0.0, 0.45)
        engX = 0.765
        engY = 0.97 + 0.731 * t
        offX = -0.15 - 0.1125 * t
        offY = -0.01 + 1.294 * t
    end

    local centerX = reference.cx + clamp(offX, -0.5, 0.5) * wpx / screen.width
    local centerY = reference.cy + clamp(offY, -0.5, 0.5) * hpx / screen.height
    local leftN = centerX - (wpx * 0.5) / screen.width
    local topN = centerY - (hpx * 0.5) / screen.height

    -- GTA minimap X units are fractions of a 16:9 wide area (height * 16/9).
    local scaleX = transform.sy * (16.0 / 9.0) / (screen.width / screen.height)

    return (leftN - transform.x) / scaleX,
        (topN - transform.y) / transform.sy,
        wpx / (screen.width * scaleX * engX),
        hpx / (screen.height * transform.sy * engY)
end

function HudScreen.MinimapRadarRect(zoom, offsetX, offsetY)
    return projectRadarRect(FULL_RECT, zoom, offsetX, offsetY)
end

function HudScreen.MinimapCircleRect(zoom, offsetX, offsetY)
    return projectRadarRect(FULL_RECT, zoom, offsetX, offsetY)
end

function HudScreen.DebugText()
    local screen = HudScreen.Get()
    if not screen then return 'no screen data' end
    local t = screen.transform
    local x, y, w, h = HudScreen.MinimapRadarRect(Config.RadarMaskScale or 1.0, Config.RadarMaskOffsetX or 0.0, Config.RadarMaskOffsetY or 0.0)
    local ref = getRadarReference(screen)
    return ('radar-fix v11 auto | res %dx%d | aspect %.4f (physical %.4f) | safezone %.3f | gfx x=%.4f y=%.4f sx=%.4f sy=%.4f | ring cx=%.4f cy=%.4f diameter=%.1fpx (%s) | component x=%.4f y=%.4f w=%.4f h=%.4f | %s')
        :format(screen.width, screen.height, screen.aspect, screen.physicalAspect, screen.safezone,
            t.x, t.y, t.sx, t.sy, ref.cx, ref.cy, ref.diameter, radarLayoutFromNui and 'from UI' or 'fallback', x, y, w, h, radarNuiInfo)
end

RegisterNUICallback('hudScreenReady', function(_, cb)
    cb({ ok = true, screen = HudScreen.Get() })
end)

RegisterNUICallback('hudRadarLayout', function(data, cb)
    local screen = HudScreen.Get()

    if type(data) ~= 'table' or data.revision ~= screen.revision then
        cb({ ok = false, error = 'Screen changed', screen = screen })
        return
    end

    local cx, cy, diameter = data.cx, data.cy, data.diameter
    if not (isNumber(cx) and isNumber(cy) and isNumber(diameter))
        or cx < 0 or cx > 1 or cy < 0 or cy > 1 or diameter <= 0 or diameter > 1 then
        cb({ ok = false, error = 'Invalid radar bounds' })
        return
    end

    local dx, dy = tonumber(data.dx), tonumber(data.dy)
    radarLayout = { cx = cx, cy = cy, diameter = diameter * screen.height,
        wFrac = (isNumber(dx) and dx > 0 and dx <= 1) and dx or nil,
        hFrac = (isNumber(dy) and dy > 0 and dy <= 1) and dy or nil }
    radarLayoutFromNui = true
    radarNuiInfo = ('nui viewport %sx%s ringRect %sx%s dpr %s'):format(tostring(data.vw), tostring(data.vh), tostring(data.rw), tostring(data.rh), tostring(data.dpr))
    TriggerEvent('codera-hud:applyMinimapLayout')
    cb({ ok = true })
end)

CreateThread(function()
    while true do
        HudScreen.Refresh(false)
        Wait(500)
    end
end)

CreateThread(function()
    Wait(8000)
    print('[codera-hud] ' .. HudScreen.DebugText())
end)
