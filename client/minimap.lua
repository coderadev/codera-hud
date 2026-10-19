

local TXD = 'circlemap_codera'                  
local RADAR_MASK_FILE = 'assets/radar-mask.png' 
local RADAR_MASK_NAME = 'round_mask'
local MINIMAP_LOAD_TIMEOUT = 5000
local METERS_PER_MILE = 1609.344

local BLIP_TYPE_WAYPOINT = 8
local MAX_BLIP_SPRITE = 900
local BLIP_DISPLAY_HIDDEN = 3
local BLIP_DISPLAY_NORMAL = 2

local minimapReady = false
local minimapLoading = false
local radarMaskTxd = nil
local radarLocked = false
local radarLayoutGeneration = 0
local screenChangeGeneration = 0
local bigmapRefreshRunning = false

local blipCache, blipCacheTime = {}, 0
local hiddenBlipDisplays = {}   -- blip -> display id to restore

local DEFAULT_MINIMAP_LAYOUT = {
    { name = 'minimap',      alignX = 'L', alignY = 'B', x = 0.0,    y = -0.047, width = 0.14,  height = 0.188 },
    { name = 'minimap_mask', alignX = 'L', alignY = 'B', x = 0.0,    y = 0.0,    width = 0.125, height = 0.19 },
    { name = 'minimap_blur', alignX = 'L', alignY = 'B', x = -0.008, y = -0.008, width = 0.162, height = 0.234 }
}

CreateThread(function()
    SetMapZoomDataLevel(0, 2.75, 0.9, 0.08, 0.0, 0.0)
    SetMapZoomDataLevel(1, 2.8, 0.9, 0.08, 0.0, 0.0)
    SetMapZoomDataLevel(2, 8.0, 0.9, 0.08, 0.0, 0.0)
    SetMapZoomDataLevel(3, 20.0, 0.9, 0.08, 0.0, 0.0)
    SetMapZoomDataLevel(4, 35.0, 0.9, 0.08, 0.0, 0.0)
    SetMapZoomDataLevel(5, 55.0, 0.0, 0.1, 2.0, 1.0)
    SetMapZoomDataLevel(6, 450.0, 0.0, 0.1, 1.0, 1.0)
    SetMapZoomDataLevel(7, 4.5, 0.0, 0.0, 0.0, 0.0)
    SetMapZoomDataLevel(8, 11.0, 0.0, 0.0, 2.0, 3.0)
end)

local function radarWanted()
    return CoderaHud.IsVisible() and CoderaHud.Setting('map', 'showMinimap', true)
end


local function forEachBlip(callback)
    for blipType = 0, MAX_BLIP_SPRITE do
        local blip = GetFirstBlipInfoId(blipType)
        while DoesBlipExist(blip) do
            callback(blip, blipType)
            blip = GetNextBlipInfoId(blipType)
        end
    end
end

local function getAllBlips()
    local now = GetGameTimer()
    if now - blipCacheTime > 500 then
        blipCacheTime = now
        blipCache = {}
        forEachBlip(function(blip) blipCache[#blipCache + 1] = blip end)
    end
    return blipCache
end

local function hideNorthRadarBlip()
    local blip = GetNorthRadarBlip and GetNorthRadarBlip()
    if blip and DoesBlipExist(blip) then
        SetBlipAlpha(blip, 0)
        SetBlipDisplay(blip, 0)
    end
end

local function restoreOneTimeBlipDisplay()
    forEachBlip(function(blip, blipType)
        if blipType ~= BLIP_TYPE_WAYPOINT and GetBlipInfoIdDisplay(blip) == BLIP_DISPLAY_HIDDEN then
            SetBlipDisplay(blip, BLIP_DISPLAY_NORMAL)
        end
    end)
end

local function hideNonWaypointBlips()
    forEachBlip(function(blip, blipType)
        if blipType ~= BLIP_TYPE_WAYPOINT then SetBlipDisplay(blip, BLIP_DISPLAY_HIDDEN) end
    end)
end

local function updateBlipVisibility(coords)
    local range = tonumber(Config.MinimapBlipRange) or 0.0
    if range <= 0.0 then return end
    local rangeSq = range * range

    local function checkBlip(blip)
        if not DoesBlipExist(blip) then return end
        local blipCoords = GetBlipCoords(blip)
        local dx, dy = coords.x - blipCoords.x, coords.y - blipCoords.y
        if dx * dx + dy * dy > rangeSq then
            if not hiddenBlipDisplays[blip] then
                hiddenBlipDisplays[blip] = GetBlipInfoIdDisplay(blip)
                SetBlipDisplay(blip, BLIP_DISPLAY_HIDDEN)
                SetBlipAlpha(blip, 0)
            end
        elseif hiddenBlipDisplays[blip] then
            SetBlipDisplay(blip, hiddenBlipDisplays[blip])
            hiddenBlipDisplays[blip] = nil
            SetBlipAlpha(blip, 255)
        end
    end

    if Config.HideMinimapBlips then
        if Config.ClipWaypointBlip then checkBlip(GetFirstBlipInfoId(BLIP_TYPE_WAYPOINT)) end
        return
    end

    local northBlip = (GetNorthRadarBlip and GetNorthRadarBlip()) or 0
    local waypointBlip = (not Config.ClipWaypointBlip) and GetFirstBlipInfoId(BLIP_TYPE_WAYPOINT) or 0
    for _, blip in ipairs(getAllBlips()) do
        if blip ~= northBlip and blip ~= waypointBlip then checkBlip(blip) end
    end
end

local function pruneHiddenBlips()
    for blip in pairs(hiddenBlipDisplays) do
        if not DoesBlipExist(blip) then hiddenBlipDisplays[blip] = nil end
    end
end

local function restoreAllBlips()
    for blip, display in pairs(hiddenBlipDisplays) do
        if DoesBlipExist(blip) then
            SetBlipDisplay(blip, display)
            SetBlipAlpha(blip, 255)
        end
        hiddenBlipDisplays[blip] = nil
    end
end


local function applyDefaultMinimapLayout()
    SetMinimapClipType(0)
    for _, c in ipairs(DEFAULT_MINIMAP_LAYOUT) do
        SetMinimapComponentPosition(c.name, c.alignX, c.alignY, c.x, c.y, c.width, c.height)
    end
end

local function unlockMinimap()
    if not radarLocked then return end
    UnlockMinimapAngle()
    UnlockMinimapPosition()
    radarLocked = false
end


local function loadRadarMask()
    if not radarMaskTxd and CreateRuntimeTxd and CreateRuntimeTextureFromImage then
        local txdName = GetCurrentResourceName() .. '_radar'
        local txd = CreateRuntimeTxd(txdName)
        local texture = txd and CreateRuntimeTextureFromImage(txd, RADAR_MASK_NAME, RADAR_MASK_FILE)
        if texture and texture ~= 0 then radarMaskTxd = txdName end
    end

    if radarMaskTxd then
        AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', radarMaskTxd, RADAR_MASK_NAME)
        AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', radarMaskTxd, RADAR_MASK_NAME)
        AddReplaceTexture('platform:/textures/graphics', 'radarmasklg', radarMaskTxd, RADAR_MASK_NAME)
        return true
    end

    RequestStreamedTextureDict(TXD, false)
    if HasStreamedTextureDictLoaded(TXD) then
        AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', TXD, 'radarmasksm')
        AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', TXD, 'radarmasksm')
        AddReplaceTexture('platform:/textures/graphics', 'radarmasklg', TXD, 'radarmasklg')
        return true
    end
    return false
end

local function applyRadarLayout()
    SetMinimapClipType(1)

    local maskScale = Config.RadarMaskScale or 1.0
    local offsetX = Config.RadarMaskOffsetX or 0.0
    local offsetY = Config.RadarMaskOffsetY or 0.0

    local x, y, width, height = HudScreen.MinimapRadarRect(maskScale, offsetX, offsetY)
    if Config.RadarClipRoute ~= false then
        local cx, cy, cw, ch = HudScreen.MinimapCircleRect(maskScale, offsetX, offsetY)
        SetMinimapComponentPosition('minimap', 'L', 'T', cx, cy, cw, ch)
    else
        SetMinimapComponentPosition('minimap', 'L', 'T', x, y, width, height)
    end
    SetMinimapComponentPosition('minimap_mask', 'L', 'T', x, y, width, height)
    SetMinimapComponentPosition('minimap_blur', 'L', 'T', x, y, width, height)
end


local function refreshMinimapBigmap()
    if bigmapRefreshRunning or IsPauseMenuActive() then return end
    bigmapRefreshRunning = true
    applyRadarLayout()
    DisplayRadar(false)
    SetRadarBigmapEnabled(true, false)
    Wait(50)
    SetRadarBigmapEnabled(false, false)
    applyRadarLayout()
    DisplayRadar(radarWanted())
    bigmapRefreshRunning = false
end

AddEventHandler('codera-hud:screenChanged', function()
    screenChangeGeneration = screenChangeGeneration + 1
    local generation = screenChangeGeneration
    CreateThread(function()
        while generation == screenChangeGeneration and (IsPauseMenuActive() or not minimapReady) do
            Wait(100)
        end
        if generation ~= screenChangeGeneration then return end
        Wait(350)
        for i = 1, 6 do
            if generation ~= screenChangeGeneration or IsPauseMenuActive() then return end
            if loadRadarMask() then
                applyRadarLayout()
                if i == 1 or i == 6 then refreshMinimapBigmap() end
            end
            Wait(350)
        end
    end)
end)

AddEventHandler('codera-hud:applyMinimapLayout', function()
    if not minimapReady then return end
    applyRadarLayout()
    radarLayoutGeneration = radarLayoutGeneration + 1
    local generation = radarLayoutGeneration
    CreateThread(function()
        Wait(250)
        while generation == radarLayoutGeneration and IsPauseMenuActive() do Wait(100) end
        if generation == radarLayoutGeneration and minimapReady then refreshMinimapBigmap() end
    end)
end)

function CoderaHud.RefreshMinimap()
    TriggerEvent('codera-hud:applyMinimapLayout')
end

local function setupMinimap()
    if minimapReady or minimapLoading then return end
    minimapLoading = true

    local deadline = GetGameTimer() + MINIMAP_LOAD_TIMEOUT
    while not loadRadarMask() do
        if deadline < GetGameTimer() then
            print(('[codera-hud] Timed out loading "%s" and the "%s" texture dict; keeping the default minimap.')
                :format(RADAR_MASK_FILE, TXD))
            minimapLoading = false
            return
        end
        Wait(0)
    end

    applyRadarLayout()
    DisplayRadar(false)
    SetRadarBigmapEnabled(true, false)
    Wait(50)
    SetRadarBigmapEnabled(false, false)
    SetMinimapClipType(1)
    DisplayRadar(radarWanted())

    minimapLoading = false
    minimapReady = true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    restoreAllBlips()
    RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
    RemoveReplaceTexture('platform:/textures/graphics', 'radarmask1g')
    RemoveReplaceTexture('platform:/textures/graphics', 'radarmasklg')
    unlockMinimap()
    if minimapReady then applyDefaultMinimapLayout() end
end)

CreateThread(function()
    local tick = 0
    if not Config.HideMinimapBlips then
        Wait(2000)
        pcall(restoreOneTimeBlipDisplay)
    end
    while true do
        Wait(100)
        tick = tick + 1
        if tick % 5 == 0 then
            pcall(hideNorthRadarBlip)
            if Config.HideMinimapBlips then pcall(hideNonWaypointBlips) end
        end
        pruneHiddenBlips()
        if CoderaHud.IsVisible() then
            if radarWanted() then pcall(updateBlipVisibility, GetEntityCoords(PlayerPedId())) end
        elseif next(hiddenBlipDisplays) then
            restoreAllBlips()
        end
    end
end)

local function getWaypointState()
    if not IsWaypointActive() then return 'off' end
    local blip = GetFirstBlipInfoId(BLIP_TYPE_WAYPOINT)
    if not DoesBlipExist(blip) then return 'missing' end
    local c = GetBlipCoords(blip)
    return ('on:%d:%d'):format(math.floor(c.x + 0.5), math.floor(c.y + 0.5))
end

CreateThread(function()
    local lastState, lastRefresh = 'off', 0
    while true do
        Wait(100)
        if minimapReady then
            local state = getWaypointState()
            if state ~= lastState then
                lastState = state
                Wait(150)
                if minimapReady then
                    refreshMinimapBigmap()
                    for _ = 1, 12 do
                        applyRadarLayout()
                        Wait(50)
                    end
                end
            elseif state ~= 'off' and state ~= 'missing' and GetGameTimer() - lastRefresh > 250 then
                lastRefresh = GetGameTimer()
                applyRadarLayout()
                SetMinimapClipType(1)
            end
        end
    end
end)

local zoom = tonumber(Config.MapZoom) or 130.0

RegisterCommand('mapzoom', function(_, args)
    local value = tonumber(args[1])
    if not value then
        print(('[codera-hud] usage: /mapzoom <number>  (meters, now: %s)'):format(zoom))
        return
    end
    zoom = math.max(10.0, value)
    print(('[codera-hud] map zoom = %s meters'):format(zoom))
end, false)

CreateThread(function()
    local nextLayoutAt = 0
    while true do
        Wait(0)
        if minimapReady and radarWanted() then
            local now = GetGameTimer()
            if nextLayoutAt <= now then
                applyRadarLayout()
                SetMinimapClipType(1)
                nextLayoutAt = now + 500
            end
            local coords = GetEntityCoords(PlayerPedId())
            SetRadarAsExteriorThisFrame()
            SetRadarZoomToDistance(zoom)
            LockMinimapPosition(coords.x, coords.y)
            LockMinimapAngle(math.floor(GetGameplayCamRot(2).z + 0.5) % 360)
            radarLocked = true
        else
            nextLayoutAt = 0
            unlockMinimap()
            if not minimapReady then Wait(200) end
        end
    end
end)


local function waitForPlayerReady()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end
    while GetIsLoadingScreenActive() do Wait(100) end
    while not IsScreenFadedIn() do Wait(100) end
    while not DoesEntityExist(PlayerPedId()) do Wait(100) end
    Wait(1500)
end

local function postSpawnMinimapRefresh()
    if not minimapReady then return end
    for _ = 1, 30 do
        applyRadarLayout()
        Wait(100)
    end
    refreshMinimapBigmap()
end

CreateThread(function()
    waitForPlayerReady()
    while not minimapReady do
        setupMinimap()
        if not minimapReady then Wait(1000) end
    end
    postSpawnMinimapRefresh()
end)

local function onPlayerSpawned()
    CreateThread(function()
        Wait(1500)
        postSpawnMinimapRefresh()
    end)
end

AddEventHandler('playerSpawned', onPlayerSpawned)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', onPlayerSpawned)
AddEventHandler('onClientResourceStart', function(name)
    if name == GetCurrentResourceName() then onPlayerSpawned() end
end)


CreateThread(function()
    local shown = false
    while true do
        Wait(Config.Intervals.minimap)
        local warn = Config.ShowSafezoneWarning
            and CoderaHud.loaded == true
            and not IsPauseMenuActive()
            and GetSafeZoneSize() < Config.RequiredSafezone
        if warn ~= shown then
            shown = warn
            SendNUIMessage({ action = warn and 'showSafezoneWarning' or 'hideSafezoneWarning' })
        end
    end
end)


local function getHeading()
    return (-GetGameplayCamRot(2).z) % 360.0
end

CreateThread(function()
    local last = nil
    local hidden = false

    while true do
        Wait(Config.Intervals.compassHeading)

        if CoderaHud.IsVisible() then
            hidden = false
            local heading = getHeading()

            if not last or math.abs(heading - last) >= 0.05 then
                last = heading
                SendNUIMessage({ action = 'updateCompassHeading', heading = heading })
            end
        elseif not hidden then
            hidden = true
            last = nil
            SendNUIMessage({ action = 'hideCompass' })
        end
    end
end)



local function getWaypointDirection(from, to)
    local bearing = math.deg(math.atan(to.x - from.x, to.y - from.y)) % 360.0
    local relative = ((bearing - getHeading() + 540.0) % 360.0) - 180.0

    if math.abs(relative) <= 45.0 then return 'straight' end
    if relative > 45.0 and relative <= 135.0 then return 'right' end
    if relative < -45.0 and relative >= -135.0 then return 'left' end
    return 'back'
end

CreateThread(function()
    local lastStreet, lastZone, lastWaypoint = nil, nil, nil
    local hidden = false

    while true do
        Wait(Config.Intervals.compassDetails)

        if CoderaHud.IsVisible() then
            hidden = false

            local coords = GetEntityCoords(PlayerPedId())

            -- Street + zone
            local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z)) or ''
            local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
            if zone == 'NULL' then zone = '' end
            street, zone = street:upper(), zone:upper()

            if street ~= lastStreet or zone ~= lastZone then
                lastStreet, lastZone = street, zone
                SendNUIMessage({ action = 'updateCompassDetails', street = street, zone = zone })
            end

            local blip = GetFirstBlipInfoId(8)
            if DoesBlipExist(blip) then
                local wp = GetBlipInfoIdCoord(blip)
                local dx, dy = wp.x - coords.x, wp.y - coords.y
                local distance = ('%.2f mi'):format(math.sqrt((dx * dx) + (dy * dy)) / METERS_PER_MILE)
                local direction = getWaypointDirection(coords, wp)
                local key = distance .. direction

                if key ~= lastWaypoint then
                    lastWaypoint = key
                    SendNUIMessage({ action = 'updateWaypoint', distance = distance, direction = direction })
                end
            elseif lastWaypoint then
                lastWaypoint = nil
                SendNUIMessage({ action = 'hideWaypoint' })
            end
        elseif not hidden then
            hidden = true
            lastStreet, lastZone, lastWaypoint = nil, nil, nil
            SendNUIMessage({ action = 'hideWaypoint' })
        end
    end
end)




RegisterCommand('vhudmap', function(_, args)
    if args and args[1] == 'debug' then
        print('[codera-hud] ' .. HudScreen.DebugText())
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('codera-hud debug printed to F8 console')
        EndTextCommandThefeedPostTicker(false, false)
        return
    end
    local keys = { sx = 'RadarEngineScaleX', sy = 'RadarEngineScaleY', ox = 'RadarMaskOffsetX', oy = 'RadarMaskOffsetY', scale = 'RadarMaskScale' }
    if args and keys[args[1]] and tonumber(args[2]) then
        Config[keys[args[1]]] = tonumber(args[2])
        if args[1] ~= 'scale' then Config.RadarAutoCalibrate = false end
        print(('[codera-hud] %s = %s'):format(keys[args[1]], args[2]))
    end
    if args and args[1] == 'auto' then
        Config.RadarAutoCalibrate = true
        print('[codera-hud] automatic calibration ON')
    end
    if args and args[1] == 'values' then
        print(('[codera-hud] sx=%s sy=%s ox=%s oy=%s scale=%s'):format(Config.RadarEngineScaleX, Config.RadarEngineScaleY, Config.RadarMaskOffsetX, Config.RadarMaskOffsetY, Config.RadarMaskScale))
    end
    CoderaHud.RefreshMinimap()
end, false)
