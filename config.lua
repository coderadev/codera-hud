Config = {}

-- Supported values: 'qbcore', 'esx', 'qbox'
Config.Framework = 'qbcore'

Config.FrameworkResources = {
    qbcore = 'qb-core',
    esx = 'es_extended',
    qbox = 'qbx_core'
}

-- Seatbelt is optional outside QBCore. Statebag-based seatbelt scripts work
-- automatically; set a resource name here only when it exposes
-- HasSeatbeltOn()/HasHarness() like qb-smallresources.
Config.SeatbeltResources = {
    qbcore = 'qb-smallresources',
    esx = false,
    qbox = false
}

Config.NeedsRefreshInterval = 5000

-- Voice resource used for the mic/proximity/radio indicator on the player HUD.
-- Supported values: 'pma-voice', 'qb-voice' or 'auto' (detects whichever of the
-- two is started; pma-voice takes priority if both happen to be running).
Config.VoiceResource = 'auto'

-- Commands registered by codera-hud.
Config.Commands = {
    cinematic = 'cinematic',
    hudsettings = 'hudsettings', -- opens the personal HUD settings menu
    devmode = 'devmode' -- toggles the green developer-mode badge on the player HUD
}

-- Name shown in the footer of the /hudsettings menu ("<name> / PERSONAL SETTINGS").
Config.SettingsBrand = 'CODERA HUD'

-- Client update intervals in milliseconds.
-- These values are read directly by the runtime loops. Lower values update more
-- frequently but use more client CPU time. The defaults below are tuned to keep
-- the HUD responsive without sending unnecessary NUI messages.
Config.Intervals = {
    player = 200,          -- Health, armour, needs, voice, stamina and weapon data.
    vehicle = 50,          -- Vehicle data while the player is inside a vehicle.
    vehicleIdle = 250,     -- Vehicle presence check while outside a vehicle.
    compassHeading = 25,   -- Camera heading target; NUI interpolation keeps it smooth.
    compassDetails = 250,  -- Street, zone and custom waypoint distance/direction.
    minimap = 1000         -- Resolution, safezone and minimap position checks.
}

-- Vehicle speed display. The default multiplier converts GTA metres/second to MPH.
-- Use 3.6 and 'KM/H' if you want metric speed instead.
Config.SpeedMultiplier = 2.236936
Config.SpeedUnit = 'MPH'
Config.MaxSpeed = 160 -- Speed at which the outer speed arc reaches 100%.

-- Warn players when their GTA safezone is too small for the HUD layout.
Config.ShowSafezoneWarning = true
Config.RequiredSafezone = 0.99

-- Display the custom aiming crosshair handled by the player HUD.
Config.UseCustomCrosshair = true

-- Minimap zoom distance in game-world meters (SET_RADAR_ZOOM_TO_DISTANCE).
-- Smaller number = closer/more detail, bigger = wider area. codera-hud's ring
-- is physically smaller on screen than chase_hud's radar circle, so the same
-- meter value looks more "zoomed out" here -- 80 is a scaled-down starting
-- point to roughly match chase_hud's look. Fine-tune live with /mapzoom <number>.
Config.MapZoom = 80.0

Config.Chat = {
    enabled = true,       -- true = use the built-in chat, false = use your own chat resource
    key = 'T',            -- keyboard key that opens the chat box
    maxLength = 120,       -- max characters per message
    maxHistory = 50,       -- messages kept in memory (scroll/log)
    visibleWhenClosed = 6, -- how many recent messages stay on screen once the box is closed
    fadeAfter = 8000,      -- ms a message stays fully visible before it starts fading out
    fadeDuration = 400,    -- ms of the fade-out transition
    inputWidth = 340        -- px width of the chat input pill
}
