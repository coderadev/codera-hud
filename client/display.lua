CoderaDisplay = {}

local cachedScreen = nil
local radarLayout = nil
local revision = 0

local RADAR_REFERENCE = { cx = 0.5, cy = 0.5, width = 1.0, height = 1.0 }

local FULL_RECT = { left = 0, top = 0, width = 1, height = 1 }

local function limit(value, min, max)
    return math.max(min, math.min(max, value))
end

local function checkNumber(value)
    return type(value) == 'number' and value == value
end

local function measureGfx(alignX, alignY)
    SetScriptGfxAlign(string.byte(alignX), string.byte(alignY))
    SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)
    local x, y = GetScriptGfxPosition(0.0, 0.0)
    local x2, y2 = GetScriptGfxPosition(1.0, 1.0)
    ResetScriptGfxAlign()
    return { x = x, y = y, sx = x2 - x, sy = y2 - y }
end

local function readAspectRatio(screen)
    if checkNumber(screen.aspect) and screen.aspect > 0 then
        return screen.aspect
    end
    return screen.width / screen.height
end

local function readRadarReference(screen)
    if radarLayout then
        return radarLayout
    end
    local scale = limit(math.min(screen.width / 1920, screen.height / 1080), 0.7, 1.35)
    local square = math.min(screen.width, screen.height * 16 / 9)
    local leftEdge = math.max(
        (screen.width - square) / 2 + square * (1 - screen.safezone) / 2,
        screen.safe.right * screen.width
    )
    radarLayout = {
        cx = (screen.width - leftEdge - 147.5 * scale) / screen.width,
        cy = screen.safe.top + (163.5 * scale) / screen.height,
        diameter = 175 * scale
    }
    return radarLayout
end

function CoderaDisplay.Get()
    if cachedScreen then
        return cachedScreen
    end
    CoderaDisplay.Refresh(true)
    return cachedScreen
end

function CoderaDisplay.Refresh(force)
    local width, height = GetActiveScreenResolution()
    if width < 1 or height < 1 then
        return
    end

    local aspect = GetAspectRatio(false)
    local physicalAspect = GetAspectRatio(true)
    local safezone = GetSafeZoneSize()
    local transform = measureGfx('L', 'T')

    if not (checkNumber(transform.sx) and checkNumber(transform.sy)
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
    local inset = (1 - limit(safezone, 0.0, 1.0)) * 0.5
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

    SendNUIMessage({ action = 'displayUpdate', screen = cachedScreen })
    TriggerEvent('codera-hud:applyMinimapLayout')
    TriggerEvent('codera-hud:screenChanged')
end

function CoderaDisplay.MinimapRect(x, y, width, height)
    local screen = CoderaDisplay.Get()
    if not screen then
        return x, y, width, height
    end

    local reference = readRadarReference(screen)
    local transform = screen.transform
    local aspectRatio = readAspectRatio(screen)

    local scaleX = transform.sx * (screen.width / screen.height) / aspectRatio
    local diameter = reference.diameter * 0.9771428571428571
    local unitX = diameter / (screen.width * scaleX * RADAR_REFERENCE.width)
    local unitY = diameter / (screen.height * transform.sy * RADAR_REFERENCE.height)

    local cx = (reference.cx - transform.x) / scaleX + (x - RADAR_REFERENCE.cx) * unitX
    local cy = (reference.cy - transform.y) / transform.sy + (y - RADAR_REFERENCE.cy) * unitY
    return cx, cy, width * unitX, height * unitY
end

local function projectRadar(rect, zoom, offsetX, offsetY)
    local screen = CoderaDisplay.Get()
    if not screen then
        return 0.0, 0.0, 0.0, 0.0
    end

    local reference = readRadarReference(screen)
    local transform = screen.transform
    local aspectRatio = readAspectRatio(screen)

    local scaleX = transform.sx * (screen.width / screen.height) / aspectRatio
    local diameter = reference.diameter * limit(tonumber(zoom) or 1.0, 0.5, 2.0)
    local unitX = diameter / rect.width
    local unitY = diameter / rect.height
    local offsetPxX = limit(tonumber(offsetX) or 0.0, -0.5, 0.5) * diameter / screen.width
    local offsetPxY = limit(tonumber(offsetY) or 0.0, -0.5, 0.5) * diameter / screen.height

    local cx = reference.cx + offsetPxX - (rect.left * unitX + diameter * 0.5) / screen.width
    local cy = reference.cy + offsetPxY - (rect.top * unitY + diameter * 0.5) / screen.height

    return (cx - transform.x) / scaleX,
        (cy - transform.y) / transform.sy,
        unitX / (screen.width * scaleX),
        unitY / (screen.height * transform.sy)
end

function CoderaDisplay.MinimapRadarRect(zoom, offsetX, offsetY)
    return projectRadar(FULL_RECT, zoom, offsetX, offsetY)
end

function CoderaDisplay.MinimapCircleRect(zoom, offsetX, offsetY)
    return projectRadar(FULL_RECT, zoom, offsetX, offsetY)
end

RegisterNUICallback('displayReady', function(_, cb)
    cb({ ok = true, screen = CoderaDisplay.Get() })
end)

RegisterNUICallback('displayRadarLayout', function(data, cb)
    local screen = CoderaDisplay.Get()

    if type(data) ~= 'table' or data.revision ~= screen.revision then
        cb({ ok = false, error = 'Screen changed', screen = screen })
        return
    end

    local cx, cy, diameter = data.cx, data.cy, data.diameter
    if not (checkNumber(cx) and checkNumber(cy) and checkNumber(diameter))
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
        CoderaDisplay.Refresh(false)
        Wait(500)
    end
end)
