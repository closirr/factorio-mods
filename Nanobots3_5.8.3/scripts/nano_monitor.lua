-- ═══════════════════════════════════════════════════════════════════════════
-- GLOBAL NANO CHARGE MONITOR
-- v5.7.0: Watches nano-ammo count for ALL players independently of
-- auto-defense or construction systems. Warns when running low.
-- ═══════════════════════════════════════════════════════════════════════════

local NanoMonitor = {}

local WARN_COOLDOWN = 600  -- 10 seconds between warnings

-- Find nano-emitter gun slot index (returns index or nil)
-- Respects nanobots-active-emitter-mode setting
local function find_nano_emitter_index(player)
    if not (player and player.valid and player.character and player.character.valid) then
        return nil
    end
    
    local gun_inv = player.character.get_inventory(defines.inventory.character_guns)
    if not gun_inv then return nil end
    
    local active_mode = player.mod_settings['nanobots-active-emitter-mode'].value
    
    if active_mode then
        -- Only check selected weapon slot
        local index = player.character.selected_gun_index
        local gun = gun_inv[index]
        if gun and gun.valid_for_read and gun.name == 'gun-nano-emitter' then
            return index
        end
        return nil
    else
        -- Check all slots
        for i = 1, #gun_inv do
            local gun = gun_inv[i]
            if gun and gun.valid_for_read and gun.name == 'gun-nano-emitter' then
                return i
            end
        end
        return nil
    end
end

-- Find nano-ammo in player's ammo inventory (slot matching nano-emitter)
local function get_nano_ammo(player)
    if not (player and player.valid and player.character and player.character.valid) then
        return nil
    end
    
    local ammo_inv = player.character.get_inventory(defines.inventory.character_ammo)
    if not ammo_inv then return nil end
    
    local index = find_nano_emitter_index(player)
    if not index then return nil end
    
    local ammo = ammo_inv[index]
    if ammo and ammo.valid_for_read then
        return ammo
    end
    
    return nil
end

-- Count total nano-ammo across all inventory stacks
local function count_total_nano_ammo(player)
    if not (player and player.valid) then return 0, nil end
    
    -- First: check the gun ammo slot (active ammo)
    local active_ammo = get_nano_ammo(player)
    local active_count = 0
    if active_ammo and active_ammo.valid_for_read then
        active_count = active_ammo.count or 0
    end
    
    -- Second: count all nano ammo in main inventory
    local inv = player.get_main_inventory()
    local inv_count = 0
    if inv and inv.valid then
        -- Check for known nano ammo types
        local nano_types = {"nano-ammo-constructors", "nano-ammo-deconstructors", "nano-ammo-termites", "nano-ammo-scrappers"}
        for _, ammo_name in pairs(nano_types) do
            inv_count = inv_count + inv.get_item_count(ammo_name)
        end
    end
    
    return active_count + inv_count, active_ammo
end

function NanoMonitor.init()
    storage.nano_monitor = storage.nano_monitor or {}
end

function NanoMonitor.check_players()
    if not storage.nano_monitor then
        storage.nano_monitor = {}
    end
    
    local current_tick = game.tick
    
    for _, player in pairs(game.connected_players) do
        if player.valid and player.character and player.character.valid then
            local pi = player.index
            local pdata = storage.nano_monitor[pi]
            if not pdata then
                pdata = {last_warn_tick = 0, warned = false}
                storage.nano_monitor[pi] = pdata
            end
            
            -- v5.8.0: Direct access to settings (already protected by outer pcall in control.lua)
            local threshold = player.mod_settings["nanobots-auto-defense-low-nano-threshold"].value or 10
            
            if threshold <= 0 then goto continue end
            
            -- Get warning interval from per-player setting (seconds -> ticks)
            local interval_str = player.mod_settings["nanobots-low-nano-warning-interval"].value or "30"
            local interval_sec = tonumber(interval_str) or 30
            local warn_interval_ticks = interval_sec * 60
            
            -- Only check if player has a nano-emitter equipped
            local emitter_index = find_nano_emitter_index(player)
            if not emitter_index then
                -- No nano emitter equipped — skip
                pdata.warned = false
                pdata.depleted_warned = false
                goto continue
            end
            
            local active_ammo = get_nano_ammo(player)
            
            if not active_ammo or not active_ammo.valid_for_read then
                -- v5.8.0: Emitter equipped but ammo slot empty!
                if (current_tick - (pdata.last_warn_tick or 0)) >= warn_interval_ticks then
                    pdata.last_warn_tick = current_tick
                    pdata.depleted_warned = true
                    
                    player.create_local_flying_text({
                        text = {"auto-defense.nano-ammo-empty"},
                        position = player.character.position,
                        color = {r = 1, g = 0, b = 0},
                        time_to_live = 180,
                        speed = 0.3
                    })
                    
                    player.character.surface.play_sound{path = "utility/cannot_build", position = player.character.position, volume_modifier = 0.7}
                end
                goto continue
            end
            
            local count = active_ammo.count or 0
            
            if count <= threshold and count > 0 then
                -- Throttle warnings using configurable interval
                if (current_tick - (pdata.last_warn_tick or 0)) >= warn_interval_ticks then
                    pdata.last_warn_tick = current_tick
                    pdata.warned = true
                    
                    player.create_local_flying_text({
                        text = {"auto-defense.low-nano-ammo", count},
                        position = player.character.position,
                        color = {r = 1, g = 0.3, b = 0},
                        time_to_live = 150,
                        speed = 0.4
                    })
                    
                    player.character.surface.play_sound{path = "utility/cannot_build", position = player.character.position, volume_modifier = 0.7}
                end
            elseif count == 0 then
                -- Ammo depleted completely (use same interval)
                if not pdata.depleted_warned or (current_tick - (pdata.last_warn_tick or 0)) >= warn_interval_ticks then
                    pdata.last_warn_tick = current_tick
                    pdata.depleted_warned = true
                    
                    player.create_local_flying_text({
                        text = {"auto-defense.nano-ammo-depleted"},
                        position = player.character.position,
                        color = {r = 1, g = 0, b = 0},
                        time_to_live = 180,
                        speed = 0.3
                    })
                    
                    player.character.surface.play_sound{path = "utility/cannot_build", position = player.character.position, volume_modifier = 0.7}
                end
            else
                -- Ammo above threshold — reset warnings
                pdata.warned = false
                pdata.depleted_warned = false
            end
            
            ::continue::
        end
    end
end

return NanoMonitor
