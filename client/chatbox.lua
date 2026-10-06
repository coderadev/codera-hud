CoderaChat = {}

local chatConfig = CoderaConfig.chat or {}

if chatConfig.enabled == false then
    function CoderaChat.IsTalking()
        local playerId = PlayerId()
        if NetworkIsPlayerTalking(playerId) then
            return true
        end
        if type(MumbleIsPlayerTalking) == 'function' then
            return MumbleIsPlayerTalking(playerId)
        end
        return false
    end

    function CoderaChat.Close() end

    function CoderaChat.SetVisible(_) end

    return
end

local isOpen = false
local nuiReady = false
local visible = true
local lastActivity = 0
local pendingMessages = {}

SetTextChatEnabled(false)

local function dispatch(payload)
    if nuiReady then
        SendNUIMessage(payload)
    else
        pendingMessages[#pendingMessages + 1] = payload
        if #pendingMessages > 200 then
            table.remove(pendingMessages, 1)
        end
    end
end

local function enqueueMessage(message)
    if type(message) == 'string' then
        message = { args = { message } }
    end
    if type(message) == 'table' then
        dispatch({ action = 'chatMessage', message = message })
    end
end

function CoderaChat.IsTalking()
    local playerId = PlayerId()
    if NetworkIsPlayerTalking(playerId) then
        return true
    end
    if type(MumbleIsPlayerTalking) == 'function' then
        return MumbleIsPlayerTalking(playerId)
    end
    return false
end

function CoderaChat.Close()
    if not isOpen then
        return
    end
    isOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'chatClose' })
end

function CoderaChat.SetVisible(value)
    visible = value
    if not value then
        CoderaChat.Close()
    end
end

exports('addMessage', enqueueMessage)
RegisterNetEvent('chat:addMessage', enqueueMessage)

RegisterNetEvent('chatMessage', function(author, color, message)
    enqueueMessage({
        args = (author and author ~= '') and { author, message } or { message },
        color = color
    })
end)

RegisterNetEvent('__cfx_internal:serverPrint', function(message)
    enqueueMessage({ args = { message } })
end)

local function raiseSuggestion(name, help, params)
    if type(name) ~= 'string' then
        return
    end
    dispatch({
        action = 'chatSuggestion',
        suggestion = { name = name, help = help or '', params = params or {} }
    })
end

exports('addSuggestion', raiseSuggestion)
RegisterNetEvent('chat:addSuggestion', raiseSuggestion)

RegisterNetEvent('chat:addSuggestions', function(suggestions)
    if type(suggestions) ~= 'table' then
        return
    end
    for _, suggestion in ipairs(suggestions) do
        if type(suggestion) == 'table' then
            raiseSuggestion(suggestion.name, suggestion.help, suggestion.params)
        end
    end
end)

RegisterNetEvent('chat:removeSuggestion', function(name)
    dispatch({ action = 'chatRemoveSuggestion', name = name })
end)

RegisterNetEvent('chat:clear', function()
    dispatch({ action = 'chatClear' })
end)

RegisterNetEvent('codera-hud:chat:commands', function(commands)
    dispatch({ action = 'chatServerCommands', commands = commands })
end)

local function syncCommands()
    local commands = {}
    for _, command in ipairs(GetRegisteredCommands()) do
        local name = command.name
        if name:sub(1, 1) ~= '+' and name:sub(1, 1) ~= '-' then
            if IsAceAllowed('command.' .. name) then
                commands[#commands + 1] = { name = '/' .. name }
            end
        end
    end
    dispatch({ action = 'chatCommands', commands = commands })
    TriggerServerEvent('codera-hud:chat:commands')
end

RegisterCommand('+coderaChat', function() end, false)

RegisterCommand('-coderaChat', function()
    if not (nuiReady and not isOpen and visible) then
        return
    end
    if IsPauseMenuActive() or IsScreenFadedOut() or IsNuiFocused() or CoderaPrefs.IsOpen() then
        return
    end
    if not (CoderaPrefs.Option('hud', true) and CoderaPrefs.Option('playerStatus', true)) then
        return
    end

    isOpen = true
    lastActivity = GetGameTimer()
    syncCommands()
    SetNuiFocus(true, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'chatOpen' })
end, false)

RegisterKeyMapping('+coderaChat', 'Codera HUD: open chat', 'keyboard', chatConfig.openKey or 'T')

RegisterNUICallback('coderaChatReady', function(_, cb)
    nuiReady = true
    dispatch({
        action = 'chatConfig',
        config = {
            maxLength = chatConfig.maxLength or 300,
            maxMessages = chatConfig.maxMessages or 60,
            messageLifetime = chatConfig.lifetimeMs or 8000
        }
    })
    for _, message in ipairs(pendingMessages) do
        SendNUIMessage(message)
    end
    pendingMessages = {}
    syncCommands()
    TriggerServerEvent('chat:init')
    cb({ ok = true })
end)

RegisterNUICallback('coderaChatSubmit', function(data, cb)
    if not isOpen then
        cb({ ok = false })
        return
    end

    local message = type(data.message) == 'string' and data.message or ''
    local maxLength = math.max(1, math.min(1000, chatConfig.maxLength or 300))
    if #message > maxLength * 4 then
        cb({ ok = false })
        return
    end

    message = message:gsub('[%z\001-\031\127]', ''):match('^%s*(.-)%s*$')
    CoderaChat.Close()
    cb({ ok = true })

    if message == '' then
        return
    end

    if message:sub(1, 1) == '/' then
        ExecuteCommand(message:sub(2))
    else
        TriggerServerEvent('codera-hud:chat:send', message)
    end
end)

RegisterNUICallback('coderaChatClose', function(_, cb)
    CoderaChat.Close()
    cb({ ok = true })
end)

RegisterNUICallback('coderaChatHeartbeat', function(_, cb)
    if isOpen then
        lastActivity = GetGameTimer()
    end
    cb({ ok = true })
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', CoderaChat.Close)
RegisterNetEvent('esx:onPlayerLogout', CoderaChat.Close)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        CoderaChat.Close()
        SetTextChatEnabled(true)
    end
end)

CreateThread(function()
    local lastTalking
    while true do
        Wait(60)

        local talking = CoderaChat.IsTalking()
        if talking ~= lastTalking then
            lastTalking = talking
            SendNUIMessage({ action = 'status', talking = talking })
        end

        if isOpen and visible
            and not IsPauseMenuActive() and not IsScreenFadedOut() and not CoderaPrefs.IsOpen()
            and CoderaPrefs.Option('hud', true) and CoderaPrefs.Option('playerStatus', true)
            and GetGameTimer() - lastActivity > 8000 then
            CoderaChat.Close()
        end
    end
end)

CreateThread(function()
    while true do
        SetTextChatEnabled(false)
        DisableControlAction(0, 245, true)
        DisableControlAction(0, 246, true)
        DisableControlAction(0, 247, true)
        DisableControlAction(0, 248, true)
        Wait(0)
    end
end)
