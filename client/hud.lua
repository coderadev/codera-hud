local hudVisible = true
local paused = false
local navigationOverride = true
local speedometerVisible = true
local seatbelt = false
local devMode = false

local lastStatusPayload = ''
local lastVehiclePayload = ''
local lastCompassHeading = -1
local minimapScaleform = nil

local lastVehicle = 0
local engineToggleCooldownUntil = 0
local hornCooldownUntil = 0
local hornHeld = false
local lastGear = nil
local lastGearAnimTime = 0

local hunger, thirst = CoderaBridge.ReadNeeds()

local stress = 0
local lastStressGainTime = 0
local blurActive = false
local fadeActive = false
local electricVehicleCache = nil

local BLIP_TYPE_WAYPOINT = 8
local MAX_BLIP_SPRITE = 900
local BLIP_DISPLAY_HIDDEN = 3
local BLIP_DISPLAY_NORMAL = 2

local blipCache = {}
local blipCacheTime = 0
local hiddenBlipDisplays = {}

local TEXTURE_DICT = 'circlemap'
local RADAR_MASK_FILE = 'html/img/radar-mask.png'
local RADAR_MASK_NAME = 'round_mask'
local MINIMAP_LOAD_TIMEOUT = 5000

local minimapReady = false
local minimapLoading = false
local radarMaskTxd = nil
local radarLocked = false
local radarLayoutGeneration = 0
local screenChangeGeneration = 0
local bigmapRefreshRunning = false

local DEFAULT_MINIMAP_LAYOUT = {
    { name = 'minimap', alignX = 'L', alignY = 'B', x = 0.0, y = -0.047, width = 0.14, height = 0.188 },
    { name = 'minimap_mask', alignX = 'L', alignY = 'B', x = 0.0, y = 0.0, width = 0.125, height = 0.19 },
    { name = 'minimap_blur', alignX = 'L', alignY = 'B', x = -0.008, y = -0.008, width = 0.162, height = 0.234 }
}

local function roundTo(value)
    return math.floor(value + 0.5)
end

local function limit(value, min, max)
    local number = tonumber(value) or 0
    if min > number then
        return min
    end
    if max < number then
        return max
    end
    return number
end

local function limitPercent(value)
    return limit(value, 0, 100)
end

local function readOxygen(ped)
    local remaining = GetPlayerUnderwaterTimeRemaining and GetPlayerUnderwaterTimeRemaining(PlayerId()) or 10.0
    local submerged = IsPedSwimmingUnderWater and IsPedSwimmingUnderWater(ped)
    local visible = submerged or remaining < 9.8
    return limitPercent(remaining / 10.0 * 100.0), visible
end

local function assignStress(value)
    stress = limitPercent(value)
    SendNUIMessage({ action = 'status', stress = stress })
end

local function raiseStress(amount)
    assignStress(stress + (tonumber(amount) or 0))
end

local function lowerStress(amount)
    assignStress(stress - (tonumber(amount) or 0))
end

local function readElectricVehicleModels()
    if electricVehicleCache then
        return electricVehicleCache
    end
    electricVehicleCache = {}
    for _, model in ipairs(CoderaConfig.electricVehicles or {}) do
        local hash = joaat and joaat(model)
        if not hash then
            hash = GetHashKey(model)
        end
        electricVehicleCache[hash] = true
    end
    return electricVehicleCache
end

local function checkElectricVehicle(vehicle)
    if vehicle == 0 then
        return false
    end
    if GetIsVehicleElectric and GetIsVehicleElectric(vehicle) then
        return true
    end
    return readElectricVehicleModels()[GetEntityModel(vehicle)] == true
end

local function readFuelLevel(vehicle)
    if vehicle == 0 then
        return 0.0
    end
    local state = Entity(vehicle).state
    if state and state.fuel ~= nil then
        return limit(state.fuel, 0, 100)
    end
    return limit(GetVehicleFuelLevel(vehicle), 0, 100)
end

local function readGearLabel(vehicle)
    if vehicle == 0 then
        return 'N'
    end
    local speedVector = GetEntitySpeedVector(vehicle, true)
    if speedVector.y < -0.2 then
        return 'R'
    end
    local gear = GetVehicleCurrentGear(vehicle)
    if gear <= 0 then
        return 'N'
    end
    return tostring(gear)
end

local function readStreetNames(coords)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = (streetHash ~= 0 and GetStreetNameFromHashKey(streetHash)) or ''
    local crossing = (crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash)) or ''
    return street, crossing
end

local function readZoneName(coords)
    local name = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    if name == 'NULL' then
        return ''
    end
    return name
end

local function readWaypointInfo(coords)
    if not IsWaypointActive() then
        return false, 0, 'mi', 0, false
    end

    local blip = GetFirstBlipInfoId(BLIP_TYPE_WAYPOINT)
    if not DoesBlipExist(blip) then
        return false, 0, 'mi', 0, false
    end

    local blipCoords = GetBlipCoords(blip)
    local dx = coords.x - blipCoords.x
    local dy = coords.y - blipCoords.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local bearing = math.floor((math.deg(math.atan(-dx, -dy)) + 360.0) % 360.0 * 2 + 0.5) / 2

    local range = tonumber(CoderaConfig.radar.blipRange) or 0.0
    local offRadar = CoderaConfig.radar.edgeWaypoint == true and range > 0.0 and distance > range

    local useMetric = CoderaConfig.general.metricUnits
    if ShouldUseMetricMeasurements then
        useMetric = ShouldUseMetricMeasurements()
    end

    if useMetric then
        return true, roundTo(distance), 'm', bearing, offRadar
    end
    return true, math.floor(distance / 1609.344 * 100 + 0.5) / 100, 'mi', bearing, offRadar
end

local function eachBlip(callback)
    for blipType = 0, MAX_BLIP_SPRITE do
        local blip = GetFirstBlipInfoId(blipType)
        while DoesBlipExist(blip) do
            callback(blip, blipType)
            blip = GetNextBlipInfoId(blipType)
        end
    end
end

local function readAllBlips()
    local now = GetGameTimer()
    if now - blipCacheTime > 500 then
        blipCacheTime = now
        blipCache = {}
        eachBlip(function(blip)
            blipCache[#blipCache + 1] = blip
        end)
    end
    return blipCache
end

local function concealNorthRadarBlip()
    local blip = GetNorthRadarBlip and GetNorthRadarBlip()
    if blip and DoesBlipExist(blip) then
        SetBlipAlpha(blip, 0)
        SetBlipDisplay(blip, 0)
    end
end

local function recoverOneTimeBlipDisplay()
    eachBlip(function(blip, blipType)
        if blipType ~= BLIP_TYPE_WAYPOINT and GetBlipInfoIdDisplay(blip) == BLIP_DISPLAY_HIDDEN then
            SetBlipDisplay(blip, BLIP_DISPLAY_NORMAL)
        end
    end)
end

local function concealNonWaypointBlips()
    eachBlip(function(blip, blipType)
        if blipType ~= BLIP_TYPE_WAYPOINT then
            SetBlipDisplay(blip, BLIP_DISPLAY_HIDDEN)
        end
    end)
end

local function syncBlipVisibility(coords)
    local range = tonumber(CoderaConfig.radar.blipRange) or 0.0
    if range <= 0.0 then
        return
    end
    local rangeSq = range * range

    local function checkBlip(blip)
        if not DoesBlipExist(blip) then
            return
        end
        local blipCoords = GetBlipCoords(blip)
        local dx = coords.x - blipCoords.x
        local dy = coords.y - blipCoords.y
        if dx * dx + dy * dy > rangeSq then
            if not hiddenBlipDisplays[blip] then
                hiddenBlipDisplays[blip] = GetBlipInfoIdDisplay(blip)
                SetBlipDisplay(blip, BLIP_DISPLAY_HIDDEN)
                SetBlipAlpha(blip, 0)
            end
        else
            if hiddenBlipDisplays[blip] then
                SetBlipDisplay(blip, hiddenBlipDisplays[blip])
                hiddenBlipDisplays[blip] = nil
                SetBlipAlpha(blip, 255)
            end
        end
    end

    if CoderaConfig.radar.hideBlips then
        if CoderaConfig.radar.edgeWaypoint then
            checkBlip(GetFirstBlipInfoId(BLIP_TYPE_WAYPOINT))
        end
        return
    end

    local northBlip = (GetNorthRadarBlip and GetNorthRadarBlip()) or 0
    local waypointBlip = (not CoderaConfig.radar.edgeWaypoint) and GetFirstBlipInfoId(BLIP_TYPE_WAYPOINT) or 0
    for _, blip in ipairs(readAllBlips()) do
        if blip ~= northBlip and blip ~= waypointBlip then
            checkBlip(blip)
        end
    end
end

local function dropStaleBlips()
    for blip in pairs(hiddenBlipDisplays) do
        if not DoesBlipExist(blip) then
            hiddenBlipDisplays[blip] = nil
        end
    end
end

local function recoverAllBlips()
    for blip, display in pairs(hiddenBlipDisplays) do
        if DoesBlipExist(blip) then
            SetBlipDisplay(blip, display)
            SetBlipAlpha(blip, 255)
        end
        hiddenBlipDisplays[blip] = nil
    end
end

local function checkHudVisible()
    if not (CoderaPrefs.IsEditing() or (hudVisible and CoderaPrefs.Option('hud', true))) then
        return false
    end
    return not paused
end

local function checkPauseMenuOpen()
    if IsPauseMenuActive() then
        return true
    end
    if type(GetPauseMenuState) == 'function' then
        return GetPauseMenuState() ~= 0
    end
    return false
end

local function wipeScreenEffects(instant)
    if blurActive then
        TriggerScreenblurFadeOut(instant and 0 or 1000.0)
        blurActive = false
    end
    if fadeActive then
        DoScreenFadeIn(instant and 0 or 200)
        fadeActive = false
    end
end

local function assignHudVisible(value)
    CoderaChat.SetVisible(value == true)
    hudVisible = value == true
    SendNUIMessage({ action = 'visible', visible = checkHudVisible() })
end

local function revealNavigation()
    return CoderaConfig.general.showNavigation ~= false and (navigationOverride or CoderaPrefs.IsEditing())
end

local function revealMinimap()
    local value = revealNavigation()
    if value then
        value = CoderaPrefs.IsEditing()
        if not value then
            value = CoderaPrefs.Option('minimap', true)
        end
    end
    return value
end

local function assignPaused(value)
    local state = value == true
    if paused == state then
        return
    end
    paused = state
    if not state then
        CoderaDisplay.Refresh(true)
    end
    lastStatusPayload = ''
    lastCompassHeading = -1
    SendNUIMessage({ action = 'visible', visible = checkHudVisible() })
    DisplayRadar(checkHudVisible() and revealMinimap())
end

local function broadcastSections()
    SendNUIMessage({
        action = 'sections',
        navigation = revealNavigation(),
        speedometer = speedometerVisible
    })
end

local function assignNavigationVisible(value)
    navigationOverride = value == true
    lastCompassHeading = -1
    broadcastSections()
    DisplayRadar(checkHudVisible() and revealMinimap())
end

local function assignSpeedometerVisible(value)
    speedometerVisible = value == true
    lastVehiclePayload = ''
    broadcastSections()
end

local function assignSpeedUnit(useMetric)
    CoderaConfig.general.metricUnits = useMetric == true
    SetResourceKvp('codera-hud:useMetricSpeed', CoderaConfig.general.metricUnits and 'true' or 'false')
    TriggerEvent('codera-hud:preferencesSpeedUnit', CoderaConfig.general.metricUnits)
end

local function fetchSpeedUnit()
    local stored = GetResourceKvpString('codera-hud:useMetricSpeed')
    if stored == 'true' then
        CoderaConfig.general.metricUnits = true
    elseif stored == 'false' then
        CoderaConfig.general.metricUnits = false
    end
end

fetchSpeedUnit()

local function fetchAnimDict(dict)
    if not dict or dict == '' then
        return false
    end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) do
        if deadline < GetGameTimer() then
            return false
        end
        Wait(0)
    end
    return true
end

local function performAnim(config)
    if not config then
        return
    end
    CreateThread(function()
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            return
        end

        local dict = config.dict
        if not fetchAnimDict(dict) then
            return
        end

        local names = config.names
        if not names then
            names = { config.name }
        end
        local blendIn = config.blendIn or 8.0
        local blendOut = config.blendOut or -8.0
        local duration = config.duration or 850
        local flag = config.flag or 48

        for _, name in ipairs(names) do
            if name and name ~= '' then
                TaskPlayAnim(ped, dict, name, blendIn, blendOut, duration, flag, 0.0, false, false, false)
                Wait(60)
                if IsEntityPlayingAnim(ped, dict, name, 3) then
                    SetTimeout(duration, function()
                        if DoesEntityExist(ped) then
                            StopAnimTask(ped, dict, name, 1.0)
                        end
                    end)
                    return
                end
            end
        end
    end)
end

local function performSeatbeltFeedback(buckled)
    local feedback = CoderaConfig.seatbelt or {}

    if feedback.sound ~= false then
        local sound = (buckled and feedback.buckleSound) or feedback.unbuckleSound or {}
        PlaySoundFrontend(-1, sound.name or 'SELECT', sound.set or 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end

    if feedback.animation ~= false then
        local animation = (buckled and feedback.buckle) or feedback.unbuckle
        if animation then
            performAnim({
                dict = animation.dict,
                names = animation.names,
                name = animation.name,
                blendIn = animation.blendIn or feedback.blendIn or 8.0,
                blendOut = animation.blendOut or feedback.blendOut or -8.0,
                duration = animation.duration or feedback.duration or 850,
                flag = animation.flag or feedback.flag or 48
            })
        end
    end
end

local function flipSeatbelt()
    if not IsPedInAnyVehicle(PlayerPedId(), false) then
        return
    end
    seatbelt = not seatbelt
    performSeatbeltFeedback(seatbelt)
    SendNUIMessage({ action = 'status', seatbelt = seatbelt })
end

local function assignVehicleEngineState(vehicle, on)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then
        return
    end
    SetVehicleEngineOn(vehicle, on, true, not on)
    SendNUIMessage({ action = 'status', engine = on })
end

local function commitDefaultMinimapLayout()
    SetMinimapClipType(0)
    for _, component in ipairs(DEFAULT_MINIMAP_LAYOUT) do
        SetMinimapComponentPosition(component.name, component.alignX, component.alignY, component.x, component.y, component.width, component.height)
    end
end

local function unlockMinimap()
    if not radarLocked then
        return
    end
    UnlockMinimapAngle()
    UnlockMinimapPosition()
    radarLocked = false
end

local function fetchRadarMask()
    if not radarMaskTxd then
        if CreateRuntimeTxd and CreateRuntimeTextureFromImage then
            local txdName = GetCurrentResourceName() .. '_radar'
            local txd = CreateRuntimeTxd(txdName)
            local texture = txd and CreateRuntimeTextureFromImage(txd, RADAR_MASK_NAME, RADAR_MASK_FILE)
            if texture and texture ~= 0 then
                radarMaskTxd = txdName
            end
        end
    end

    if radarMaskTxd then
        AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', radarMaskTxd, RADAR_MASK_NAME)
        AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', radarMaskTxd, RADAR_MASK_NAME)
        return true
    end

    RequestStreamedTextureDict(TEXTURE_DICT, false)
    if HasStreamedTextureDictLoaded(TEXTURE_DICT) then
        AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', TEXTURE_DICT, 'radarmasksm')
        AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', TEXTURE_DICT, 'radarmasksm')
        return true
    end
    return false
end

local function commitRadarLayout()
    SetMinimapClipType(1)

    local maskScale = CoderaConfig.radar.maskScale or 1.0
    local offsetX = CoderaConfig.radar.maskOffset.x or 0.0
    local offsetY = CoderaConfig.radar.maskOffset.y or 0.0

    local x, y, width, height = CoderaPrefs.MinimapRadarRect(maskScale, offsetX, offsetY)
    if CoderaConfig.radar.clipRoute ~= false then
        local circleX, circleY, circleWidth, circleHeight = CoderaPrefs.MinimapCircleRect(maskScale, offsetX, offsetY)
        SetMinimapComponentPosition('minimap', 'L', 'T', circleX, circleY, circleWidth, circleHeight)
    else
        SetMinimapComponentPosition('minimap', 'L', 'T', x, y, width, height)
    end
    SetMinimapComponentPosition('minimap_mask', 'L', 'T', x, y, width, height)
    SetMinimapComponentPosition('minimap_blur', 'L', 'T', x, y, width, height)
end

local function resyncBigmap()
    if bigmapRefreshRunning or IsPauseMenuActive() then
        return
    end
    bigmapRefreshRunning = true
    commitRadarLayout()
    DisplayRadar(false)
    SetRadarBigmapEnabled(true, false)
    Wait(50)
    SetRadarBigmapEnabled(false, false)
    commitRadarLayout()
    DisplayRadar(checkHudVisible() and revealMinimap())
    bigmapRefreshRunning = false
end

AddEventHandler('codera-hud:screenChanged', function()
    screenChangeGeneration = screenChangeGeneration + 1
    local generation = screenChangeGeneration
    CreateThread(function()
        while true do
            if generation ~= screenChangeGeneration then
                break
            end
            if not IsPauseMenuActive() and minimapReady then
                break
            end
            Wait(100)
        end
        if generation ~= screenChangeGeneration then
            return
        end
        Wait(350)
        for i = 1, 6 do
            if generation == screenChangeGeneration and not IsPauseMenuActive() then
                if fetchRadarMask() then
                    commitRadarLayout()
                    if i == 1 or i == 6 then
                        resyncBigmap()
                    end
                end
            else
                return
            end
            Wait(350)
        end
    end)
end)

AddEventHandler('codera-hud:applyMinimapLayout', function()
    if not minimapReady then
        return
    end
    commitRadarLayout()
    radarLayoutGeneration = radarLayoutGeneration + 1
    local generation = radarLayoutGeneration
    CreateThread(function()
        Wait(250)
        while true do
            if generation ~= radarLayoutGeneration then
                break
            end
            if not IsPauseMenuActive() then
                break
            end
            Wait(100)
        end
        if generation == radarLayoutGeneration and minimapReady then
            resyncBigmap()
        end
    end)
end)

local function initRadar()
    if minimapReady or minimapLoading then
        return
    end
    minimapLoading = true

    local deadline = GetGameTimer() + MINIMAP_LOAD_TIMEOUT
    while not fetchRadarMask() do
        if deadline < GetGameTimer() then
            print(("[codera-hud] Timed out loading \"%s\" and the \"%s\" texture dict; keeping the default square minimap.")
                :format(RADAR_MASK_FILE, TEXTURE_DICT))
            minimapLoading = false
            return
        end
        Wait(50)
    end

    commitRadarLayout()
    DisplayRadar(false)
    SetRadarBigmapEnabled(true, false)
    Wait(50)
    SetRadarBigmapEnabled(false, false)
    SetMinimapClipType(1)
    DisplayRadar(checkHudVisible() and revealMinimap())

    local scaleform = RequestScaleformMovie('minimap')
    minimapScaleform = scaleform
    local scaleformDeadline = GetGameTimer() + MINIMAP_LOAD_TIMEOUT
    while not HasScaleformMovieLoaded(minimapScaleform) do
        if scaleformDeadline < GetGameTimer() then
            print('[codera-hud] Timed out loading the minimap scaleform; stock health/armour pips may still show on the map.')
            minimapScaleform = nil
            minimapLoading = false
            return
        end
        Wait(0)
    end

    minimapLoading = false
    minimapReady = true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end
    wipeScreenEffects(true)
    recoverAllBlips()
    RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
    RemoveReplaceTexture('platform:/textures/graphics', 'radarmask1g')
    unlockMinimap()
    if minimapScaleform then
        SetScaleformMovieAsNoLongerNeeded(minimapScaleform)
        minimapScaleform = nil
    end
    if minimapReady then
        commitDefaultMinimapLayout()
    end
end)

CreateThread(function()
    local tick = 0
    if not CoderaConfig.radar.hideBlips then
        Wait(2000)
        pcall(recoverOneTimeBlipDisplay)
    end
    while true do
        Wait(100)
        tick = tick + 1
        if tick % 5 == 0 then
            pcall(concealNorthRadarBlip)
            if CoderaConfig.radar.hideBlips then
                pcall(concealNonWaypointBlips)
            end
        end
        dropStaleBlips()
        if checkHudVisible() then
            if revealNavigation() then
                pcall(syncBlipVisibility, GetEntityCoords(PlayerPedId()))
            end
        else
            if next(hiddenBlipDisplays) then
                recoverAllBlips()
            end
        end
    end
end)

local function readWaypointState()
    if not IsWaypointActive() then
        return 'off'
    end
    local blip = GetFirstBlipInfoId(BLIP_TYPE_WAYPOINT)
    if not DoesBlipExist(blip) then
        return 'missing'
    end
    local coords = GetBlipCoords(blip)
    return ('on:%d:%d'):format(math.floor(coords.x + 0.5), math.floor(coords.y + 0.5))
end

CreateThread(function()
    local lastState = 'off'
    local lastRefresh = 0
    while true do
        Wait(100)
        if minimapReady then
            local state = readWaypointState()
            if state ~= lastState then
                lastState = state
                Wait(150)
                if minimapReady then
                    resyncBigmap()
                    for _ = 1, 12 do
                        commitRadarLayout()
                        Wait(50)
                    end
                end
            elseif state ~= 'off' and state ~= 'missing' then
                if GetGameTimer() - lastRefresh > 250 then
                    lastRefresh = GetGameTimer()
                    commitRadarLayout()
                    SetMinimapClipType(1)
                end
            end
        end
    end
end)

CreateThread(function()
    local nextLayoutAt = 0
    while true do
        Wait(0)
        if minimapReady then
            if checkHudVisible() and revealMinimap() and not checkPauseMenuOpen() then
                if CoderaConfig.radar.lockToPlayer ~= false then
                    local coords = GetEntityCoords(PlayerPedId())
                    local now = GetGameTimer()
                    if nextLayoutAt <= now then
                        commitRadarLayout()
                        SetMinimapClipType(1)
                        nextLayoutAt = now + 500
                    end
                    SetRadarAsExteriorThisFrame()
                    if CoderaConfig.radar.zoomDistance then
                        SetRadarZoomToDistance(CoderaConfig.radar.zoomDistance)
                    end
                    LockMinimapPosition(coords.x, coords.y)
                    LockMinimapAngle(math.floor(GetGameplayCamRot(2).z + 0.5) % 360)
                    radarLocked = true
                end
            end
        else
            nextLayoutAt = 0
            unlockMinimap()
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        assignPaused(checkPauseMenuOpen())
    end
end)

local function awaitPlayer()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(100)
    end
    while GetIsLoadingScreenActive() do
        Wait(100)
    end
    while not IsScreenFadedIn() do
        Wait(100)
    end
    while not DoesEntityExist(PlayerPedId()) do
        Wait(100)
    end
    Wait(1500)
end

local function respawnRadarSync()
    if not minimapReady then
        return
    end
    for _ = 1, 30 do
        commitRadarLayout()
        Wait(100)
    end
    resyncBigmap()
end

CreateThread(function()
    awaitPlayer()
    while not minimapReady do
        initRadar()
        if not minimapReady then
            Wait(1000)
        end
    end
    respawnRadarSync()
end)

local function handleSpawn()
    CreateThread(function()
        Wait(1500)
        respawnRadarSync()
    end)
end

AddEventHandler('playerSpawned', handleSpawn)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', handleSpawn)

CreateThread(function()
    while true do
        Wait(CoderaConfig.general.tickRate)

        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        local maxHealth = math.max(1, GetEntityMaxHealth(ped) - 100)
        local health = limit((GetEntityHealth(ped) - 100) / maxHealth * 100, 0, 100)

        local maxArmour = (GetPlayerMaxArmour and GetPlayerMaxArmour(PlayerId())) or 100
        local armour = limit(GetPedArmour(ped) / math.max(1, maxArmour) * 100, 0, 100)

        local oxygen, oxygenVisible = readOxygen(ped)

        local inVehicle = IsPedInAnyVehicle(ped, false)
        local vehicle = inVehicle and GetVehiclePedIsIn(ped, false) or 0

        if vehicle ~= lastVehicle then
            lastVehicle = vehicle
            seatbelt = false
            lastGear = nil
            lastGearAnimTime = 0
            SendNUIMessage({ action = 'status', seatbelt = false })
        end

        local fuel = 0.0
        local electric = false
        local lights = 0
        local locked = false
        local engineOn = false
        if vehicle ~= 0 then
            fuel = readFuelLevel(vehicle)
            electric = checkElectricVehicle(vehicle)

            local _, lightsOn, highBeamsOn = GetVehicleLightsState(vehicle)
            if highBeamsOn == 1 then
                lights = 2
            elseif lightsOn == 1 then
                lights = 1
            else
                lights = 0
            end

            locked = GetVehicleDoorLockStatus(vehicle) > 1
            engineOn = GetIsVehicleEngineRunning(vehicle)
        end

        local talking = CoderaChat.IsTalking()
        local stamina = limit(100 - math.floor(GetPlayerSprintStaminaRemaining(PlayerId())), 0, 100)
        local street, crossing = readStreetNames(coords)
        local zone = readZoneName(coords)
        local waypointActive, waypointDistance, waypointUnit, waypointBearing, waypointOffRadar = readWaypointInfo(coords)

        local payload = {
            action = 'update',
            visible = checkHudVisible(),
            navigation = revealNavigation(),
            speedometer = speedometerVisible,
            navBackdrop = CoderaPrefs.Option('navBackdrop', CoderaConfig.general.navTextBackdrop == true),
            controlsTimeout = CoderaConfig.general.vehicleHintsTimeout or 0,
            health = health,
            armor = armour,
            hunger = limitPercent(hunger),
            thirst = limitPercent(thirst),
            stamina = stamina,
            oxygen = oxygen,
            oxygenVisible = oxygenVisible,
            talking = talking,
            inVehicle = inVehicle,
            seatbelt = seatbelt,
            stress = stress,
            dev = devMode,
            fuel = fuel,
            electric = electric,
            fuelType = electric and 'electric' or 'gasoline',
            speedUnit = CoderaConfig.general.metricUnits and 'KMH' or 'MPH',
            lights = lights,
            locked = locked,
            engine = engineOn,
            zone = zone,
            street = street,
            crossing = crossing,
            waypoint = waypointActive,
            waypointDistance = waypointDistance,
            waypointUnit = waypointUnit,
            waypointBearing = waypointBearing,
            waypointOffRadar = waypointOffRadar
        }

        local encoded = json.encode(payload)
        if encoded ~= lastStatusPayload then
            SendNUIMessage(json.decode(encoded))
            lastStatusPayload = encoded
        end

        DisplayRadar(checkHudVisible() and revealMinimap())
    end
end)

CreateThread(function()
    while true do
        Wait(250)
        local now = GetGameTimer()
        if now - lastStressGainTime >= (CoderaConfig.stress.gain.cooldownMs or 5000) then
            local ped = PlayerPedId()
            if IsPedShooting(ped) then
                raiseStress(CoderaConfig.stress.gain.shooting or 2)
                lastStressGainTime = now
            else
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                    if GetEntitySpeed(vehicle) * 3.6 >= (CoderaConfig.stress.speedThresholdKmh or 140.0) then
                        raiseStress(CoderaConfig.stress.gain.driving or 1)
                        lastStressGainTime = now
                    end
                end
            end
        end
    end
end)

local function locateBand(bands, value)
    if type(bands) ~= 'table' then
        return nil
    end
    for _, band in ipairs(bands) do
        if value >= (band.min or 0) and value <= (band.max or 100) then
            return band
        end
    end
    return nil
end

local function readBlurDuration(config)
    local band = locateBand(config.blurBands, stress)
    return tonumber(band and band.holdMs or stress) or 1500
end

local function readEffectInterval(config)
    local band = locateBand(config.intervalBands, stress)
    if not band then
        return 60000
    end
    local min = tonumber(band.minDelayMs) or 60000
    local max = tonumber(band.maxDelayMs) or min
    if min >= max then
        return min
    end
    return math.random(min, max)
end

local function stressEffectsActive()
    local effects = CoderaConfig.stress.effects or {}
    if effects.enabled == false then
        return false
    end
    if not checkHudVisible() then
        return false
    end
    if checkPauseMenuOpen() or IsNuiFocused() then
        return false
    end
    return not IsEntityDead(PlayerPedId())
end

local function blurPulse(duration)
    TriggerScreenblurFadeIn(1000.0)
    blurActive = true
    Wait(duration)
    TriggerScreenblurFadeOut(1000.0)
    blurActive = false
end

local function executeStressEffects(config)
    if stress < 100 then
        blurPulse(readBlurDuration(config))
        return
    end

    local blurDuration = readBlurDuration(config)
    local cycles = math.random(2, 4)
    local shakeDuration = cycles * 1750
    local fadeOutMs = tonumber(config.blackoutOutMs) or 200
    local fadeInMs = tonumber(config.blackoutInMs) or 200

    blurPulse(blurDuration)

    local ped = PlayerPedId()
    if config.ragdoll ~= false and not IsPedRagdoll(ped) and IsPedOnFoot(ped) and not IsPedSwimming(ped) then
        local forward = GetEntityForwardVector(ped)
        SetPedToRagdollWithFall(ped, shakeDuration, shakeDuration, 1, forward.x, forward.y, forward.z, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    end

    Wait(1000)
    for _ = 1, cycles do
        if not (stressEffectsActive() and stress >= 100) then
            return
        end
        Wait(750)
        DoScreenFadeOut(fadeOutMs)
        fadeActive = true
        Wait(1000)
        DoScreenFadeIn(fadeInMs)
        fadeActive = false
        blurPulse(blurDuration)
    end
end

CreateThread(function()
    while true do
        local effects = CoderaConfig.stress.effects or {}
        local minLevel = tonumber(effects.minLevel) or 50
        if stressEffectsActive() and stress >= minLevel then
            executeStressEffects(effects)
            Wait(readEffectInterval(effects))
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    local wasDead = false
    while true do
        Wait(250)
        local dead = IsEntityDead(PlayerPedId())
        if dead and not wasDead then
            wipeScreenEffects(true)
        end
        wasDead = dead
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if checkHudVisible() and revealNavigation() then
            local heading = GetGameplayCamRot(2).z
            heading = (heading % 360.0 + 360.0) % 360.0
            heading = (360.0 - heading) % 360.0

            local snapped = math.floor(heading * 4 + 0.5) / 4
            if snapped >= 360.0 then
                snapped = 0.0
            end

            local delta
            if lastCompassHeading < 0 then
                delta = 1
            else
                delta = math.abs((snapped - lastCompassHeading + 540.0) % 360.0 - 180.0)
            end

            if delta >= 0.25 then
                SendNUIMessage({ action = 'compass', heading = snapped })
                lastCompassHeading = snapped
            end
        else
            lastCompassHeading = -1
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if checkHudVisible() and vehicle ~= 0 then
            local rpm = math.floor(math.max(0.0, math.min(1.0, GetVehicleCurrentRpm(vehicle))) * 1000 + 0.5) / 1000
            local speed = math.floor(GetEntitySpeed(vehicle) * (CoderaConfig.general.metricUnits and 3.6 or 2.236936) * 10 + 0.5) / 10
            local gear = readGearLabel(vehicle)
            local electric = checkElectricVehicle(vehicle)

            local gearAnim = CoderaConfig.animations.gearShift or {}
            if gearAnim.enabled ~= false and GetPedInVehicleSeat(vehicle, -1) == ped then
                if lastGear ~= nil and gear ~= lastGear then
                    local now = GetGameTimer()
                    if (gearAnim.minSpeed or 1.0) <= GetEntitySpeed(vehicle)
                        and now - lastGearAnimTime >= (gearAnim.cooldown or 450) then
                        performAnim({
                            dict = gearAnim.dict,
                            names = gearAnim.names,
                            name = gearAnim.name,
                            blendIn = gearAnim.blendIn or 8.0,
                            blendOut = gearAnim.blendOut or -8.0,
                            duration = gearAnim.duration or 650,
                            flag = gearAnim.flag or 48
                        })
                        lastGearAnimTime = now
                    end
                end
                lastGear = gear
            end

            local signature = ('%.3f|%.1f|%s|%s'):format(rpm, speed, gear, electric and '1' or '0')
            if signature ~= lastVehiclePayload then
                SendNUIMessage({
                    action = 'vehicle',
                    inVehicle = true,
                    rpm = rpm,
                    speed = speed,
                    gear = gear,
                    electric = electric,
                    fuelType = electric and 'electric' or 'gasoline',
                    speedUnit = CoderaConfig.general.metricUnits and 'KMH' or 'MPH'
                })
                lastVehiclePayload = signature
            end
        else
            if lastVehiclePayload ~= '' then
                SendNUIMessage({
                    action = 'vehicle',
                    inVehicle = false,
                    rpm = 0.0,
                    speed = 0,
                    gear = 'N',
                    electric = false,
                    fuelType = 'gasoline',
                    speedUnit = CoderaConfig.general.metricUnits and 'KMH' or 'MPH'
                })
                lastVehiclePayload = ''
                lastGear = nil
            end
        end
    end
end)

local ENGINE_TOGGLE_CONTROL = 14
local HORN_CONTROL = 86

CreateThread(function()
    while true do
        local wait = 250
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if not CoderaPrefs.IsOpen() and checkHudVisible() and vehicle ~= 0
            and GetPedInVehicleSeat(vehicle, -1) == ped then
            wait = 0

            if IsControlJustReleased(0, ENGINE_TOGGLE_CONTROL) then
                local now = GetGameTimer()
                if now > engineToggleCooldownUntil then
                    assignVehicleEngineState(vehicle, not GetIsVehicleEngineRunning(vehicle))
                    engineToggleCooldownUntil = now + 450
                end
            end

            local hornAnim = CoderaConfig.animations.horn or {}
            local hornActive = (IsHornActive and IsHornActive(vehicle))
                or IsControlPressed(0, HORN_CONTROL)
                or IsDisabledControlPressed(0, HORN_CONTROL)

            if hornAnim.enabled ~= false and hornActive then
                if not hornHeld then
                    local now = GetGameTimer()
                    if now > hornCooldownUntil then
                        performAnim({
                            dict = hornAnim.dict,
                            names = hornAnim.names,
                            name = hornAnim.name,
                            blendIn = hornAnim.blendIn or 8.0,
                            blendOut = hornAnim.blendOut or -8.0,
                            duration = hornAnim.duration or 1000,
                            flag = hornAnim.flag or 49
                        })
                        hornCooldownUntil = now + (hornAnim.cooldown or 900)
                    end
                end
            end
            hornHeld = hornActive
        else
            hornHeld = false
        end

        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if minimapScaleform then
            BeginScaleformMovieMethod(minimapScaleform, 'SETUP_HEALTH_ARMOUR')
            ScaleformMovieMethodAddParamInt(3)
            EndScaleformMovieMethod()
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if CoderaConfig.general.hideNativeHud then
            HideHudComponentThisFrame(6)
            HideHudComponentThisFrame(7)
            HideHudComponentThisFrame(8)
            HideHudComponentThisFrame(9)
        end
        if checkHudVisible() and CoderaConfig.general.showNativeAmmo then
            DisplayHud(true)
            DisplayAmmoThisFrame(true)
            ShowHudComponentThisFrame(2)
            ShowHudComponentThisFrame(20)
            ShowHudComponentThisFrame(22)
        end
    end
end)

RegisterCommand('seatbelt', flipSeatbelt, false)
RegisterKeyMapping('seatbelt', 'Toggle seatbelt', 'keyboard', 'B')

local function commitNeeds(hungerValue, thirstValue)
    if hungerValue ~= nil then
        hunger = limitPercent(hungerValue)
    end
    if thirstValue ~= nil then
        thirst = limitPercent(thirstValue)
    end
end

RegisterNetEvent('hud:client:UpdateNeeds', commitNeeds)
CoderaBridge.WatchNeeds(commitNeeds)

RegisterCommand('coderahud', function()
    hudVisible = not hudVisible
    assignHudVisible(hudVisible)
end, false)

RegisterCommand('huddev', function()
    devMode = not devMode
    SendNUIMessage({ action = 'status', dev = devMode })
end, false)

RegisterCommand('speedunit', function(_, args)
    local unit = args[1]
    if unit then
        unit = string.lower(unit)
    end
    if unit == 'kmh' then
        assignSpeedUnit(true)
    elseif unit == 'mph' then
        assignSpeedUnit(false)
    else
        assignSpeedUnit(not CoderaConfig.general.metricUnits)
    end
end, false)
RegisterKeyMapping('speedunit', 'Toggle speed unit (MPH/KMH)', 'keyboard', '')

RegisterNetEvent('codera-hud:setVisible', assignHudVisible)
RegisterNetEvent('codera-hud:setNavigationVisible', assignNavigationVisible)
RegisterNetEvent('codera-hud:setSpeedometerVisible', assignSpeedometerVisible)

RegisterNetEvent('codera-hud:updateStatus', function(status)
    if status.stress ~= nil then
        stress = limitPercent(status.stress)
    end
    status.action = 'status'
    SendNUIMessage(status)
end)

RegisterNetEvent('codera-hud:setStress', assignStress)
RegisterNetEvent('codera-hud:addStress', raiseStress)

if CoderaConfig.stress.revive.clear ~= false then
    local registered = {}
    for _, eventName in ipairs(CoderaConfig.stress.revive.events or {}) do
        if type(eventName) == 'string' and eventName ~= '' and not registered[eventName] then
            registered[eventName] = true
            pcall(RegisterNetEvent, eventName)
            AddEventHandler(eventName, function()
                assignStress(0)
            end)
        end
    end
end

exports('SetVisible', assignHudVisible)
exports('showHUD', function()
    assignHudVisible(true)
end)
exports('hideHUD', function()
    assignHudVisible(false)
end)
exports('SetStatus', function(status)
    TriggerEvent('codera-hud:updateStatus', status)
end)
exports('SetSpeedUnit', assignSpeedUnit)
exports('SetStress', assignStress)
exports('AddStress', raiseStress)
exports('DecreaseStress', lowerStress)
exports('RemoveStress', lowerStress)
exports('GetStress', function()
    return stress
end)
exports('ResetStress', function()
    assignStress(0)
end)
exports('SetNavigationVisible', assignNavigationVisible)
exports('showCompass', function()
    assignNavigationVisible(true)
end)
exports('hideCompass', function()
    assignNavigationVisible(false)
end)
exports('SetSpeedometerVisible', assignSpeedometerVisible)
exports('showSpeedometer', function()
    assignSpeedometerVisible(true)
end)
exports('hideSpeedometer', function()
    assignSpeedometerVisible(false)
end)
