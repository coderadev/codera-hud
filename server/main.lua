
local prefix = '^5[codera-hud]^7 '

local function log(message)
    print(prefix .. message)
end

CreateThread(function()
    Wait(2000)

    local framework = Config.Framework
    local frameworkResource = Config.FrameworkResources[framework]

    if not frameworkResource then
        log(('^1Invalid Config.Framework "%s". Use qbcore, esx or qbox.^7'):format(tostring(framework)))
        return
    end

    if GetResourceState(frameworkResource) ~= 'started' then
        log(('^1Framework resource "%s" is not started. Start it before codera-hud.^7'):format(frameworkResource))
    end

    local seatbelt = Config.SeatbeltResources and Config.SeatbeltResources[framework]
    if seatbelt and GetResourceState(seatbelt) ~= 'started' then
        log(('^3Seatbelt resource "%s" is not started; seatbelt icon will use statebags only.^7'):format(seatbelt))
    end

    if framework == 'esx' and GetResourceState('esx_status') ~= 'started' then
        log('^3esx_status is not started; hunger and thirst will stay at 100%.^7')
    end

    local wantedVoice = Config.VoiceResource

    local voiceOk
    if wantedVoice == 'pma-voice' or wantedVoice == 'qb-voice' then
        voiceOk = GetResourceState(wantedVoice) == 'started'
    else
        voiceOk = GetResourceState('pma-voice') == 'started' or GetResourceState('qb-voice') == 'started'
    end

    if not voiceOk then
        log('^3Neither pma-voice nor qb-voice is started; voice indicator will show the default mode.^7')
    end

    log(('Started. Framework: ^2%s^7'):format(framework))
end)
