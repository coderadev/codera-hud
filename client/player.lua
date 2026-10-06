
local GROUP_MELEE = 2685387236
local GROUP_PARACHUTE = 431593103
local GROUP_SNIPER = 3082541095

local UNARMED = GetHashKey('WEAPON_UNARMED')

local cache = nil
local hiddenSent = false

local function changed(new, old)
    if not old then return true end
    for key, value in pairs(new) do
        if old[key] ~= value then return true end
    end
    return false
end


local function getVoiceMode()
    local proximity = LocalPlayer.state.proximity
    if type(proximity) == 'table' and tonumber(proximity.index) then
        return math.floor(CoderaHud.Clamp(proximity.index, 1, 3))
    end
    return 2
end

local function getWeaponData(ped)
    local weapon = GetSelectedPedWeapon(ped)
    if weapon == 0 or weapon == UNARMED then return false, 0, 0, 0 end

    local group = GetWeapontypeGroup(weapon)
    if group == GROUP_MELEE or group == GROUP_PARACHUTE then return false, 0, 0, group end

    local total = GetAmmoInPedWeapon(ped, weapon)
    local maxClip = GetMaxAmmoInClip(ped, weapon, true)
    local clip, reserve

    if maxClip and maxClip > 0 then
        local ok, inClip = GetAmmoInClip(ped, weapon)
        clip = ok and inClip or 0
        reserve = math.max(total - clip, 0)
    else
        clip, reserve = total, 0
    end

    return true, clip, reserve, group
end

CreateThread(function()
    while true do
        Wait(Config.Intervals.player)

        if CoderaHud.IsVisible() then
            hiddenSent = false

            local ped = PlayerPedId()
            local playerId = PlayerId()

            local maxHealth = GetEntityMaxHealth(ped)
            local health = GetEntityHealth(ped) - 100
            local healthRange = math.max(maxHealth - 100, 1)
            if IsEntityDead(ped) or health < 0 then health = 0 end

            local hasWeapon, ammoClip, ammoTotal, weaponGroup = getWeaponData(ped)

            local isAiming = Config.UseCustomCrosshair
                and CoderaHud.Setting('player', 'crosshair', true)
                and IsPlayerFreeAiming(playerId)
                and weaponGroup ~= GROUP_SNIPER
                or false

            local inVehicle = IsPedInAnyVehicle(ped, false)
            local showStamina = not inVehicle
                and not IsPedSwimming(ped)
                and (IsPedRunning(ped) or IsPedSprinting(ped))

            local underwater = IsPedSwimmingUnderWater(ped)

            local data = {
                health = math.floor(CoderaHud.Clamp((health / healthRange) * 100, 0, 100)),
                armor = math.floor(CoderaHud.Clamp(GetPedArmour(ped), 0, 100)),
                hunger = math.floor(CoderaHud.needs.hunger),
                thirst = math.floor(CoderaHud.needs.thirst),
                showStamina = showStamina,
                stamina = math.floor(CoderaHud.Clamp(100 - GetPlayerSprintStaminaRemaining(playerId), 0, 100)),
                isUnderwater = underwater,
                oxygen = math.floor(CoderaHud.Clamp(GetPlayerUnderwaterTimeRemaining(playerId) * 10, 0, 100)),
                voice = getVoiceMode(),
                isTalking = NetworkIsPlayerTalking(playerId) and true or false,
                isRadio = CoderaHud.radioActive and true or false,
                isAiming = isAiming,
                hasWeapon = hasWeapon,
                ammoClip = ammoClip,
                ammoTotal = ammoTotal
            }

            CoderaHud.hideNativeCrosshair = isAiming

            if changed(data, cache) then
                cache = data
                SendNUIMessage({ action = 'updatePlayerHud', data = data })
            end
        elseif not hiddenSent then
            hiddenSent = true
            cache = nil
            CoderaHud.hideNativeCrosshair = false
            SendNUIMessage({ action = 'hidePlayerHud' })
        end
    end
end)
