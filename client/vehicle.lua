
local cache = nil
local hiddenSent = false
local forceRefresh = false

local function changed(new, old)
    if not old then return true end
    for key, value in pairs(new) do
        if old[key] ~= value then return true end
    end
    return false
end


local function getSeatbeltState()
    local mechanic = Config.MechanicResource
    if mechanic and GetResourceState(mechanic) == 'started' then
        local okBelt, belt = pcall(function() return exports[mechanic]:seatBeltOn() end)
        local okHarness, harness = pcall(function() return exports[mechanic]:HasHarness() end)
        if (okBelt and belt == true) or (okHarness and harness == true) then return true end
    end

    local resource = Config.SeatbeltResources and Config.SeatbeltResources[Config.Framework]

    if resource and GetResourceState(resource) == 'started' then
        local okBelt, belt = pcall(function() return exports[resource]:HasSeatbeltOn() end)
        local okHarness, harness = pcall(function() return exports[resource]:HasHarness() end)
        return (okBelt and belt == true) or (okHarness and harness == true)
    end

    local state = LocalPlayer.state
    return state.seatbelt == true or state.seatBelt == true or state.harness == true or state.hasHarness == true
end

-- jim-mechanic's GetNosLevel(vehicle) export: returns nosLevel (0-100), hasNos (bool).
-- Only used when Config.MechanicResource is set to it.
local function getNosStatus(vehicle)
    local mechanic = Config.MechanicResource
    if not mechanic or GetResourceState(mechanic) ~= 'started' then return false, 0 end

    local ok, nosLevel, hasNos = pcall(function() return exports[mechanic]:GetNosLevel(vehicle) end)
    if not ok or not hasNos then return false, 0 end

    return true, CoderaHud.Clamp(tonumber(nosLevel) or 0, 0, 100)
end

local function getFuel(vehicle)
    local statebagFuel = Entity(vehicle).state.fuel
    if type(statebagFuel) == 'number' then
        return CoderaHud.Clamp(statebagFuel, 0, 100)
    end
    return CoderaHud.Clamp(GetVehicleFuelLevel(vehicle), 0, 100)
end

local function getGear(vehicle)
    local gear = GetVehicleCurrentGear(vehicle)
    if gear and gear > 0 then return tostring(gear) end

    local velocity = GetEntitySpeedVector(vehicle, true)
    if velocity.y < -0.5 then return 'R' end
    return 'N'
end

local function isLocked(vehicle)
    local status = GetVehicleDoorLockStatus(vehicle)
    if status >= 2 then return true end
    return GetVehicleDoorsLockedForPlayer(vehicle, PlayerId()) and true or false
end

-- Model hashes from Config.ElectricVehicles, used as a fallback for addon/custom EVs
-- whose vehicles.meta doesn't set the game's own "isElectric" flag (GetIsVehicleElectric
-- only recognises base-game EVs like the Voltic or Khamelion when that flag is set).
local electricModels = {}
for _, name in ipairs(Config.ElectricVehicles or {}) do
    electricModels[GetHashKey(name)] = true
end

local function isElectricVehicle(vehicle)
    local ok, result = pcall(function() return GetIsVehicleElectric(vehicle) end)
    if ok and result then return true end

    return electricModels[GetEntityModel(vehicle)] == true
end

RegisterNetEvent('seatbelt:client:ToggleSeatbelt', function()
    forceRefresh = true
end)

-- Bottom-of-screen control hint bar: STOP ENGINE / VEHICLE LOCK / HEADLIGHTS / HORN / EXIT.
-- Headlights (H), Horn (E) and Exit (F) already work through GTA's own default vehicle
-- controls, so only the engine toggle and the lock toggle need scripted key handling here.

RegisterCommand('+coderahud_vehtoggleengine', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    SetVehicleEngineOn(vehicle, not GetIsVehicleEngineRunning(vehicle), false, true)
    forceRefresh = true
end, false)
RegisterCommand('-coderahud_vehtoggleengine', function() end, false)
RegisterKeyMapping('+coderahud_vehtoggleengine', 'Vehicle: Stop/Start Engine', 'keyboard', 'DOWN')

RegisterCommand('+coderahud_vehtogglelock', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    SetVehicleDoorsLocked(vehicle, isLocked(vehicle) and 1 or 2)
    forceRefresh = true
end, false)
RegisterCommand('-coderahud_vehtogglelock', function() end, false)
RegisterKeyMapping('+coderahud_vehtogglelock', 'Vehicle: Lock/Unlock', 'keyboard', 'L')

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = CoderaHud.IsVisible() and GetVehiclePedIsIn(ped, false) or 0

        if vehicle ~= 0 then
            hiddenSent = false

            local _, lightsOn, highbeamsOn = GetVehicleLightsState(vehicle)

            local speedMultiplier, speedUnit, maxSpeed = CoderaHud.GetSpeedSettings()
            local hasNos, nosLevel = getNosStatus(vehicle)

            local data = {
                action = 'updateVehicleHud',
                speed = math.floor((GetEntitySpeed(vehicle) * speedMultiplier) + 0.5),
                maxSpeed = maxSpeed,
                speedUnit = speedUnit,
                fuel = math.floor(getFuel(vehicle) + 0.5),
                gear = getGear(vehicle),
                lights = (lightsOn == 1 or highbeamsOn == 1),
                seatbelt = getSeatbeltState(),
                locked = isLocked(vehicle),
                engine = math.floor(math.max(GetVehicleEngineHealth(vehicle), 0)),
                engineOn = GetIsVehicleEngineRunning(vehicle) and true or false,
                controlsEnabled = Config.ShowVehicleControlsBar ~= false,
                electric = isElectricVehicle(vehicle),
                hasNos = hasNos,
                nos = math.floor(nosLevel + 0.5)
            }

            if forceRefresh or changed(data, cache) then
                forceRefresh = false
                cache = data
                SendNUIMessage(data)
            end

            Wait(Config.Intervals.vehicle)
        else
            if not hiddenSent then
                hiddenSent = true
                cache = nil
                SendNUIMessage({ action = 'hideVehicleHud' })
            end

            Wait(Config.Intervals.vehicleIdle)
        end
    end
end)
