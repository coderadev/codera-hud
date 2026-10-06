# codera-hud

A full-screen FiveM HUD with status bars, speedometer, compass, circular radar, a per-player layout editor and a built-in chat. It supports QBox, QBCore and ESX out of the box and can be wired to any other framework through a small adapter.
<img width="1919" height="1079" alt="657644549-c87688fa-15fa-4771-8091-661bb46e155e" src="https://github.com/user-attachments/assets/9fdc34f1-d63e-4b19-ba38-d2368d99988b" />
<img width="1919" height="1079" alt="659827967-8da39018-91be-434d-9c07-3e1549ceb715" src="https://github.com/user-attachments/assets/f992d2f8-f544-4040-a703-a7794452c6fc" />

## Features

- Health, armor, hunger, thirst, stamina, oxygen and stress indicators
- Vehicle speedometer with RPM, gear, fuel / battery, seatbelt and engine state
- Compass with street name, zone name and waypoint marker on the radar ring
- Circular radar with route clipping and blip range limiting
- Player settings menu with drag-and-drop layout editor (saved per character)
- Stress system with blur, blackout and ragdoll effects plus admin commands
- Seatbelt, gear-shift and horn animations
- Optional built-in chat with command suggestions and rate limiting

## Requirements

- FX server with `lua54` support (artifact 5848 or newer is recommended)
- One of: `qbx_core`, `qb-core`, `es_extended` (or use the `custom` framework mode)
- ESX only: `esx_status` for hunger and thirst

## Installation

1. Place the `codera-hud` folder in your `resources` directory.
2. Add it to `server.cfg`:
   ```cfg
   ensure codera-hud
   ```
3. Stop or remove any other HUD resource (and any other chat resource if you keep `chat.enabled = true`).
4. Adjust `shared/config.lua` to your needs and restart the resource.


Set `framework = 'custom'` and provide a resolver:

```lua
playerResolver = function()
    return { id = 'unique-character-id', cash = 0, bank = 0 }
end,
```

Hunger and thirst can be pushed with the `status` export or the `codera-hud:updateStatus` event (see below). Hunger/thirst reading for other frameworks can also be added in `bridge/adapter.lua`.

## Commands and keys

| Command | Default key | Description |
| --- | --- | --- |
| `/hudmenu` | `F7` | Open the HUD settings and layout editor |
| `/seatbelt` | `B` | Toggle the seatbelt |
| `/speedunit [mph\|kmh]` | none | Switch the speed unit |
| `/coderahud` | none | Show or hide the whole HUD |
| `/huddev` | none | Toggle developer mode |
| `/addstress <id> <percent>` | none | Admin: add stress to a player |
| `/removestress [id]` | none | Admin: clear stress (defaults to yourself) |
| Chat | `T` | Open the chat (when enabled) |

Stress commands are available to admins automatically (ACE `group.admin`, `group.superadmin`, `command.<name>`, or QBox / QBCore / ESX admin groups). Use `stress.commands.ace` to require a custom ACE, or set it to `false` to allow everyone.

## Exports (client)

```lua
exports['codera-hud']:SetVisible(true)
exports['codera-hud']:showHUD()
exports['codera-hud']:hideHUD()
exports['codera-hud']:SetStatus({ ... })            -- push raw status values to the NUI
exports['codera-hud']:SetSpeedUnit(true)            -- true = km/h
exports['codera-hud']:SetNavigationVisible(true)
exports['codera-hud']:showCompass()
exports['codera-hud']:hideCompass()
exports['codera-hud']:SetSpeedometerVisible(true)
exports['codera-hud']:showSpeedometer()
exports['codera-hud']:hideSpeedometer()
exports['codera-hud']:SetStress(50)
exports['codera-hud']:AddStress(10)
exports['codera-hud']:DecreaseStress(10)            -- alias: RemoveStress
exports['codera-hud']:GetStress()
exports['codera-hud']:ResetStress()
exports['codera-hud']:OpenSettings()
```

When `chat.enabled = true` the chat exports `addMessage` and `addSuggestion` are also provided and the usual `chat:*` events are handled.

## Events

Client events:

| Event | Arguments |
| --- | --- |
| `codera-hud:setVisible` | `boolean` |
| `codera-hud:setNavigationVisible` | `boolean` |
| `codera-hud:setSpeedometerVisible` | `boolean` |
| `codera-hud:updateStatus` | `table` |
| `codera-hud:setStress` | `number` |
| `codera-hud:addStress` | `number` |
| `codera-hud:openSettings` | none |

Server-side use, for example from an admin script:

```lua
TriggerClientEvent('codera-hud:addStress', playerId, 15)
TriggerClientEvent('codera-hud:setStress', playerId, 0)
```

