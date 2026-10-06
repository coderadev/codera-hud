
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
    local resource = Config.SeatbeltResources and Config.SeatbeltResources[Config.Framework]

    if resource and GetResourceState(resource) == 'started' then
        local okBelt, belt = pcall(function() return exports[resource]:HasSeatbeltOn() end)
        local okHarness, harness = pcall(function() return exports[resource]:HasHarness() end)
        return (okBelt and belt == true) or (okHarness and harness == true)
    end

    local state = LocalPlayer.state
    return state.seatbelt == true or state.seatBelt == true or state.harness == true or state.hasHarness == true
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

RegisterNetEvent('seatbelt:client:ToggleSeatbelt', function()
    forceRefresh = true
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = CoderaHud.IsVisible() and GetVehiclePedIsIn(ped, false) or 0

        if vehicle ~= 0 then
            hiddenSent = false

            local _, lightsOn, highbeamsOn = GetVehicleLightsState(vehicle)

            local speedMultiplier, speedUnit, maxSpeed = CoderaHud.GetSpeedSettings()

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
                engine = math.floor(math.max(GetVehicleEngineHealth(vehicle), 0))
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
