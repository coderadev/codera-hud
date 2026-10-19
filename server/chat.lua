
if Config.Chat and Config.Chat.enabled == false then return end

local maxLength = (Config.Chat and Config.Chat.maxLength) or 120
local registeredSuggestions = {} -- [lowername] = { name = '...', help = '...', params = {...} }

RegisterServerEvent('codera-hud:chat:send')
AddEventHandler('codera-hud:chat:send', function(message)
    local src = source

    if type(message) ~= 'string' then return end
    message = message:gsub('^%s+', ''):gsub('%s+$', '')
    if message == '' then return end
    if #message > maxLength then message = message:sub(1, maxLength) end

    local author = GetPlayerName(src) or ('Player ' .. tostring(src))

    TriggerEvent('chatMessage', src, author, message)
    if WasEventCanceled() then return end

    TriggerClientEvent('codera-hud:chat:addMessage', -1, { author = author, message = message })
end)


RegisterServerEvent('codera-hud:chat:getCommands')
AddEventHandler('codera-hud:chat:getCommands', function()
    local src = source
    local names = {}
    for _, cmd in ipairs(GetRegisteredCommands()) do
        names[string.lower(cmd.name)] = true
    end
    TriggerClientEvent('codera-hud:chat:commandsList', src, names)

    for _, data in pairs(registeredSuggestions) do
        TriggerClientEvent('chat:addSuggestion', src, '/' .. data.name, data.help, data.params)
    end
end)

-- Community-standard `chat:addSuggestion` / `chat:removeSuggestion` exports, server side.
-- Stored so any player who (re)joins later still receives them.
local function addSuggestion(name, help, params)
    if type(name) ~= 'string' then return end
    name = name:gsub('^/', '')
    if name == '' then return end
    registeredSuggestions[string.lower(name)] = { name = name, help = help or '', params = params or {} }
    TriggerClientEvent('chat:addSuggestion', -1, '/' .. name, help, params)
end

local function removeSuggestion(name)
    if type(name) ~= 'string' then return end
    name = name:gsub('^/', '')
    if name == '' then return end
    registeredSuggestions[string.lower(name)] = nil
    TriggerClientEvent('chat:removeSuggestion', -1, '/' .. name)
end

exports('addSuggestion', addSuggestion)
exports('removeSuggestion', removeSuggestion)

addSuggestion('me', 'Perform a roleplay action', { { name = 'action', help = 'The action to describe' } })
addSuggestion('ooc', 'Send an out-of-character message', { { name = 'message', help = 'The message to send' } })

local function trimmedArgs(args)
    return (table.concat(args, ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

RegisterCommand('me', function(source, args)
    local src = source
    if src == 0 then return end -- no console equivalent for an in-game action

    local message = trimmedArgs(args)
    if message == '' then return end
    if #message > maxLength then message = message:sub(1, maxLength) end

    local author = GetPlayerName(src) or ('Player ' .. tostring(src))
    local text = ('%s %s'):format(author, message)

    TriggerClientEvent('codera-hud:chat:addMessage', -1, { message = text, type = 'me' })
end, false)

RegisterCommand('ooc', function(source, args)
    local src = source
    if src == 0 then return end

    local message = trimmedArgs(args)
    if message == '' then return end
    if #message > maxLength then message = message:sub(1, maxLength) end

    local author = GetPlayerName(src) or ('Player ' .. tostring(src))

    TriggerClientEvent('codera-hud:chat:addMessage', -1, {
        author = '(( OOC ))',
        message = ('%s: %s'):format(author, message),
        type = 'ooc'
    })
end, false)
