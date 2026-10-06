CoderaBridge = {}

local function checkResourceRunning(resourceName)
    local state = GetResourceState(resourceName)
    return state == 'started' or state == 'starting'
end

local function detectFramework()
    if CoderaConfig.framework and CoderaConfig.framework ~= 'auto' then
        return CoderaConfig.framework
    end

    if checkResourceRunning('qbx_core') or checkResourceRunning('qb-core') then
        return 'qb'
    end

    if checkResourceRunning('es_extended') then
        return 'esx'
    end

    return 'custom'
end

CoderaBridge.Framework = detectFramework()

function CoderaBridge.ResolvePlayer()
    local ok, player = pcall(function()
        if type(CoderaConfig.playerResolver) == 'function' then return CoderaConfig.playerResolver() end
        if CoderaBridge.Framework == 'qb' then
            local data
            if checkResourceRunning('qbx_core') then
                data = exports['qbx_core']:GetPlayerData()
            else
                data = exports['qb-core']:GetCoreObject().Functions.GetPlayerData()
            end
            if not data or not data.citizenid then return nil end
            return { id = data.citizenid, cash = data.money and data.money.cash, bank = data.money and data.money.bank }
        elseif CoderaBridge.Framework == 'esx' then
            local data = exports['es_extended']:getSharedObject().GetPlayerData()
            if not data or not data.identifier then return nil end
            local cash, bank = data.money, nil
            for _, account in pairs(data.accounts or {}) do
                if account.name == 'money' then cash = account.money end
                if account.name == 'bank' then bank = account.money end
            end
            return { id = data.identifier, cash = cash, bank = bank }
        end
        return { id = 'local' }
    end)
    if ok and type(player) == 'table' and type(player.id) == 'string' and player.id ~= '' then return player end
    return nil
end

local function checkLocalPlayerBag(bagName)
    return bagName == ('player:%s'):format(GetPlayerServerId(PlayerId()))
end

local function qbGetNeeds()
    local playerState = LocalPlayer.state
    return playerState.hunger or 100, playerState.thirst or 100
end

local function qbOnNeedsUpdate(callback)
    AddStateBagChangeHandler('hunger', nil, function(bagName, _, value)
        if not checkLocalPlayerBag(bagName) then return end
        callback(value, nil)
    end)

    AddStateBagChangeHandler('thirst', nil, function(bagName, _, value)
        if not checkLocalPlayerBag(bagName) then return end
        callback(nil, value)
    end)
end

local function esxGetStatus(name)
    local ok, status = pcall(function() return exports['esx_status']:getStatus(name) end)
    if ok and type(status) == 'table' and type(status.percent) == 'number' then
        return status.percent
    end
    return 100
end

local function esxGetNeeds()
    return esxGetStatus('hunger'), esxGetStatus('thirst')
end

local function esxOnNeedsUpdate(callback)
    AddEventHandler('esx_status:onTick', function(statuses)
        local hunger, thirst
        for _, status in ipairs(statuses or {}) do
            if status.name == 'hunger' then
                hunger = status.percent
            elseif status.name == 'thirst' then
                thirst = status.percent
            end
        end
        if hunger ~= nil or thirst ~= nil then
            callback(hunger, thirst)
        end
    end)
end

function CoderaBridge.ReadNeeds()
    if CoderaBridge.Framework == 'qb' then
        return qbGetNeeds()
    end

    if CoderaBridge.Framework == 'esx' then
        return esxGetNeeds()
    end

    return 100, 100
end

function CoderaBridge.WatchNeeds(callback)
    if CoderaBridge.Framework == 'qb' then
        qbOnNeedsUpdate(callback)
    elseif CoderaBridge.Framework == 'esx' then
        esxOnNeedsUpdate(callback)
    end

end
