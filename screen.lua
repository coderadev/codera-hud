
HudScreen = {}
CoderaHud = CoderaHud or {}

local cachedScreen = nil   -- last measured screen table
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

    local scaleX = transform.sx * (screen.width / screen.height) / aspectRatio
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
    local aspectRatio = getAspectRatio(screen)

    local scaleX = transform.sx * (screen.width / screen.height) / aspectRatio
    local diameter = reference.diameter * clamp(tonumber(zoom) or 1.0, 0.5, 2.0)
    local unitX = diameter / rect.width
    local unitY = diameter / rect.height
    local offsetPxX = clamp(tonumber(offsetX) or 0.0, -0.5, 0.5) * diameter / screen.width
    local offsetPxY = clamp(tonumber(offsetY) or 0.0, -0.5, 0.5) * diameter / screen.height

    local cx = reference.cx + offsetPxX - (rect.left * unitX + diameter * 0.5) / screen.width
    local cy = reference.cy + offsetPxY - (rect.top * unitY + diameter * 0.5) / screen.height

    return (cx - transform.x) / scaleX,
        (cy - transform.y) / transform.sy,
        unitX / (screen.width * scaleX),
        unitY / (screen.height * transform.sy)
end

function HudScreen.MinimapRadarRect(zoom, offsetX, offsetY)
    return projectRadarRect(FULL_RECT, zoom, offsetX, offsetY)
end

function HudScreen.MinimapCircleRect(zoom, offsetX, offsetY)
    return projectRadarRect(FULL_RECT, zoom, offsetX, offsetY)
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

    radarLayout = { cx = cx, cy = cy, diameter = diameter * screen.height }
    TriggerEvent('codera-hud:applyMinimapLayout')
    cb({ ok = true })
end)

CreateThread(function()
    while true do
        HudScreen.Refresh(false)
        Wait(500)
    end
end)