-- Auto-Defense Hotkey and Shortcut

local constants = require('prototypes/ammo/constants')

-- Ammo delivery projectile (orange color = defense)
local defense_orange = { r = 1.0, g = 0.6, b = 0.1, a = 1.0 }

local projectile_defense = {
    type = 'projectile',
    name = 'nano-projectile-defense',
    flags = { 'not-on-map' },
    acceleration = 0.005,
    direction_only = false,
    animation = constants.projectile_animation,
    light = { intensity = 0.5, size = 5, color = defense_orange },
    final_action = {
        type = 'direct',
        action_delivery = {
            type = 'instant',
            target_effects = {
                {
                    type = 'create-entity',
                    entity_name = 'nano-cloud-small-defense',
                    check_buildability = false
                }
            }
        }
    }
}

local cloud_small_defense = {
    type = 'smoke-with-trigger',
    name = 'nano-cloud-small-defense',
    flags = { 'not-on-map' },
    show_when_smoke_off = true,
    animation = constants.cloud_animation(.3),
    affected_by_wind = false,
    cyclic = true,
    duration = 60,
    fade_away_duration = 30,
    spread_duration = 10,
    color = { r = 1.0, g = 0.7, b = 0.2, a = 0.6 },
    action = nil
}


data:extend({
    projectile_defense,
    cloud_small_defense,

    -- Custom input (hotkey)
    {
        type = "custom-input",
        name = "nanobots-toggle-auto-defense",
        key_sequence = "ALT + G",
        consuming = "none",
        action = "lua"
    },
    
    -- Shortcut button
    {
        type = "shortcut",
        name = "nanobots-toggle-auto-defense",
        action = "lua",
        toggleable = true,
        icon = "__Nanobots3__/graphics/icons/nano-gun.png",
        icon_size = 64,
        small_icon = "__Nanobots3__/graphics/icons/nano-gun.png",
        small_icon_size = 64,
        order = "a[nanobots]-c[auto-defense]"
    },

    -- v5.7.0: Stats GUI hotkey
    {
        type = "custom-input",
        name = "nanobots-toggle-stats-gui",
        key_sequence = "ALT + H",
        consuming = "none",
        action = "lua"
    }
})
