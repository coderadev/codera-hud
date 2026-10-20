Config = {}

Config.Framework = 'qbcore'

Config.FrameworkResources = {
    qbcore = 'qb-core',
    esx = 'es_extended',
    qbox = 'qbx_core'
}

Config.SeatbeltResources = {
    qbcore = 'qb-smallresources',
    esx = false,
    qbox = false
}

Config.MechanicResource = false

Config.NeedsRefreshInterval = 5000

Config.VoiceResource = 'auto'

Config.Commands = {
    cinematic = 'cinematic',
    hudsettings = 'hudsettings',
    devmode = 'devmode'
}

Config.SettingsBrand = 'CODERA HUD'

Config.Intervals = {
    player = 200,
    vehicle = 50,
    vehicleIdle = 250,
    compassHeading = 25,
    compassDetails = 250,
    minimap = 1000
}

Config.SpeedMultiplier = 2.236936
Config.SpeedUnit = 'MPH'
Config.MaxSpeed = 160

Config.MaxAircraftSpeed = 200

Config.AircraftAltitude = 'ground'

Config.ElectricVehicles = {
    'voltic',
    'voltic2',
    'khamelion',
    'raiden'

}

Config.ShowVehicleControlsBar = true

Config.ShowSafezoneWarning = true
Config.RequiredSafezone = 0.99

Config.UseCustomCrosshair = true

Config.MapZoom = 140.0

Config.Chat = {
    enabled = true,
    key = 'T',
    maxLength = 120,
    maxHistory = 50,
    visibleWhenClosed = 6,
    fadeAfter = 8000,
    fadeDuration = 400,
    inputWidth = 340
}

Config.RadarAutoCalibrate = true
Config.RadarMaskScale = 1.0
Config.RadarMaskOffsetX = -0.17
Config.RadarMaskOffsetY = 0.22

Config.RadarEngineScaleX = 0.765
Config.RadarEngineScaleY = 1.10
