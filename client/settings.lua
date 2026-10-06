
local KVP_KEY = 'codera_hud:settings'


local Defaults = {
    layout = {
        player  = { x = 0.0, y = 0.0, scale = 1.0 }, -- health, armor, needs, mic
        status  = { x = 0.0, y = 0.0, scale = 1.0 }, -- stamina / oxygen / engine bars
        weapon  = { x = 0.0, y = 0.0, scale = 1.0 }, -- ammo counter
        vehicle = { x = 0.0, y = 0.0, scale = 1.0 }, -- speedometer
        compass = { x = 0.0, y = 0.0, scale = 1.0 }  -- minimap, compass, location, waypoint
    },
    map = {
        showMinimap = true,
        showHeading = true,
        showLocation = true,
        showWaypoint = true
    },
    player = {
        showVoice = true,
        showNeeds = true,
        showArmor = true,
        showStamina = true,
        showAmmo = true,
        crosshair = true
    },
    vehicle = {
        unit = 'auto', -- 'auto' (use config.lua), 'mph' or 'kmh'
        showGear = true,
        showFuel = true,
        showIcons = true
    },
    general = {
        opacity = 100,
        snap = true
    }
}

local LIMITS = {
    x = { -1.0, 1.0 },
    y = { -1.0, 1.0 },
    scale = { 0.4, 2.5 },
    opacity = { 30, 100 }
}

local UNITS = { auto = true, mph = true, kmh = true }


local function deepCopy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, inner in pairs(value) do copy[key] = deepCopy(inner) end
    return copy
end


local function sanitize(input, defaults)
    if type(input) ~= 'table' then input = {} end
    local out = {}

    for key, default in pairs(defaults) do
        local value = input[key]
        local kind = type(default)

        if kind == 'table' then
            out[key] = sanitize(value, default)
        elseif kind == 'boolean' then
            if type(value) == 'boolean' then out[key] = value else out[key] = default end
        elseif kind == 'number' then
            local number = tonumber(value)
            if number == nil or number ~= number then number = default end
            local limit = LIMITS[key]
            if limit then number = CoderaHud.Clamp(number, limit[1], limit[2]) end
            out[key] = number
        elseif kind == 'string' then
            if key == 'unit' and UNITS[value] then out[key] = value else out[key] = default end
        end
    end

    return out
end

local function load()
    local raw = GetResourceKvpString(KVP_KEY)
    if not raw or raw == '' then return deepCopy(Defaults) end

    local ok, data = pcall(json.decode, raw)
    if not ok then return deepCopy(Defaults) end

    return sanitize(data, Defaults)
end

local function save()
    SetResourceKvp(KVP_KEY, json.encode(CoderaHud.Settings))
end

local function notify(text)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

CoderaHud.Settings = load()

function CoderaHud.GetMapLayout()
    return CoderaHud.Settings.layout.compass
end


function CoderaHud.GetSpeedSettings()
    local unit = CoderaHud.Settings.vehicle.unit
    local configIsMph = (tonumber(Config.SpeedMultiplier) or 0) < 3.0
    local maxMph = configIsMph and Config.MaxSpeed or (Config.MaxSpeed / 1.609344)
    local maxKmh = configIsMph and (Config.MaxSpeed * 1.609344) or Config.MaxSpeed

    if unit == 'mph' then
        return 2.236936, 'MPH', math.floor(maxMph + 0.5)
    elseif unit == 'kmh' then
        return 3.6, 'KM/H', math.floor(maxKmh + 0.5)
    end

    return Config.SpeedMultiplier, Config.SpeedUnit, Config.MaxSpeed
end


local isOpen = false

local function zoomState()
    return {
        value = CoderaHud.GetMapZoom and CoderaHud.GetMapZoom() or 0,
        min = Config.MapZoomMin or 300,
        max = Config.MapZoomMax or 1400
    }
end

local function openMenu()
    if isOpen then return end

    if not CoderaHud.loaded then
        notify('The HUD is not ready yet.')
        return
    end

    if IsPauseMenuActive() then return end

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'hudSettingsOpen',
        settings = CoderaHud.Settings,
        zoom = zoomState(),
        brand = Config.SettingsBrand or 'CODERA HUD'
    })


    CreateThread(function()
        local releaseAt = nil
        while true do
            if not isOpen and not releaseAt then releaseAt = GetGameTimer() + 300 end
            if releaseAt and GetGameTimer() > releaseAt then break end

            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            Wait(0)
        end
    end)
end

local function closeMenu()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hudSettingsClose' })
end

local commandName = (Config.Commands and Config.Commands.hudsettings) or 'hudsettings'
RegisterCommand(commandName, openMenu, false)
RegisterNetEvent('hud:client:OpenSettings', openMenu)


RegisterNUICallback('hudsettings_get', function(_, cb)
    cb({ settings = CoderaHud.Settings, zoom = zoomState(), brand = Config.SettingsBrand or 'CODERA HUD' })
end)

RegisterNUICallback('hudsettings_close', function(_, cb)
    closeMenu()
    cb('ok')
end)

RegisterNUICallback('hudsettings_save', function(data, cb)
    local previous = CoderaHud.Settings.layout.compass
    local updated = sanitize(data, Defaults)
    local map = updated.layout.compass

    CoderaHud.Settings = updated
    save()

    if map.x ~= previous.x or map.y ~= previous.y or map.scale ~= previous.scale then
        CoderaHud.RefreshMinimap()
    end

    cb('ok')
end)

RegisterNUICallback('hudsettings_reset', function(data, cb)
    local scope = data and data.scope

    if scope == 'layout' then
        CoderaHud.Settings.layout = deepCopy(Defaults.layout)
        save()
        CoderaHud.RefreshMinimap()
    else
        CoderaHud.Settings = deepCopy(Defaults)
        save()
        ExecuteCommand('vhudmap reset') -- also clears the minimap calibration and re-applies the map
    end

    cb({ settings = CoderaHud.Settings, zoom = zoomState() })
end)

RegisterNUICallback('hudsettings_calibrate', function(_, cb)
    closeMenu()
    cb('ok')
    ExecuteCommand('vhudmap')
end)

RegisterNUICallback('hudsettings_cinematic', function(_, cb)
    closeMenu()
    cb('ok')
    CoderaHud.SetCinematic(not CoderaHud.cinematic)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
end)
