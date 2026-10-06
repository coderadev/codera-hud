CoderaPrefs = {}

local settings = { version = 1, options = {}, layout = {} }
local profileId = nil
local settingsKey = nil
local isOpen = false
local isEditing = false
local nuiReady = false
local lastActivity = 0
local defaultOptions = nil
local lastMoneyPayload = nil

local SCALE_BOUNDS = {
    minimap = { 0.75, 1.35 },
    playerStatus = { 0.5, 1.75 },
    stamina = { 0.5, 1.75 },
    speedometer = { 0.5, 1.75 },
    location = { 0.5, 1.75 },
    money = { 0.5, 1.75 },
    vehicleControls = { 0.5, 1.75 }
}

local function readDefaults()
    if not defaultOptions then
        defaultOptions = {
            hud = true,
            playerStatus = true,
            stamina = true,
            speedometer = true,
            minimap = true,
            compass = true,
            heading = true,
            location = true,
            money = false,
            waypoint = true,
            vehicleControls = true,
            navBackdrop = CoderaConfig.general.navTextBackdrop == true,
            snap = (CoderaConfig.menu or {}).gridSnap == true,
            safeArea = 0,
            speedUnit = CoderaConfig.general.metricUnits and 'KMH' or 'MPH'
        }
    end
    return defaultOptions
end

local function clampNumber(value, min, max)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return math.max(min, math.min(max, value))
end

local function normalize(raw)
    if type(raw) ~= 'table' or not raw then
        raw = {}
    end

    local out = { version = 1, options = {}, layout = {} }
    local optionsIn = (type(raw.options) == 'table' and raw.options) or {}

    for key, default in pairs(readDefaults()) do
        if type(default) == 'boolean' then
            local value = optionsIn[key]
            out.options[key] = (type(value) == 'boolean') and value or default
        end
    end

    local speedUnit = optionsIn.speedUnit
    if speedUnit ~= 'MPH' and speedUnit ~= 'KMH' then
        speedUnit = readDefaults().speedUnit
    end
    out.options.speedUnit = speedUnit

    out.options.safeArea = clampNumber(optionsIn.safeArea, 0, 10) or 0

    if type(raw.layout) == 'table' then
        for element, bounds in pairs(SCALE_BOUNDS) do
            local entry = raw.layout[element]
            if type(entry) == 'table' then
                local x = clampNumber(entry.x, 0, 1)
                local y = clampNumber(entry.y, 0, 1)
                local scale = clampNumber(entry.scale, bounds[1], bounds[2])
                if x and y and scale then
                    out.layout[element] = { x = x, y = y, scale = scale }
                end
            end
        end
    end

    return out
end

function CoderaPrefs.Option(key, default)
    local value = settings.options[key]
    if value == nil then
        return default
    end
    return value
end

function CoderaPrefs.IsEditing()
    return isEditing
end

function CoderaPrefs.IsOpen()
    return isOpen
end

local function commitSpeedUnit()
    CoderaConfig.general.metricUnits = settings.options.speedUnit == 'KMH'
end

local function composeSettingsPayload()
    return {
        ok = true,
        action = 'prefsLoad',
        profile = profileId,
        settings = settings,
        defaults = readDefaults()
    }
end

local function dismiss()
    isEditing = false
    isOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'prefsHide' })
end

CoderaPrefs.Close = dismiss

local function fetchProfile()
    local player = CoderaBridge.ResolvePlayer()
    local characterId = player and player.id and player.id:sub(1, 128) or nil

    if characterId ~= profileId then
        if isOpen then
            dismiss()
        end

        profileId = characterId
        local key
        if profileId then
            key = ('codera-hud:settings:%s:%s'):format(GetCurrentServerEndpoint() or 'local', profileId)
        end
        settingsKey = key

        local encoded = settingsKey and GetResourceKvpString(settingsKey)
        local ok, decoded = false, nil
        if encoded and #encoded <= 16000 then
            ok, decoded = pcall(json.decode, encoded)
        end

        settings = normalize((ok and decoded) or {})
        commitSpeedUnit()
        TriggerEvent('codera-hud:applyMinimapLayout')

        if nuiReady then
            SendNUIMessage(composeSettingsPayload())
        end
    end

    return player
end

local function profileReady()
    return profileId ~= nil and CoderaBridge.ResolvePlayer() ~= nil
end

RegisterNUICallback('prefsReady', function(_, cb)
    if isOpen then
        dismiss()
    end
    nuiReady = true
    lastMoneyPayload = nil
    fetchProfile()
    cb(composeSettingsPayload())
end)

RegisterNUICallback('prefsSave', function(data, cb)
    if not profileReady() then
        cb({ ok = false, error = 'Character changed; reopen HUD settings.' })
        return
    end

    settings = normalize(data.settings)
    commitSpeedUnit()
    SetResourceKvp(settingsKey, json.encode(settings))
    cb({ ok = true })
end)

RegisterNUICallback('prefsPreview', function(data, cb)
    if not profileReady() then
        cb({ ok = false, error = 'Character is not ready.' })
        return
    end

    settings.options = normalize({ options = data.options }).options
    commitSpeedUnit()
    cb({ ok = true })
end)

CoderaPrefs.MinimapRect = CoderaDisplay.MinimapRect
CoderaPrefs.MinimapRadarRect = CoderaDisplay.MinimapRadarRect
CoderaPrefs.MinimapCircleRect = CoderaDisplay.MinimapCircleRect

RegisterNUICallback('prefsEditorMode', function(data, cb)
    isEditing = isOpen and type(data) == 'table'
    cb({ ok = true })
end)

RegisterNUICallback('prefsClose', function(_, cb)
    dismiss()
    cb({ ok = true })
end)

RegisterNUICallback('prefsHeartbeat', function(_, cb)
    lastActivity = GetGameTimer()
    cb({ ok = true })
end)

local function launch()
    if not (nuiReady and profileId and not IsPauseMenuActive()) then
        return
    end
    if isOpen then
        dismiss()
        return
    end
    if CoderaChat then
        CoderaChat.Close()
    end

    isOpen = true
    lastActivity = GetGameTimer()
    SendNUIMessage(composeSettingsPayload())
    SendNUIMessage({ action = 'prefsShow' })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
end

local menuConfig = CoderaConfig.menu or {}
RegisterCommand(menuConfig.openCommand or 'hudmenu', launch, false)
RegisterKeyMapping(menuConfig.openCommand or 'hudmenu', 'HUD settings and layout', 'keyboard', menuConfig.openKey or 'F7')

RegisterNetEvent('codera-hud:openSettings', launch)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', dismiss)
RegisterNetEvent('esx:onPlayerLogout', dismiss)

exports('OpenSettings', launch)

AddEventHandler('codera-hud:preferencesSpeedUnit', function(useMetric)
    settings.options.speedUnit = useMetric and 'KMH' or 'MPH'
    if settingsKey then
        SetResourceKvp(settingsKey, json.encode(settings))
    end
    SendNUIMessage({ action = 'prefsSpeedUnit', speedUnit = settings.options.speedUnit })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        dismiss()
    end
end)

CreateThread(function()
    while true do
        if isOpen then
            DisableAllControlActions(0)
            DisableAllControlActions(1)
            DisableAllControlActions(2)
            if not IsPauseMenuActive() and GetGameTimer() - lastActivity > 15000 then
                dismiss()
            end
            Wait(0)
        else
            Wait(200)
        end
    end
end)

CreateThread(function()
    while true do
        local player = fetchProfile()
        local payload = {
            action = 'hudMoney',
            available = player ~= nil,
            cash = player and clampNumber(player.cash, 0, 1e15) or 0,
            bank = player and clampNumber(player.bank, 0, 1e15) or 0
        }
        local encoded = json.encode(payload)
        if nuiReady and encoded ~= lastMoneyPayload then
            lastMoneyPayload = encoded
            SendNUIMessage(payload)
        end
        Wait(1000)
    end
end)
