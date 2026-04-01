local Event = require('__stdlib2__/stdlib/event/event').set_protected_mode(true)
local Interface = require('__stdlib2__/stdlib/scripts/interface').merge_interfaces(require('interface'))
local Commands = require('commands')

local ev = defines.events
Event.build_events = {ev.on_built_entity, ev.on_robot_built_entity, ev.script_raised_built, ev.script_raised_revive, ev.on_entity_cloned}
Event.mined_events = {ev.on_pre_player_mined_item, ev.on_robot_pre_mined, ev.script_raised_destroy}

local Player = require('__stdlib2__/stdlib/event/player').register_events(true)
require('__stdlib2__/stdlib/event/force').register_events(true)
require('__stdlib2__/stdlib/event/changes').register_events('mod_versions', 'changes/versions')

Player.additional_data({ranges = {}})

require('scripts/nanobots')
require('scripts/roboport-interface')
require('scripts/armor-mods')

require('scripts/reprogram-gui')

-- v5.5.0: Auto-Defense System
local AutoDefense = require('scripts/auto_defense')

-- v5.7.0: Global nano charge monitor
local NanoMonitor = require('scripts/nano_monitor')

-- v5.4.0: Initialize QualitySystem and cache
local QualitySystem = require('scripts/quality_system')
local CONSTANTS = require('scripts/constants')

Event.on_init(function()
    QualitySystem.init()
    AutoDefense.init()
    NanoMonitor.init()
end)

-- v5.4.2: Initialize cache when mod is added to existing save
Event.on_configuration_changed(function(data)
    -- Check if our mod was added or updated
    local mod_changes = data.mod_changes and data.mod_changes["Nanobots3"]
    if mod_changes then
        -- Initialize cache if it doesn't exist
        QualitySystem.init()
        AutoDefense.init()
        
        -- Migrate old data structure (v5.5.x -> v5.6.0)
        if storage and storage.auto_defense then
            for player_index, player_data in pairs(storage.auto_defense) do
                -- Remove old throttle fields (they used old localization keys)
                if player_data.last_warning_gun_tick then
                    player_data.last_warning_gun_tick = nil
                end
                if player_data.last_warning_artillery_tick then
                    player_data.last_warning_artillery_tick = nil
                end
                
                -- Ensure new structure exists
                if not player_data.last_warnings then
                    player_data.last_warnings = {}
                end
                
                -- v5.7.0: Ensure new statistics fields
                if player_data.statistics then
                    if not player_data.statistics.nano_charges_used then
                        player_data.statistics.nano_charges_used = 0
                    end
                    if not player_data.statistics.session_start_tick then
                        player_data.statistics.session_start_tick = 0
                    end
                end
                
                -- v5.7.0: Ensure lifetime_stats exists
                if not player_data.lifetime_stats then
                    player_data.lifetime_stats = {
                        turrets_rearmed = 0,
                        total_ammo_delivered = 0,
                        nano_charges_used = 0,
                        sessions_count = 0
                    }
                end
            end
        end
        
        -- Sync all player shortcuts after mod update
        for _, player in pairs(game.players) do
            if player and player.valid then
                AutoDefense.init_player(player)
                if storage and storage.auto_defense and storage.auto_defense[player.index] then
                    local player_data = storage.auto_defense[player.index]
                    player.set_shortcut_toggled("nanobots-toggle-auto-defense", player_data.enabled == true)
                end
            end
        end
    end
end)

Event.on_load(function()
    -- IMPORTANT: on_load() must NEVER modify storage!
    -- Shortcut sync will happen via on_player_joined_game event instead
end)

-- v5.4.0: Periodic cache cleanup
Event.on_nth_tick(CONSTANTS.CLEANUP_INTERVAL_TICKS, function(event)
    QualitySystem.cleanup_old_caches(event.tick)
end)

-- v5.5.0: Auto-Defense scanning - MOVED into nanobots.lua unified on_tick
-- AutoDefense.on_tick() and update_open_guis() are now called from poll_players()

-- v5.7.0: Global nano charge monitor (every 1 second)
Event.on_nth_tick(60, function(event)
    pcall(NanoMonitor.check_players)
end)

-- v5.7.0: Update settings cache when settings change
Event.register(defines.events.on_runtime_mod_setting_changed, function(event)
    AutoDefense.on_runtime_mod_setting_changed(event)
end)

-- v5.5.0: Auto-Defense hotkey
Event.register("nanobots-toggle-auto-defense", function(event)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        AutoDefense.toggle(player)
        
        -- Update shortcut button state
        local player_data = storage.auto_defense[player.index]
        if player_data then
            player.set_shortcut_toggled("nanobots-toggle-auto-defense", player_data.enabled)
        end
    end
end)

-- v5.7.0: Stats GUI hotkey
Event.register("nanobots-toggle-stats-gui", function(event)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        AutoDefense.toggle_gui(player)
    end
end)

-- v5.7.0: GUI close button
Event.register(defines.events.on_gui_click, function(event)
    AutoDefense.on_gui_click(event)
end)

-- v5.5.0: Initialize new players
Event.register(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        AutoDefense.init_player(player)
        -- New players start with auto-defense disabled
        player.set_shortcut_toggled("nanobots-toggle-auto-defense", false)
    end
end)

-- v5.6.0: Restore shortcut state when player joins (multiplayer)
Event.register(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        AutoDefense.init_player(player)
        
        -- Sync auto-defense shortcut state
        if storage and storage.auto_defense and storage.auto_defense[player.index] then
            local player_data = storage.auto_defense[player.index]
            local is_enabled = (player_data.enabled == true)
            player.set_shortcut_toggled("nanobots-toggle-auto-defense", is_enabled)
        else
            player.set_shortcut_toggled("nanobots-toggle-auto-defense", false)
        end
        
        -- Restore radius visualization (sync shortcut + recreate render)
        QualitySystem.on_player_joined(player)
    end
end)

remote.add_interface(script.mod_name, Interface)

-- v5.7.0: Cleanup enemy cache and GUI on player leave
Event.register(defines.events.on_player_left_game, function(event)
    AutoDefense.on_player_left(event.player_index)
end)

commands.add_command(script.mod_name, 'Nanobot commands', Commands)
