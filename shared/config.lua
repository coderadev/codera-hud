CoderaConfig = {

    framework = 'auto',

    playerResolver = nil,

    general = {
        tickRate           = 200,
        hideNativeHud      = true,
        showNativeAmmo     = true,
        metricUnits        = false,
        showNavigation     = true,
        navTextBackdrop    = false,
        vehicleHintsTimeout = 5000,
    },

    menu = {
        openCommand = 'hudmenu',
        openKey     = 'F7',
        gridSnap    = false,
    },

    stress = {
        speedThresholdKmh = 140.0,

        gain = {
            driving    = 1,
            shooting   = 2,
            cooldownMs = 5000,
        },

        commands = {
            enabled    = true,
            addName    = 'addstress',
            removeName = 'removestress',
            ace        = nil,
        },

        revive = {
            clear  = true,
            events = {
                'hospital:client:Revive',
                'qbx_medical:client:playerRevived',
                'esx_ambulancejob:revive',
                'ambulance:client:revive',
            },
        },

        effects = {
            enabled        = true,
            minLevel       = 50,
            ragdoll        = true,
            blackoutOutMs  = 200,
            blackoutInMs   = 200,

            blurBands = {
                { min = 50, max = 60,  holdMs = 1500 },
                { min = 60, max = 70,  holdMs = 2000 },
                { min = 70, max = 80,  holdMs = 2500 },
                { min = 80, max = 90,  holdMs = 2700 },
                { min = 90, max = 100, holdMs = 3000 },
            },

            intervalBands = {
                { min = 50, max = 60,  minDelayMs = 50000, maxDelayMs = 60000 },
                { min = 60, max = 70,  minDelayMs = 40000, maxDelayMs = 50000 },
                { min = 70, max = 80,  minDelayMs = 30000, maxDelayMs = 40000 },
                { min = 80, max = 90,  minDelayMs = 20000, maxDelayMs = 30000 },
                { min = 90, max = 100, minDelayMs = 15000, maxDelayMs = 20000 },
            },
        },
    },

    radar = {
        maskScale     = 1.05,
        maskOffset    = { x = 0.0, y = 0.0 },
        clipRoute     = true,
        lockToPlayer  = true,
        zoomDistance  = 130.0,
        fallbackZoom  = 1200,

        hideBlips     = false,
        blipRange     = 120.0,
        edgeWaypoint  = true,
    },

    seatbelt = {
        sound     = true,
        animation = true,
        buckle    = { dict = 'codera@anim@seatbelt', names = { 'seatbelt_driver' } },
        unbuckle  = { dict = 'codera@anim@gearbox',  names = { 'gearbox_up' } },
        blendIn   = 8.0,
        blendOut  = -8.0,
        duration  = 1000,
        flag      = 49,
        buckleSound   = { name = 'SELECT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        unbuckleSound = { name = 'BACK',   set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    },

    animations = {
        gearShift = {
            enabled  = true,
            dict     = 'codera@anim@gearbox',
            names    = { 'gearbox_up' },
            blendIn  = 8.0,
            blendOut = -8.0,
            duration = 1000,
            flag     = 49,
            minSpeed = 1.0,
            cooldown = 450,
        },
        horn = {
            enabled  = true,
            dict     = 'codera@anim@gearbox',
            names    = { 'gearbox_up' },
            blendIn  = 8.0,
            blendOut = -8.0,
            duration = 1000,
            flag     = 49,
            cooldown = 900,
        },
    },

    electricVehicles = {
        'airtug', 'caddy', 'caddy2', 'caddy3', 'cyclone', 'cyclone2',
        'dilettante', 'imorgon', 'iwagen', 'khamelion', 'neon', 'omnisegt',
        'powersurge', 'raiden', 'surge', 'tezeract', 'virtue', 'voltic', 'voltic2',
    },

    chat = {
        enabled     = true,
        openKey     = 'T',
        maxLength   = 300,
        lifetimeMs  = 8000,
        maxMessages = 60,
        cooldownMs  = 800,
    },
}
