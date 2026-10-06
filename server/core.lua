local cfg = CoderaConfig.stress.commands or {}

CoderaCommandAccess = CoderaCommandAccess or {}

local RESULT_COLOR = {
    ok    = { 120, 255, 120 },
    warn  = { 255, 200, 80 },
    error = { 255, 80, 80 },
}

local function started(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

local function detectCore()
    local forced = CoderaConfig.framework
    if forced and forced ~= 'auto' then return forced end
    if started('qbx_core') or started('qb-core') then return 'qb' end
    if started('es_extended') then return 'esx' end
    return 'custom'
end

local core = detectCore()

local frameworkAdmin = {
    qb = function(src)
        if started('qbx_core') then
            return exports.qbx_core:HasPermission(src, 'admin')
                or exports.qbx_core:HasPermission(src, 'god')
        end
        local qb = exports['qb-core']:GetCoreObject()
        return qb.Functions.HasPermission(src, 'admin') or qb.Functions.HasPermission(src, 'god')
    end,
    esx = function(src)
        local player = exports.es_extended:getSharedObject().GetPlayerFromId(src)
        local group = player and player.getGroup and player.getGroup()
        return group == 'admin' or group == 'superadmin'
    end,
}

local function isFrameworkAdmin(src)
    local check = frameworkAdmin[core]
    if not check then return false end
    local ok, allowed = pcall(check, src)
    return ok and allowed == true
end

local function canUse(src, command)
    if src == 0 then return true end
    if cfg.ace == false then return true end
    if type(cfg.ace) == 'string' and cfg.ace ~= '' then
        return IsPlayerAceAllowed(src, cfg.ace)
    end
    return IsPlayerAceAllowed(src, 'group.admin')
        or IsPlayerAceAllowed(src, 'group.superadmin')
        or IsPlayerAceAllowed(src, 'command.' .. command)
        or isFrameworkAdmin(src)
end

local function reply(src, text, kind)
    local chatOff = CoderaConfig.chat and CoderaConfig.chat.enabled == false
    if src == 0 or chatOff then
        print(('[codera-hud] %s'):format(text))
        return
    end
    TriggerClientEvent('chat:addMessage', src, {
        color = RESULT_COLOR[kind] or { 255, 255, 255 },
        args = { '[HUD]', text },
    })
end

local function resolveTarget(src, raw, allowSelf)
    local id = tonumber(raw)
    if not id then
        if allowSelf and src ~= 0 then return src, GetPlayerName(src) end
        return nil
    end
    local name = GetPlayerName(id)
    if not name then
        reply(src, ('Player %s is not connected.'):format(tostring(raw)), 'error')
        return false
    end
    return id, name
end

local handlers = {}

function handlers.add(src, args, label)
    local amount = tonumber(args[2])
    local target, name = resolveTarget(src, args[1], false)
    if target == false then return end
    if not target or not amount then
        return reply(src, ('Usage: /%s <id> <percent>'):format(label), 'warn')
    end
    TriggerClientEvent('codera-hud:addStress', target, amount)
    reply(src, ('Added %s stress to %s.'):format(amount, name), 'ok')
end

function handlers.remove(src, args, label)
    local target, name = resolveTarget(src, args[1], true)
    if target == false then return end
    if not target then
        return reply(src, ('Usage: /%s <id>'):format(label), 'warn')
    end
    TriggerClientEvent('codera-hud:setStress', target, 0)
    reply(src, ('Cleared stress for %s.'):format(name), 'ok')
end

local function register(kind, label)
    RegisterCommand(label, function(src, args)
        if not canUse(src, label) then
            return reply(src, 'You do not have permission to use this command.', 'error')
        end
        handlers[kind](src, args, label)
    end, false)

    CoderaCommandAccess[label] = function(src)
        return canUse(src, label)
    end
end

if cfg.enabled ~= false then
    register('add', cfg.addName or 'addstress')
    register('remove', cfg.removeName or 'removestress')
end
