local cfg = CoderaConfig.chat or {}
if cfg.enabled == false then return end

local MAX_HARD_LIMIT = 1000
local lastSent = {}

local function allowed(src, name)
    local rule = CoderaCommandAccess and CoderaCommandAccess[name]
    if rule then return rule(src) == true end
    return IsPlayerAceAllowed(src, 'command.' .. name)
end

local function pushCommandList(src)
    local list = {}
    for _, entry in ipairs(GetRegisteredCommands()) do
        local name = entry.name
        local first = name and name:sub(1, 1)
        if name and name ~= '' and first ~= '+' and first ~= '-' and allowed(src, name) then
            list[#list + 1] = { name = '/' .. name }
        end
    end
    TriggerClientEvent('codera-hud:chat:commands', src, list)
end

local function cleanText(raw)
    if type(raw) ~= 'string' then return nil end
    local text = raw:gsub('[%z\001-\031\127]', ''):match('^%s*(.-)%s*$')
    if not text or text == '' then return nil end
    return text
end

local function onCooldown(src)
    local now = GetGameTimer()
    local gap = tonumber(cfg.cooldownMs) or 800
    if lastSent[src] and now - lastSent[src] < gap then return true end
    lastSent[src] = now
    return false
end

RegisterNetEvent('chat:init', function() pushCommandList(source) end)
RegisterNetEvent('codera-hud:chat:commands', function() pushCommandList(source) end)

RegisterNetEvent('codera-hud:chat:send', function(message)
    local src = source
    local text = cleanText(message)
    if not text then return end

    local limit = math.max(1, math.min(MAX_HARD_LIMIT, tonumber(cfg.maxLength) or 300))
    if #text > limit * 4 then return end
    if onCooldown(src) then return end

    TriggerClientEvent('chat:addMessage', -1, {
        color = { 255, 255, 255 },
        multiline = true,
        args = { GetPlayerName(src) or ('Player %d'):format(src), text },
    })
end)

AddEventHandler('playerDropped', function()
    lastSent[source] = nil
end)
