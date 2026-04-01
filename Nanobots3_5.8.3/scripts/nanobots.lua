-- scripts/nanobots.lua (UPDATED)
-- Fixes:
--  - Repair visuals use nano-projectile-repair (green repair effect)
--  - Prevent "LuaEntity API call when LuaEntity was invalid" in ghost scan loop

_G.DEBUG_NANO = 0 -- default OFF, global for module access

-- v5.8.0: Cached debug flags (updated in update_settings)
local debug_repair_enabled = false

-- Aggregated logging
local aggregated_messages = {}
local AGGREGATE_SILENCE_THRESHOLD = 120 -- 2 sec (120 ticks)

local function nlog(msg)
    if _G.DEBUG_NANO >= 1 and debug_repair_enabled and game then
        game.print("[NANO] " .. msg)
    end
end

local function nlog_dbg(msg)
    if _G.DEBUG_NANO >= 2 and debug_repair_enabled and game then
        game.print("[NANO:DBG] " .. msg)
    end
end

local function nlog_agg(category, name, count)
    if _G.DEBUG_NANO < 2 or not debug_repair_enabled then return end
    if not game then return end
    
    count = count or 1
    local key = category .. "|" .. (name or "unknown")
    local t = game.tick
    local rec = aggregated_messages[key]
    if rec then
        rec.count = rec.count + count
        rec.last_tick = t
    else
        aggregated_messages[key] = { count = count, last_tick = t }
    end
end

local function flush_aggregated_messages()
    if _G.DEBUG_NANO < 2 then return end
    if not game then return end
    local t = game.tick
    local rm = {}
    for key, rec in pairs(aggregated_messages) do
        if t - rec.last_tick >= AGGREGATE_SILENCE_THRESHOLD then
            local category, name = key:match("([^|]+)|(.+)")
            if category and name then
                game.print("[NANO:AGG] " .. category .. ": " .. name .. " x" .. rec.count)
            end
            rm[#rm + 1] = key
        end
    end
    for _, key in ipairs(rm) do
        aggregated_messages[key] = nil
    end
end

local Event = require('__stdlib2__/stdlib/event/event').set_protected_mode(true)
local Area = require('__stdlib2__/stdlib/area/area')
local Position = require('__stdlib2__/stdlib/area/position')
local table = require('__stdlib2__/stdlib/utils/table')
local time = require('__stdlib2__/stdlib/utils/defines/time')
local Queue = require('scripts/hash_queue')

-- v5.0 NEW: Безопасные модули
local SafeEntity = require('scripts/safe_entity')
local ModuleRequests = require('scripts/module_requests')

-- v5.2 NEW: Система качества и визуализация
local QualitySystem = require('scripts/quality_system')

-- v5.5.0: Auto-Defense System
local AutoDefense = require('scripts/auto_defense')

-- v5.4.0: Централизованные константы
local CONSTANTS = require('scripts/constants')

local queue
local cfg

local max, floor = math.max, math.floor
local lua_table_sort = _G.table.sort

local config = require('config')
local armormods = require('scripts/armor-mods')

local bot_radius = config.BOT_RADIUS
local queue_speed = config.QUEUE_SPEED_BONUS

local function unique(tbl)
    return table.keys(table.invert(tbl))
end

local inv_list = unique {
    defines.inventory.character_trash,
    defines.inventory.character_main,
    defines.inventory.god_main,
    defines.inventory.chest,
    defines.inventory.character_vehicle,
    defines.inventory.car_trunk,
    defines.inventory.cargo_wagon
}

local moveable_types = { train = true, car = true, spidertron = true }
local blockable_types = { ['straight-rail'] = false, ['curved-rail'] = false }

local explosives = {
    { name = 'cliff-explosives', count = 1 }, { name = 'explosives', count = 10 }, { name = 'explosive-rocket', count = 4 },
    { name = 'explosive-cannon-shell', count = 4 }, { name = 'cluster-grenade', count = 2 }, { name = 'grenade', count = 14 },
    { name = 'land-mine', count = 5 }, { name = 'artillery-shell', count = 1 }
}

-- Repair type groups + scan lists builder (4.7.0)
local REPAIR_TYPE_GROUPS = {
    defense = { "ammo-turret", "electric-turret", "fluid-turret", "artillery-turret", "wall", "gate", "radar", "land-mine" },
    transport = { "car", "spider-vehicle", "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon" },
    power = {
        "electric-pole", "accumulator", "solar-panel", "generator", "boiler",
        "reactor", "heat-exchanger", "heat-pipe",
        "offshore-pump", "pump", "pipe", "pipe-to-ground",
        "power-switch", "electric-energy-interface"
    },
    production = { "assembling-machine", "furnace", "mining-drill", "inserter", "roboport", "lab", "beacon" },
    other = {"container", "logistic-container", "storage-tank", 
    "straight-rail", "curved-rail", "half-diagonal-rail",
    "curved-rail-a", "curved-rail-b",
    "elevated-straight-rail", "elevated-curved-rail", 
    "elevated-curved-rail-a", "elevated-curved-rail-b",
    "elevated-half-diagonal-rail",
    "rail-ramp", "rail-support",
    "rail-signal", "rail-chain-signal",
    "train-stop",
    "transport-belt", "underground-belt", "splitter", "loader", "loader-1x1",
    "linked-belt", "lane-splitter"}
}

local function build_repair_scan_types()
    if not cfg then return end
    local normal = {}

    local function add(group)
        for _, t in ipairs(REPAIR_TYPE_GROUPS[group]) do
            normal[#normal + 1] = t
        end
    end

    if cfg.repair_cat_defense then add("defense") end
    if cfg.repair_cat_transport then add("transport") end
    if cfg.repair_cat_power then add("power") end
    if cfg.repair_cat_production then add("production") end
    if cfg.repair_cat_other then add("other") end

    cfg.repair_scan_types_normal = normal

    local combat = {}
    local function addc(group)
        for _, t in ipairs(REPAIR_TYPE_GROUPS[group]) do
            combat[#combat + 1] = t
        end
    end
    addc("defense")
    addc("transport")
    cfg.repair_scan_types_combat = combat
end

-- Settings
local function update_settings()
    local setting = settings['global']

    local log_level_str = setting['nanobots-log-level'].value
    if log_level_str == "off" then
        _G.DEBUG_NANO = 0
    elseif log_level_str == "standard" then
        _G.DEBUG_NANO = 1
    elseif log_level_str == "debug" then
        _G.DEBUG_NANO = 2
    else
        _G.DEBUG_NANO = 0
    end

    local function gv(name, default)
        local s = setting[name]
        if not s then return default end
        return s.value
    end

    cfg = {
        poll_rate = gv('nanobots-nano-poll-rate', 60),
        queue_rate = gv('nanobots-nano-queue-rate', 12),
        queue_cycle = gv('nanobots-nano-queue-per-cycle', 100),
        build_tiles = gv('nanobots-nano-build-tiles', true),
        network_limits = gv('nanobots-network-limits', true),
        nanobots_auto = gv('nanobots-nanobots-auto', true),
        equipment_auto = gv('nanobots-equipment-auto', true),
        afk_time = gv('nanobots-afk-time', 4) * time.second,
        do_proxies = gv('nanobots-nano-fullfill-requests', true),
        do_repair = gv('nanobots-nano-repair', true),

        -- 4.7.0 repair settings
        repair_threshold = tonumber(gv('nanobots-repair-start-threshold', "0.95")) or 0.95,
        repair_max_sessions = gv('nanobots-repair-max-sessions', 15),
        repair_hp_per_action = gv('nanobots-repair-hp-per-action', 20),
        repair_requeue_delay = gv('nanobots-repair-requeue-delay', 20),
        repair_throttle_ticks = gv('nanobots-repair-throttle-ticks', 60),

        repair_combat_important_only = gv('nanobots-repair-combat-important-only', true),
        repair_combat_enemy_radius = gv('nanobots-repair-combat-enemy-radius', 32),
        repair_combat_recent_damage_ticks = (gv('nanobots-repair-combat-recent-damage-seconds', 10) or 0) * 60,

        repair_cat_defense = gv('nanobots-repair-cat-defense', true),
        repair_cat_transport = gv('nanobots-repair-cat-transport', true),
        repair_cat_power = gv('nanobots-repair-cat-power', true),
        repair_cat_production = gv('nanobots-repair-cat-production', true),
        repair_cat_other = gv('nanobots-repair-cat-other', false)
    }

    build_repair_scan_types()

    if _G.DEBUG_NANO >= 1 then
        nlog("Log level: " .. log_level_str)
    end
    
    -- v5.8.0: Cache debug flag
    debug_repair_enabled = false
    if settings and settings.global then
        local dbg_setting = settings.global["nanobots-debug-repair-system"]
        if dbg_setting and dbg_setting.value then
            debug_repair_enabled = true
        end
    end
end

Event.register(defines.events.on_runtime_mod_setting_changed, update_settings)
update_settings()

-- Combat detection
Event.register(defines.events.on_entity_damaged, function(e)
    local ent = e.entity
    if not (ent and ent.valid) then return end
    if ent.type ~= "character" then return end
    local player = ent.player
    if not (player and player.valid) then return end

    storage.players = storage.players or {}
    storage.players[player.index] = storage.players[player.index] or {}
    storage.players[player.index].last_damaged_tick = game.tick
end)

local function is_player_in_combat(player)
    if not (player and player.valid and player.character and player.character.valid) then
        return false
    end
    local pdata = storage.players and storage.players[player.index]
    local last = pdata and pdata.last_damaged_tick or nil

    if last and (cfg.repair_combat_recent_damage_ticks or 0) > 0 then
        if (game.tick - last) <= cfg.repair_combat_recent_damage_ticks then
            return true
        end
    end

    local r = cfg.repair_combat_enemy_radius or 0
    if r <= 0 then
        return false
    end

    local c = player.character
    local cnt = c.surface.count_entities_filtered { position = c.position, radius = r, force = { "enemy" }, limit = 1 }
    return (cnt and cnt > 0) or false
end

-- Repair sessions + throttle
local function get_session_bucket(player_index)
    storage.repair_sessions = storage.repair_sessions or {}
    local b = storage.repair_sessions[player_index]
    if not b then
        b = { count = 0, units = {} }
        storage.repair_sessions[player_index] = b
    end
    return b
end

local function session_active(player_index, unit_number)
    local b = storage.repair_sessions and storage.repair_sessions[player_index]
    return b and b.units and b.units[unit_number] ~= nil
end

local function session_count(player_index)
    local b = storage.repair_sessions and storage.repair_sessions[player_index]
    return (b and b.count) or 0
end

local function can_start_new_session(player_index)
    return session_count(player_index) < (cfg.repair_max_sessions or 15)
end

local function start_session(player_index, unit_number)
    local b = get_session_bucket(player_index)
    if not b.units[unit_number] then
        b.units[unit_number] = { last_tick = game.tick }
        b.count = (b.count or 0) + 1
    else
        b.units[unit_number].last_tick = game.tick
    end
end

local function touch_session(player_index, unit_number)
    local b = storage.repair_sessions and storage.repair_sessions[player_index]
    if b and b.units and b.units[unit_number] then
        b.units[unit_number].last_tick = game.tick
    end
end

local function end_session(player_index, unit_number)
    local b = storage.repair_sessions and storage.repair_sessions[player_index]
    if b and b.units and b.units[unit_number] then
        b.units[unit_number] = nil
        b.count = math.max(0, (b.count or 1) - 1)
    end
end

local function cleanup_sessions_all()
    if not storage.repair_sessions then return end
    local timeout = 60 * 15 -- 15 sec idle => drop
    for _, b in pairs(storage.repair_sessions) do
        if b and b.units then
            for unit, rec in pairs(b.units) do
                if not rec or (game.tick - (rec.last_tick or 0)) > timeout then
                    b.units[unit] = nil
                    b.count = math.max(0, (b.count or 1) - 1)
                end
            end
        end
    end
end

local function ensure_throttle()
    storage.repair_last_scan_tick = storage.repair_last_scan_tick or {}
end

-- v5.8.0: Precomputed priority lookup table (O(1) instead of O(n))
local REPAIR_PRIORITY_MAP = {}
-- Defense: priority 10
for _, t in ipairs({"wall", "gate", "ammo-turret", "electric-turret", "fluid-turret", "artillery-turret"}) do
    REPAIR_PRIORITY_MAP[t] = 10
end
REPAIR_PRIORITY_MAP["radar"] = 20
REPAIR_PRIORITY_MAP["land-mine"] = 30
-- Transport: priority 40
for _, t in ipairs({"car", "spider-vehicle", "locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"}) do
    REPAIR_PRIORITY_MAP[t] = 40
end
-- Power: priority 50
for _, t in ipairs(REPAIR_TYPE_GROUPS.power) do
    REPAIR_PRIORITY_MAP[t] = 50
end
-- Production: priority 60
for _, t in ipairs(REPAIR_TYPE_GROUPS.production) do
    REPAIR_PRIORITY_MAP[t] = 60
end
-- Other: priority 70
for _, t in ipairs(REPAIR_TYPE_GROUPS.other) do
    REPAIR_PRIORITY_MAP[t] = 70
end

local function get_repair_priority(entity)
    return REPAIR_PRIORITY_MAP[entity.type] or 80
end

-- Item search
local current_player
local current_at_least_one

local function find_item(simple_stack, _, player, at_least_one)
    current_player = player
    current_at_least_one = at_least_one

    local function _find_item(inner_stack)
        local player = current_player
        local at_least_one = current_at_least_one

        local item = inner_stack.name
        local count = inner_stack.count
        local quality = inner_stack.quality or "normal"
        count = at_least_one and 1 or count

        local prototype = prototypes.item[item]
        if not prototype then return false end
        if prototype.type == 'item-with-inventory' then return false end

        local have = player.get_item_count({ name = item, quality = quality })
        nlog_agg("Поиск предмета", item .. " (" .. quality .. ")")

        if player.cheat_mode or have >= count then
            return true
        end

        local vehicle = player.vehicle
        local train = vehicle and vehicle.train
        return vehicle and ((vehicle.get_item_count({ name = item, quality = quality }) >= count)
            or (train and train.get_item_count({ name = item, quality = quality }) >= count))
    end

    return _find_item(simple_stack)
end

local function local_find_item(list, player, at_least_one)
    for _, stack in pairs(list or {}) do
        if find_item(stack, nil, player, at_least_one) then
            return stack
        end
    end
    return nil
end

local function is_connected_player_ready(player)
    return (cfg.afk_time <= 0 or player.afk_time < cfg.afk_time) and player.character
end

local function has_powered_equipment(character, eq_name)
    local grid = character.grid
    if grid then
        local eq = grid.find(eq_name)
        return eq and eq.energy > 0
    end
end

local function nano_network_check(character, target)
    if has_powered_equipment(character, 'equipment-bot-chip-nanointerface') then
        return true
    else
        local c = character
        local networks = target and target.valid
            and target.surface.find_logistic_networks_by_construction_area(target.position, target.force)
            or c.surface.find_logistic_networks_by_construction_area(c.position, c.force)

        local pnetwork = c.logistic_cell and c.logistic_cell.mobile and c.logistic_cell.logistic_network
        
        -- v5.7.0: Check if personal roboport is ENABLED
        -- allow_dispatching_robots = false when player toggles roboport off (ALT+F or shortcut bar)
        local has_pbots = false
        if c.logistic_cell and c.logistic_cell.mobile then
            local cell = c.logistic_cell
            -- Check if roboport is enabled via character property
            local roboport_enabled = c.allow_dispatching_robots
            
            if roboport_enabled then
                -- Roboport is enabled, check for robots
                if cell.stationed_construction_robot_count and cell.stationed_construction_robot_count > 0 then
                    has_pbots = true
                elseif cell.logistic_network and cell.logistic_network.all_construction_robots > 0 then
                    has_pbots = true
                end
            end
            -- If roboport is disabled (allow_dispatching_robots = false), has_pbots stays false = nanobots can work
        end

        local has_nbots = table.any(networks or {}, function(network)
            return network ~= pnetwork and network.all_construction_robots > 0
        end)
        return not (has_pbots or has_nbots)
    end
end

local function nano_repairable_entity(entity)
    if not SafeEntity.is_valid(entity) then return false end
    
    -- v5.1: Безопасные проверки через SafeEntity
    if SafeEntity.has_flag(entity, 'not-repairable') then return false end
    
    local entity_type = SafeEntity.get_type(entity)
    if entity_type:find('robot') then return false end
    
    -- Проверка blockable_types
    if blockable_types[entity_type] then
        local is_minable = SafeEntity.get_property(entity, "minable")
        if is_minable == false then return false end
    end
    
    -- Проверка здоровья
    if SafeEntity.get_health_ratio(entity, 1) >= 1 then return false end
    
    -- Проверка движения
    if moveable_types[entity_type] then
        local speed = SafeEntity.get_property(entity, "speed", 0)
        if speed > 0 then return false end
    end
    
    -- Безопасная проверка collision_mask
    local proto = SafeEntity.get_prototype(entity)
    if proto and proto.collision_mask then
        return table_size(proto.collision_mask) > 0
    end
    
    return false
end

local function get_gun_ammo_name(player, gun_name)
    if not (player and player.valid and player.character and player.character.valid) then
        return nil, nil, nil
    end
    local gun_inv = player.character.get_inventory(defines.inventory.character_guns)
    local ammo_inv = player.character.get_inventory(defines.inventory.character_ammo)
    if not (gun_inv and ammo_inv) then return nil, nil, nil end

    local gun, ammo
    if not player.mod_settings['nanobots-active-emitter-mode'].value then
        local index
        gun, index = gun_inv.find_item_stack(gun_name)
        ammo = gun and ammo_inv[index]
    else
        local index = player.character.selected_gun_index
        gun, ammo = gun_inv[index], ammo_inv[index]
    end

    if gun and gun.valid_for_read and ammo and ammo.valid_for_read then
        return gun, ammo, ammo.name
    end
    return nil, nil, nil
end

-- insert/spill helpers
local function insert_or_spill_items(entity, item_stacks, is_return_cheat)
    if is_return_cheat then return end
    if not (entity and entity.valid) then return end

    local new_stacks = {}
    if item_stacks then
        if item_stacks[1] and item_stacks[1].name then
            new_stacks = item_stacks
        elseif item_stacks and item_stacks.name then
            new_stacks = { item_stacks }
        end

        for _, stack in pairs(new_stacks) do
            local name, count, health = stack.name, stack.count, stack.health or 1
            if prototypes.item[name] and not prototypes.item[name].hidden then
                local inserted = entity.insert({ name = name, count = count, health = health })
                if inserted ~= count then
                    entity.surface.spill_item_stack(entity.position, { name = name, count = count - inserted, health = health }, true)
                end
            end
        end
        return new_stacks[1] and new_stacks[1].name and true
    end
end

local function insert_into_entity(entity, item_stacks)
    if not (entity and entity.valid) then return {} end
    item_stacks = item_stacks or {}
    if item_stacks and item_stacks.name then
        item_stacks = { item_stacks }
    end
    local new_stacks = {}
    for _, stack in pairs(item_stacks) do
        local name, count, health = stack.name, stack.count, stack.health or 1
        local inserted = entity.insert(stack)
        if inserted ~= count then
            new_stacks[#new_stacks + 1] = { name = name, count = count - inserted, health = health }
        end
    end
    return new_stacks
end

local function get_all_items_on_ground(entity, existing_stacks)
    if not SafeEntity.is_valid(entity) then return existing_stacks or {} end
    local item_stacks = existing_stacks or {}
    
    -- v5.1: Безопасное получение всех свойств через SafeEntity
    local surface = SafeEntity.get_surface(entity)
    local position = SafeEntity.get_position(entity, {x=0, y=0})
    
    -- Безопасное получение ghost_prototype
    local ghost_proto = SafeEntity.get_property(entity, "ghost_prototype")
    local bounding_box = (ghost_proto and ghost_proto.selection_box) or {{-1,-1},{1,1}}
    
    if not surface then return item_stacks end
    
    local area = Area.offset(bounding_box, position)

    -- Безопасный поиск предметов на земле
    local success, items = pcall(function()
        return surface.find_entities_filtered { name = 'item-on-ground', area = area }
    end)
    
    if success and items then
        for _, item_on_ground in pairs(items) do
            if item_on_ground.valid then
                pcall(function()
                    item_stacks[#item_stacks + 1] = {
                        name = item_on_ground.stack.name,
                        count = item_on_ground.stack.count,
                        health = item_on_ground.health or 1
                    }
                    item_on_ground.destroy()
                end)
            end
        end
    end

    -- Безопасный поиск предметов в манипуляторах
    local inserter_area = Area.expand(area, 3)
    success, items = pcall(function()
        return surface.find_entities_filtered { area = inserter_area, type = 'inserter' }
    end)
    
    if success and items then
        for _, inserter in pairs(items) do
            if inserter.valid then
                pcall(function()
                    local stack = inserter.held_stack
                    if stack.valid_for_read and Position.inside(inserter.held_stack_position, area) then
                        item_stacks[#item_stacks + 1] = { 
                            name = stack.name, 
                            count = stack.count, 
                            health = stack.health or 1 
                        }
                        stack.clear()
                    end
                end)
            end
        end
    end

    return (item_stacks[1] and item_stacks) or {}
end

local function get_items_from_inv(entity, item_stack, cheat, at_least_one)
    if cheat then
        return { name = item_stack.name, count = item_stack.count, health = 1, quality = item_stack.quality }
    end

    local sources = {}
    if entity.vehicle and entity.vehicle.valid and entity.vehicle.train then
        sources = entity.vehicle.train.cargo_wagons or {}
        if entity.character and entity.character.valid then
            sources[#sources + 1] = entity.character
        end
    elseif entity.vehicle and entity.vehicle.valid then
        sources = { entity.vehicle }
        if entity.character and entity.character.valid then
            sources[#sources + 1] = entity.character
        end
    elseif entity.character and entity.character.valid then
        sources = { entity.character }
    end

    local new_item_stack = { name = item_stack.name, count = 0, health = 1, quality = item_stack.quality }
    local count = item_stack.count
    local required_quality = item_stack.quality or "normal"

    for _, source in pairs(sources) do
        if source and source.valid then
            for _, inv in pairs(inv_list) do
                local inventory = source.get_inventory(inv)
                if inventory and inventory.valid then
                    -- Проверяем наличие предмета с нужным качеством
                    local item_count = inventory.get_item_count({ name = item_stack.name, quality = required_quality })
                    if item_count > 0 then
                        -- v5.8.0: Manual iteration but without pcall overhead
                        for i = 1, #inventory do
                            local stack = inventory[i]
                            if stack.valid_for_read and stack.name == item_stack.name then
                                local stack_quality = "normal"
                                if stack.quality and stack.quality.name then
                                    stack_quality = stack.quality.name
                                end
                                
                                if stack_quality == required_quality then
                                    local removed = math.min(stack.count, count)
                                    new_item_stack.count = new_item_stack.count + removed
                                    new_item_stack.health = new_item_stack.health * stack.health
                                    stack.count = stack.count - removed
                                    count = count - removed
                                    if new_item_stack.count == item_stack.count then
                                        return new_item_stack
                                    end
                                    if count <= 0 then
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if entity.is_player() then
        local stack = entity.cursor_stack
        if stack and stack.valid_for_read and stack.name == item_stack.name then
            -- v5.8.0: Прямой доступ к quality без pcall
            local cursor_quality = "normal"
            if stack.quality and stack.quality.name then
                cursor_quality = stack.quality.name
            end
            
            if cursor_quality == required_quality then
                local removed = math.min(stack.count, count)
                new_item_stack.count = new_item_stack.count + removed
                new_item_stack.health = new_item_stack.health * stack.health
                stack.count = stack.count - count
            end
        end
    end

    if new_item_stack.count == item_stack.count then
        return new_item_stack
    elseif new_item_stack.count > 0 and at_least_one then
        return new_item_stack
    else
        return nil
    end
end

-- ammo drain
local function ammo_drain(player, ammo, amount)
    if not (player and player.valid) then return false end
    if player.cheat_mode then return true end
    if not (ammo and ammo.valid_for_read) then return false end

    amount = amount or 1
    
    -- v5.8.0: Прямой доступ без pcall
    local name = ammo.name
    if not name then return false end
    
    ammo.drain_ammo(amount)

    if not ammo.valid_for_read then
        local inv = player.get_main_inventory()
        if inv and inv.valid then
            local new = inv.find_item_stack(name)
            if new then
                ammo.set_stack(new)
                new.clear()
            end
        end
    end
    return true
end

local function get_ammo_radius(player, nano_ammo)
    if not (player and player.valid) then return 7 end
    storage.players = storage.players or {}
    local data = storage.players[player.index] or {}
    data.ranges = data.ranges or {}
    storage.players[player.index] = data

    -- v5.8.0: Прямой доступ к ammo_category без pcall
    local modifier = 0
    if nano_ammo and nano_ammo.prototype and nano_ammo.prototype.ammo_category then
        modifier = player.force.get_ammo_damage_modifier(nano_ammo.prototype.ammo_category.name) or 0
    end
    
    local base_radius = bot_radius[modifier] or 7
    
    -- v5.2: Применяем бонус качества к радиусу
    local _, quality_multiplier = QualitySystem.get_ammo_quality(player, nano_ammo)
    local max_radius = QualitySystem.apply_quality_to_radius(base_radius, quality_multiplier)
    
    -- v5.8.0: Прямой доступ к имени ammo
    local ammo_name = nano_ammo and nano_ammo.valid_for_read and nano_ammo.name or nil
    
    local custom_radius = ammo_name and data.ranges[ammo_name]
    if type(custom_radius) ~= 'number' then
        custom_radius = max_radius
    end
    return custom_radius <= max_radius and custom_radius or max_radius
end

-- Repair pack handling (direct durability hot path)
local REPAIR_PACK_NAME = 'repair-pack'
local REPAIR_PACK_MAX_DUR = 300

local function find_repair_pack_stack(player)
    if not (player and player.valid) then return nil end

    if player.character and player.character.valid then
        local inv = player.get_main_inventory()
        if inv and inv.valid then
            local st = inv.find_item_stack(REPAIR_PACK_NAME)
            if st and st.valid_for_read then return st end
        end
    end

    local vehicle = player.vehicle
    if vehicle and vehicle.valid then
        local trunk = vehicle.get_inventory(defines.inventory.car_trunk)
        if trunk and trunk.valid then
            local st = trunk.find_item_stack(REPAIR_PACK_NAME)
            if st and st.valid_for_read then return st end
        end

        local train = vehicle.train
        if train then
            for _, wagon in pairs(train.cargo_wagons or {}) do
                if wagon.valid then
                    local winv = wagon.get_inventory(defines.inventory.cargo_wagon)
                    if winv and winv.valid then
                        local st = winv.find_item_stack(REPAIR_PACK_NAME)
                        if st and st.valid_for_read then return st end
                    end
                end
            end
        end
    end

    return nil
end

local function has_repair_tool(player)
    if not (player and player.valid) then return false end
    if player.cheat_mode then return true end
    return find_repair_pack_stack(player) ~= nil
end

local function use_repair_tool(player, want_hp)
    if not (player and player.valid) then return 0, false end
    if want_hp <= 0 then return 0, false end

    local per_action = (cfg and cfg.repair_hp_per_action) or 20
    want_hp = math.min(want_hp, per_action)

    if player.cheat_mode then
        return want_hp, false
    end

    local stack = find_repair_pack_stack(player)
    if not (stack and stack.valid_for_read) then
        return 0, false
    end

    local dur = stack.durability
    if type(dur) ~= "number" then
        return 0, false
    end

    if dur <= 0 then
        if stack.count > 1 then
            stack.count = stack.count - 1
            stack.durability = REPAIR_PACK_MAX_DUR
        else
            stack.clear()
        end
        nlog_agg("Израсходован ремкомплект", REPAIR_PACK_NAME)
        return 0, true
    end

    local repaired = math.min(want_hp, dur)
    local new_dur = dur - repaired

    if new_dur <= 0 then
        if stack.count > 1 then
            stack.count = stack.count - 1
            stack.durability = REPAIR_PACK_MAX_DUR
        else
            stack.clear()
        end
        nlog_agg("Израсходован ремкомплект", REPAIR_PACK_NAME)
        return repaired, true
    else
        stack.durability = new_dur
        return repaired, false
    end
end

-- pending repairs
local function push_pending_repair(data, run_tick, need_ammo)
    storage.nano_repair_pending = storage.nano_repair_pending or {}
    storage.nano_repair_pending[#storage.nano_repair_pending + 1] = {
        data = data,
        tick = run_tick,
        need_ammo = need_ammo and true or false
    }
end

local function process_pending_repairs()
    local pending = storage.nano_repair_pending
    if not pending or #pending == 0 then return end
    storage.nano_repair_pending = {}

    for _, rec in ipairs(pending) do
        local data = rec.data
        local tick = rec.tick

        local entity = data and data.entity
        if not (entity and entity.valid) then
            if data and data.player_index and data.unit_number then
                end_session(data.player_index, data.unit_number)
            end
            goto continue
        end

        if not queue then goto continue end
        if queue:get_hash(entity) then goto continue end

        if rec.need_ammo then
            local player = game.get_player(data.player_index)
            if not (player and player.valid and player.character and player.character.valid) then
                if data and data.player_index and data.unit_number then
                    end_session(data.player_index, data.unit_number)
                end
                goto continue
            end
            if not (data.ammo and data.ammo.valid_for_read) then
                if data and data.player_index and data.unit_number then
                    end_session(data.player_index, data.unit_number)
                end
                goto continue
            end
            if not ammo_drain(player, data.ammo, 1) then
                if data and data.player_index and data.unit_number then
                    end_session(data.player_index, data.unit_number)
                end
                goto continue
            end
        end

        queue:insert(data, tick)
        ::continue::
    end
end

-- v5.0 NEW: Используем новый модуль ModuleRequests вместо старой функции
-- Старая функция satisfy_requests_impl удалена - теперь используется безопасный модуль
local function satisfy_requests(requests, entity, player)
    return ModuleRequests.satisfy_requests(requests, entity, player)
end

local function create_projectile(name, surface, force, source, target, speed)
    speed = speed or 1
    force = force or 'player'
    if surface and surface.valid then
        surface.create_entity { name = name, force = force, position = source, target = target, speed = speed }
    end
end

-- Queue actions (same as before) + Repair uses nano-projectile-repair
function Queue.cliff_deconstruction(data)
    local entity, player = data.entity, game.get_player(data.player_index)
    if not (player and player.valid) then return end
    if not (player.character and player.character.valid) then
        return insert_or_spill_items(player, { data.item_stack })
    end
    
    -- v5.1: Безопасная проверка entity
    if not SafeEntity.is_valid(entity) then
        return insert_or_spill_items(player, { data.item_stack })
    end
    
    local should_deconstruct = false
    pcall(function()
        should_deconstruct = entity.to_be_deconstructed()
    end)
    
    if not should_deconstruct then
        return insert_or_spill_items(player, { data.item_stack })
    end

    -- v5.1: Безопасное получение свойств для projectile
    local entity_surface = SafeEntity.get_surface(entity)
    local entity_force = SafeEntity.get_property(entity, "force")
    local entity_pos = SafeEntity.get_position(entity)
    local player_pos = SafeEntity.get_position(player.character)
    
    if entity_surface and entity_pos and player_pos then
        create_projectile('nano-projectile-deconstructors', entity_surface, entity_force, player_pos, entity_pos)
        
        local exp_name = data.item_stack.name == 'artillery-shell' and 'big-artillery-explosion' or 'big-explosion'
        pcall(function()
            entity_surface.create_entity { name = exp_name, position = entity_pos }
        end)
    end
    
    SafeEntity.destroy(entity, { do_cliff_correction = true, raise_destroy = true })
    nlog_agg("Снесено скал", "cliff")
end

function Queue.deconstruction(data)
    local entity = data.entity
    local player = game.get_player(data.player_index)
    if not (player and player.valid) then return end
    if not (player.character and player.character.valid) then return end
    if not SafeEntity.is_valid(entity) then return end
    
    -- Проверяем to_be_deconstructed через pcall
    local should_deconstruct = false
    pcall(function()
        should_deconstruct = entity.to_be_deconstructed()
    end)
    if not should_deconstruct then return end

    -- v5.0: Сохраняем всё через SafeEntity ДО потенциального уничтожения
    local entity_name = SafeEntity.get_name(entity, "unknown")
    local surface = data.surface or SafeEntity.get_surface(entity)
    local force = SafeEntity.get_property(entity, "force")
    local ppos = SafeEntity.get_position(player.character)
    local epos = SafeEntity.get_position(entity)
    
    if not surface then return end

    create_projectile('nano-projectile-deconstructors', surface, force, ppos, epos)
    create_projectile('nano-projectile-return', surface, force, epos, ppos)

    if entity_name == 'deconstructible-tile-proxy' then
        local tile = surface.get_tile(epos)
        if tile then
            local tile_name = SafeEntity.get_name(tile, "unknown")
            player.mine_tile(tile)
            if SafeEntity.is_valid(entity) then 
                SafeEntity.destroy(entity)
            end
            nlog_agg("Снесено плиток", tile_name)
        end
    else
        -- ВАЖНО: после mine_entity() entity может стать invalid
        player.mine_entity(entity)
        nlog_agg("Снесено", entity_name)
    end
end

function Queue.build_entity_ghost(data)
    local ghost = data.entity
    local player = game.get_player(data.player_index)
    local surface = data.surface
    local position = data.position

    if not (player and player.valid) then return end
    if not (player.character and player.character.valid) then
        return insert_or_spill_items(player, { data.item_stack }, player.cheat_mode)
    end
    
    -- v5.0: Проверка ghost через SafeEntity
    if not SafeEntity.is_valid(ghost) then
        return insert_or_spill_items(player, { data.item_stack }, player.cheat_mode)
    end
    
    local ghost_name = SafeEntity.get_property(ghost, "ghost_name")
    if ghost_name ~= data.entity_name then
        return insert_or_spill_items(player, { data.item_stack }, player.cheat_mode)
    end

    local item_stacks = get_all_items_on_ground(ghost)
    
    -- v5.0: Безопасное получение свойств для can_place_entity
    local ghost_pos = SafeEntity.get_position(ghost)
    local ghost_dir = SafeEntity.get_property(ghost, "direction")
    local ghost_force = SafeEntity.get_property(ghost, "force")
    
    if not player.character.surface.can_place_entity { 
        name = ghost_name, 
        position = ghost_pos, 
        direction = ghost_dir, 
        force = ghost_force 
    } then
        return insert_or_spill_items(player, { data.item_stack }, player.cheat_mode)
    end

    -- v5.0: Безопасный revive
    local revived, entity, requests = SafeEntity.revive(ghost, { return_item_request_proxy = true, raise_revive = true })
    if not revived then
        return insert_or_spill_items(player, { data.item_stack }, player.cheat_mode)
    end

    if not SafeEntity.is_valid(entity) then
        if insert_or_spill_items(player, item_stacks, player.cheat_mode) then
            create_projectile('nano-projectile-return', surface, player.force, position, player.character.position)
        end
        return
    end

    -- v5.0: Безопасное создание projectile и установка health
    local entity_surface = SafeEntity.get_surface(entity)
    local entity_force = SafeEntity.get_property(entity, "force")
    local entity_pos = SafeEntity.get_position(entity)
    
    if entity_surface then
        create_projectile('nano-projectile-constructors', entity_surface, entity_force, player.character.position, entity_pos)
    end
    
    -- Безопасная установка здоровья
    pcall(function()
        local current_health = entity.health
        local max_health = entity.max_health
        if current_health and max_health and current_health > 0 then
            entity.health = (data.item_stack.health or 1) * max_health
        end
    end)

    if insert_or_spill_items(player, insert_into_entity(entity, item_stacks)) then
        create_projectile('nano-projectile-return', surface, player.force, position, player.character.position)
    end

    nlog_agg("Построено", data.entity_name)

    if requests and requests.valid and SafeEntity.is_valid(entity) then
        satisfy_requests(requests, entity, player)
    end
end

function Queue.build_tile_ghost(data)
    local ghost = data.entity
    local player = game.get_player(data.player_index)
    local surface = data.surface
    local position = data.position

    if not (player and player.valid) then return end
    if not (player.character and player.character.valid) then
        return insert_or_spill_items(player, { data.item_stack })
    end
    if not SafeEntity.is_valid(ghost) then
        return insert_or_spill_items(player, { data.item_stack })
    end

    local tile, hidden_tile = surface.get_tile(position), surface.get_hidden_tile(position)
    
    -- v5.1: Безопасное получение force
    local force = SafeEntity.get_property(ghost, "force")
    
    local tile_was_mined = hidden_tile and tile.prototype.can_be_part_of_blueprint and player.mine_tile(tile)
    local ghost_was_revived = SafeEntity.is_valid(ghost) and SafeEntity.revive(ghost, { raise_revive = true })
    
    if not (tile_was_mined or ghost_was_revived) then
        return insert_or_spill_items(player, { data.item_stack })
    end

    local item_ptype = data.item_stack and prototypes.item[data.item_stack.name]
    local tile_ptype = item_ptype and item_ptype.place_as_tile_result and item_ptype.place_as_tile_result.result
    
    local player_pos = SafeEntity.get_position(player.character)
    if player_pos then
        create_projectile('nano-projectile-constructors', surface, force, player_pos, position)
    end

    Position.floored(position)
    if tile_was_mined and not ghost_was_revived and tile_ptype then
        if player_pos then
            create_projectile('nano-projectile-return', surface, force, position, player_pos)
        end
        pcall(function()
            surface.set_tiles({ { name = tile_ptype.name, position = position } }, true, true, false, true)
        end)
    end
    
    pcall(function()
        surface.play_sound { path = 'nano-sound-build-tiles', position = position }
    end)

    local tile_name = tile_ptype and tile_ptype.name or (data.item_stack and data.item_stack.name) or "unknown"
    nlog_agg("Уложено плиток", tile_name)
end

function Queue.upgrade_direction(data)
    local ghost = data.entity
    local player = game.get_player(data.player_index)
    local surface = data.surface
    if not (player and player.valid) then return end
    if not (player.character and player.character.valid) then return end
    
    -- v5.1: Безопасная проверка ghost
    if not SafeEntity.is_valid(ghost) then return end
    
    local should_upgrade = false
    pcall(function()
        should_upgrade = ghost.to_be_upgraded()
    end)
    if not should_upgrade then return end

    -- v5.1: Безопасное изменение направления
    pcall(function()
        ghost.direction = data.direction
        ghost.cancel_upgrade(player.force, player)
    end)
    
    local ghost_surface = SafeEntity.get_surface(ghost)
    local ghost_force = SafeEntity.get_property(ghost, "force")
    local ghost_pos = SafeEntity.get_position(ghost)
    local ghost_name = SafeEntity.get_name(ghost, "unknown")
    local player_pos = SafeEntity.get_position(player.character)
    
    if ghost_surface and ghost_pos and player_pos then
        create_projectile('nano-projectile-constructors', ghost_surface, ghost_force, player_pos, ghost_pos)
        pcall(function()
            surface.play_sound { path = 'utility/build_small', position = ghost_pos }
        end)
    end
    
    nlog_agg("Повернуто", ghost_name)
end

function Queue.upgrade_ghost(data)
    local ghost = data.entity
    local player = game.get_player(data.player_index)
    local surface = data.surface
    local position = data.position

    if not (player and player.valid) then return end
    if not (player.character and player.character.valid) then
        return insert_or_spill_items(player, { data.item_stack })
    end
    if not (ghost and ghost.valid) then
        return insert_or_spill_items(player, { data.item_stack })
    end

    local old_name = ghost.name
    local new_name = data.entity_name or data.item_stack.name

    local entity = surface.create_entity {
        name = new_name,
        direction = ghost.direction,
        force = ghost.force,
        position = position,
        fast_replace = true,
        player = player,
        type = ghost.type == 'underground-belt' and ghost.belt_to_ground_type or nil,
        raise_built = true
    }
    if not entity then
        return insert_or_spill_items(player, { data.item_stack })
    end

    create_projectile('nano-projectile-constructors', entity.surface, entity.force, player.character.position, entity.position)
    surface.play_sound { path = 'utility/build_small', position = entity.position }
    entity.health = (entity.health > 0) and ((data.item_stack.health or 1) * entity.max_health)

    nlog_agg("Апгрейд " .. old_name .. " →", new_name)
end

function Queue.item_requests(data)
    local proxy = data.entity
    local player = game.get_player(data.player_index)
    if not player or not player.valid then return end
    if not player.character or not player.character.valid then return end
    if not SafeEntity.is_valid(proxy) then return end

    -- v5.1: Безопасное получение proxy_target
    local target = nil
    pcall(function()
        target = proxy.proxy_target
    end)
    
    if not SafeEntity.is_valid(target) then return end
    
    local target_name = SafeEntity.get_name(target, "unknown")
    
    -- v5.4.4: Определяем тип запроса для корректного логирования
    local request_type = "модулей"
    if SafeEntity.has_burner(target) then
        request_type = "топлива"
    elseif SafeEntity.has_ammo_inventory(target) then
        request_type = "боеприпасов"
    end
    
    nlog("🎯 Обработка запроса " .. request_type .. " для: " .. target_name)

    local ok = satisfy_requests(proxy, target, player)
    if ok and player.character and player.character.valid then
        -- v5.1: Безопасное создание projectile
        local proxy_surface = SafeEntity.get_surface(proxy)
        local proxy_force = SafeEntity.get_property(proxy, "force")
        local proxy_pos = SafeEntity.get_position(proxy)
        local player_pos = SafeEntity.get_position(player.character)
        
        if proxy_surface and proxy_pos and player_pos then
            create_projectile('nano-projectile-constructors', proxy_surface, proxy_force, player_pos, proxy_pos)
        end
    end
end

-- Repair action (UPDATED projectile name)
function Queue.repair(data)
    local entity = data.entity
    local player = game.get_player(data.player_index)

    if not (player and player.valid) then
        if data and data.player_index and data.unit_number then end_session(data.player_index, data.unit_number) end
        return
    end
    if not (player.character and player.character.valid) then
        if data and data.player_index and data.unit_number then end_session(data.player_index, data.unit_number) end
        return
    end
    if not SafeEntity.is_valid(entity) then
        if data and data.player_index and data.unit_number then end_session(data.player_index, data.unit_number) end
        return
    end
    if not cfg.do_repair then
        if data and data.player_index and data.unit_number then end_session(data.player_index, data.unit_number) end
        return
    end

    if data.unit_number then
        touch_session(data.player_index, data.unit_number)
    end

    -- v5.1: Безопасное получение health ratio
    local ratio = SafeEntity.get_health_ratio(entity, 1)
    if ratio >= 1 then
        if data and data.player_index and data.unit_number then end_session(data.player_index, data.unit_number) end
        return
    end

    local ammo = data.ammo
    if not (ammo and ammo.valid_for_read) then
        if data and data.player_index and data.unit_number then end_session(data.player_index, data.unit_number) end
        return
    end

    if cfg.network_limits and not nano_network_check(player.character, entity) then
        return
    end

    local radius = get_ammo_radius(player, ammo)
    
    -- v5.1: Безопасное получение позиций для проверки радиуса
    local player_pos = SafeEntity.get_position(player.character, {x=0, y=0})
    local entity_pos = SafeEntity.get_position(entity, {x=0, y=0})
    local dx = player_pos.x - entity_pos.x
    local dy = player_pos.y - entity_pos.y
    if (dx * dx + dy * dy) > (radius * radius) then
        return
    end

    -- v5.1: Безопасное получение health
    local max_health = SafeEntity.get_property(entity, "max_health", 100)
    local current_health = SafeEntity.get_property(entity, "health", 0)
    local damage = max_health - current_health
    if damage <= 0 then
        if data and data.player_index and data.unit_number then end_session(data.player_index, data.unit_number) end
        return
    end

    local repaired, pack_exhausted = use_repair_tool(player, damage)
    if repaired <= 0 and not pack_exhausted then
        return
    end

    -- IMPORTANT: repair uses nano-projectile-repair now
    if data.repair_shot and repaired > 0 then
        local surface = data.surface or SafeEntity.get_surface(entity)
        local force = SafeEntity.get_property(entity, "force")
        
        if surface and player_pos and entity_pos then
            create_projectile('nano-projectile-repair', surface, force, player_pos, entity_pos)
            pcall(function()
                surface.play_sound { path = 'utility/build_small', position = entity_pos }
            end)
        end
    end

    if repaired > 0 then
        pcall(function()
            entity.health = math.min(max_health, current_health + repaired)
        end)
        nlog_agg("Отремонтировано", SafeEntity.get_name(entity, "unknown"))
    end

    if not (SafeEntity.is_valid(entity) and SafeEntity.get_health_ratio(entity, 1) < 1) then
        if data and data.player_index and data.unit_number then end_session(data.player_index, data.unit_number) end
        return
    end

    if not has_repair_tool(player) then
        return
    end

    local delay = (cfg and cfg.repair_requeue_delay) or 20

    local nd = {
        player_index = data.player_index,
        ammo         = ammo,
        position     = entity.position,
        surface      = entity.surface,
        unit_number  = data.unit_number or entity.unit_number,
        entity       = entity,
        action       = 'repair'
    }

    if pack_exhausted then
        nd.repair_shot = true
        push_pending_repair(nd, game.tick + delay, true)
    else
        nd.repair_shot = false
        push_pending_repair(nd, game.tick + delay, false)
    end
end

-- Trees (termite ammo)
local function everyone_hates_trees(player, pos, nano_ammo)
    local radius = get_ammo_radius(player, nano_ammo)
    local force = player.force

    for _, stupid_tree in pairs(player.character.surface.find_entities_filtered { position = pos, radius = radius, type = 'tree', limit = 200 }) do
        if nano_ammo.valid and nano_ammo.valid_for_read then
            if not stupid_tree.to_be_deconstructed() then
                local tree_area = Area.expand(stupid_tree.bounding_box, .5)
                if player.character.surface.count_entities_filtered { area = tree_area, name = 'nano-cloud-small-termites' } == 0 then
                    player.character.surface.create_entity {
                        name = 'nano-projectile-termites',
                        position = player.character.position,
                        force = force,
                        target = stupid_tree,
                        speed = .5
                    }
                    ammo_drain(player, nano_ammo, 1)
                    nlog_agg("Атаковано деревьев", "tree")
                end
            end
        else
            break
        end
    end
end

-- Execute item
function Queue.execute_item(data)
    if data.action == 'cliff_deconstruction' then
        Queue.cliff_deconstruction(data)
    elseif data.action == 'deconstruction' then
        Queue.deconstruction(data)
    elseif data.action == 'build_entity_ghost' then
        Queue.build_entity_ghost(data)
    elseif data.action == 'build_tile_ghost' then
        Queue.build_tile_ghost(data)
    elseif data.action == 'upgrade_direction' then
        Queue.upgrade_direction(data)
    elseif data.action == 'upgrade_ghost' then
        Queue.upgrade_ghost(data)
    elseif data.action == 'item_requests' then
        Queue.item_requests(data)
    elseif data.action == 'repair' then
        Queue.repair(data)
    end
end

-- Scan in range: repairs + ghosts/deconstruct/upgrades
local function queue_ghosts_in_range(player, pos, nano_ammo)
    storage.players = storage.players or {}
    local pdata = storage.players[player.index] or {}
    storage.players[player.index] = pdata

    local force = player.force
    local _next_nano_tick =
        (pdata._next_nano_tick and pdata._next_nano_tick < (game.tick + 2000) and pdata._next_nano_tick) or game.tick

    -- v5.2: Применяем бонус качества оружия к скорости
    local _, gun_quality_bonus = QualitySystem.get_gun_quality(player)
    local base_speed_bonus = queue_speed[force.get_gun_speed_modifier('nano-ammo')] or queue_speed[4]
    local speed_bonus = QualitySystem.apply_quality_to_speed(base_speed_bonus, gun_quality_bonus)
    
    local tick_spacing = max(1, cfg.queue_rate - speed_bonus)

    local next_tick, queue_count = queue:next(_next_nano_tick, tick_spacing)
    local radius = get_ammo_radius(player, nano_ammo)
    local area = Position.expand_to_area(pos, radius)

    -- Repairs optimized scan
    if cfg.do_repair then
        ensure_throttle()

        -- v5.4.1: PERFORMANCE - Player-level repair scan throttling
        -- Не сканируем ремонты чаще чем раз в REPAIR_SCAN_THROTTLE_TICKS
        pdata.last_repair_scan_tick = pdata.last_repair_scan_tick or 0
        local repair_scan_interval = CONSTANTS.REPAIR_SCAN_THROTTLE_TICKS
        
        if (game.tick - pdata.last_repair_scan_tick) < repair_scan_interval then
            -- Слишком рано для нового сканирования, пропускаем
            goto skip_repair_scan
        end
        
        pdata.last_repair_scan_tick = game.tick

        local in_combat = is_player_in_combat(player)
        local use_priority_filter = (in_combat and cfg.repair_combat_important_only)

        if has_repair_tool(player) then
            -- В режиме боя - используем приоритетный список типов
            -- Вне боя - сканируем ВСЁ, что можно ремонтировать
            local filter_params = { area = area, force = force, limit = 400 }
            
            if use_priority_filter then
                -- Режим боя: только важные типы
                filter_params.type = cfg.repair_scan_types_combat
            end
            -- Вне боя: фильтр по типу НЕ добавляется, сканируем всё
            
            local candidates = player.character.surface.find_entities_filtered(filter_params)

            local list = {}

            for _, entity in pairs(candidates) do
                if nano_repairable_entity(entity) then
                    local ratio_e = entity.get_health_ratio() or 1
                    if ratio_e < (cfg.repair_threshold or 0.95) then
                        local unit = entity.unit_number
                        if unit then
                            local last = storage.repair_last_scan_tick[unit]
                            local throttle = cfg.repair_throttle_ticks or 0
                            if (not last) or throttle <= 0 or (game.tick - last) >= throttle then
                                storage.repair_last_scan_tick[unit] = game.tick

                                local already_session = session_active(player.index, unit)
                                local can_start = (not already_session) and can_start_new_session(player.index)

                                if already_session or can_start then
                                    if not queue:get_hash(entity) then
                                        local pr = get_repair_priority(entity)
                                        -- В бою проверяем приоритет, вне боя - ремонтируем всё
                                        if not use_priority_filter or pr <= 40 then
                                            list[#list + 1] = {
                                                entity = entity,
                                                unit = unit,
                                                pr = pr,
                                                ratio = ratio_e,
                                                start_new = (not already_session)
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            lua_table_sort(list, function(a, b)
                if a.pr ~= b.pr then return a.pr < b.pr end
                return a.ratio < b.ratio
            end)

            for i = 1, #list do
                if queue_count() >= cfg.queue_cycle then break end
                if not (nano_ammo.valid and nano_ammo.valid_for_read) then break end

                local rec = list[i]
                local entity = rec.entity
                if not (entity and entity.valid) then goto continue_repair_loop end
                if queue:get_hash(entity) then goto continue_repair_loop end

                if rec.start_new then
                    if not can_start_new_session(player.index) then break end
                    local data = {
                        player_index = player.index,
                        ammo = nano_ammo,
                        position = entity.position,
                        surface = entity.surface,
                        unit_number = rec.unit,
                        entity = entity,
                        action = 'repair',
                        repair_shot = true
                    }
                    queue:insert(data, next_tick())
                    ammo_drain(player, nano_ammo, 1)
                    start_session(player.index, rec.unit)
                else
                    local data = {
                        player_index = player.index,
                        ammo = nano_ammo,
                        position = entity.position,
                        surface = entity.surface,
                        unit_number = rec.unit,
                        entity = entity,
                        action = 'repair',
                        repair_shot = false
                    }
                    queue:insert(data, next_tick())
                end

                ::continue_repair_loop::
            end
        end
    end
    
    ::skip_repair_scan::  -- v5.4.1: Label for repair scan throttling

    -- v5.4.3: Ghost scan throttling REMOVED
    -- Причина: item-request-proxy обрабатывается внутри ghost loop
    -- Throttling блокировал важные запросы топлива/модулей для машин
    -- Ghost scan достаточно быстрый, не требует агрессивного throttling

    -- Ghosts/deconstruct/upgrades scan (FIXED invalid access)
    for _, ghost in pairs(player.character.surface.find_entities(area)) do
        if not (ghost and ghost.valid) then
            goto continue_ghost_loop
        end

        local same_force = ghost.force == force
        local deconstruct = ghost.to_be_deconstructed()
        local upgrade = ghost.to_be_upgraded() and ghost.force == force

        if not (deconstruct or upgrade or same_force) then
            goto continue_ghost_loop
        end

        -- log only after valid check
        nlog_agg("Сканирование призраков", ghost.name)

        if not (nano_ammo.valid and nano_ammo.valid_for_read) then
            break
        end

        if cfg.network_limits and not nano_network_check(player.character, ghost) then
            goto continue_ghost_loop
        end

        if queue_count() >= cfg.queue_cycle then
            break
        end

        if queue:get_hash(ghost) then
            goto continue_ghost_loop
        end

        local data = {
            player_index = player.index,
            ammo        = nano_ammo,
            position    = ghost.position,
            surface     = ghost.surface,
            unit_number = ghost.unit_number,
            entity      = ghost
        }

        if ghost.name == 'item-request-proxy' and cfg.do_proxies then
            data.action = 'item_requests'
            data.target = ghost.proxy_target
            queue:insert(data, next_tick())
            ammo_drain(player, nano_ammo, 1)
            goto continue_ghost_loop
        end

        if deconstruct then
            if ghost.type == 'cliff' then
                if player.force.technologies['nanobots-cliff'].researched then
                    local item_stack = local_find_item(explosives, player, false)
                    if item_stack then
                        local explosive = get_items_from_inv(player, item_stack, player.cheat_mode)
                        if explosive then
                            data.item_stack = explosive
                            data.action = 'cliff_deconstruction'
                            queue:insert(data, next_tick())
                            ammo_drain(player, nano_ammo, 1)
                        end
                    end
                end
            elseif ghost.minable then
                data.action = 'deconstruction'
                data.deconstructors = true
                queue:insert(data, next_tick())
                ammo_drain(player, nano_ammo, 1)
            end
        elseif upgrade then
            -- Factorio 2.0: get_upgrade_target() returns prototype, quality
            local prototype, upgrade_quality = ghost.get_upgrade_target()
            if prototype then
                if prototype.name == ghost.name then
                    -- Factorio 2.0: get_upgrade_direction() removed
                    -- Try to get upgrade direction, skip if not available
                    local ok, dir = pcall(function() return ghost.direction end)
                    -- Direction-only upgrades are handled natively in 2.0
                    -- Just skip this case — robots/player handle rotation
                else
                    local item_stack = local_find_item(prototype.items_to_place_this, player, false)
                    if item_stack then
                        -- v5.8.0: Quality from get_upgrade_target() second return
                        local required_quality = (upgrade_quality and upgrade_quality.name) or "normal"
                        local required_stack = {
                            name = item_stack.name,
                            count = item_stack.count,
                            quality = required_quality
                        }
                        local place_item = get_items_from_inv(player, required_stack, player.cheat_mode)
                        if place_item then
                            data.action = 'upgrade_ghost'
                            data.entity_name = prototype.name
                            data.item_stack = place_item
                            queue:insert(data, next_tick())
                            ammo_drain(player, nano_ammo, 1)
                        end
                    end
                end
            end
        elseif ghost.name == 'entity-ghost' or (ghost.name == 'tile-ghost' and cfg.build_tiles) then
            local proto = ghost.ghost_prototype
            local item_stack = local_find_item(proto.items_to_place_this, player, false)
            if item_stack then
                if ghost.name == 'entity-ghost' then
                    -- v5.0: Используем SafeEntity для безопасного получения качества
                    local ghost_quality = SafeEntity.get_quality(ghost, "normal")
                    -- Создаем item_stack с нужным качеством
                    local required_stack = {
                        name = item_stack.name,
                        count = item_stack.count,
                        quality = ghost_quality
                    }
                    local place_item = get_items_from_inv(player, required_stack, player.cheat_mode)
                    if place_item then
                        data.action = 'build_entity_ghost'
                        data.entity_name = proto.name
                        data.item_stack = place_item
                        queue:insert(data, next_tick())
                        ammo_drain(player, nano_ammo, 1)
                    end
                elseif ghost.name == 'tile-ghost' then
                    local tile = ghost.surface.get_tile(ghost.position)
                    if tile then
                        local place_item = get_items_from_inv(player, item_stack, player.cheat_mode)
                        if place_item then
                            data.item_stack = place_item
                            data.action = 'build_tile_ghost'
                            queue:insert(data, next_tick())
                            ammo_drain(player, nano_ammo, 1)
                        end
                    end
                end
            end
        end

        ::continue_ghost_loop::
    end

    pdata._next_nano_tick = next_tick() or game.tick
end

-- on_tick (UNIFIED: poll_players + AutoDefense + visualization)
local function poll_players(event)
    flush_aggregated_messages()

    -- AutoDefense (protected - errors here should not block construction)
    pcall(AutoDefense.on_tick)

    -- AutoDefense GUI update (every 1 second)
    if event.tick % 60 == 0 then
        pcall(AutoDefense.update_open_guis)
    end

    if event.tick % max(1, floor(cfg.poll_rate / #game.connected_players)) == 0 then
        local last_player, player = next(game.connected_players, storage._last_player)
        if player and is_connected_player_ready(player) then
            if cfg.nanobots_auto and (not cfg.network_limits or nano_network_check(player.character)) then
                local gun, nano_ammo, ammo_name = get_gun_ammo_name(player, 'gun-nano-emitter')
                if gun then
                    if ammo_name == 'ammo-nano-constructors' then
                        queue_ghosts_in_range(player, player.character.position, nano_ammo)
                    elseif ammo_name == 'ammo-nano-termites' then
                        everyone_hates_trees(player, player.character.position, nano_ammo)
                    end
                end
            end
            if cfg.equipment_auto then
                armormods.prepare_chips(player)
            end
        end
        storage._last_player = last_player
    end

    queue:execute(event)
    process_pending_repairs()

    if event.tick % 60 == 0 then
        cleanup_sessions_all()
    end

    -- Visualization update (every 0.5 seconds)
    if event.tick % CONSTANTS.VISUALIZATION_UPDATE_TICKS == 0 then
        for _, player in pairs(game.connected_players) do
            if QualitySystem.is_visualization_enabled(player) then
                QualitySystem.update_radius_visualization(player)
            else
                storage.radius_rendering = storage.radius_rendering or {}
                local pdata = storage.radius_rendering[player.index]
                if pdata and pdata.circle_id then
                    QualitySystem.destroy_circle(pdata.circle_id)
                    pdata.circle_id = nil
                end
            end
        end
    end
end

Event.register(defines.events.on_tick, poll_players)

local function players_changed()
    storage._last_player = nil
end

Event.register({ defines.events.on_player_joined_game, defines.events.on_player_left_game }, players_changed)

-- init/load/reset
local function on_nano_init()
    storage.players = storage.players or {}
    storage.repair_sessions = storage.repair_sessions or {}
    storage.repair_last_scan_tick = storage.repair_last_scan_tick or {}
    storage.nano_repair_pending = storage.nano_repair_pending or {}

    storage.nano_queue = Queue()
    queue = storage.nano_queue

    nlog("🤖 Nanobots initialized")
end

Event.register(Event.core_events.init, on_nano_init)

local function on_nano_load()
    queue = Queue(storage.nano_queue)
end

Event.register(Event.core_events.load, on_nano_load)

local function reset_nano_queue()
    storage.nano_queue = nil
    queue = nil
    storage.nano_queue = Queue()
    queue = storage.nano_queue
    storage.nano_repair_pending = {}
    storage.repair_last_scan_tick = storage.repair_last_scan_tick or {}

    if storage.players then
        for _, p in pairs(storage.players) do
            if type(p) == "table" then
                p._next_nano_tick = 0
            end
        end
    end
end

Event.register(Event.generate_event_name('reset_nano_queue'), reset_nano_queue)

-- v5.2: Обработчики для визуализации радиуса
Event.register(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "nanobots-toggle-radius" then
        local player = game.get_player(event.player_index)
        if player and player.valid then
            local enabled = QualitySystem.toggle_radius_visualization(player)
            player.set_shortcut_toggled("nanobots-toggle-radius", enabled)
        end
    elseif event.prototype_name == "nanobots-toggle-auto-defense" then
        -- v5.5.0: Auto-Defense toggle
        local player = game.get_player(event.player_index)
        if player and player.valid then
            AutoDefense.toggle(player)
            local player_data = storage.auto_defense and storage.auto_defense[player.index]
            if player_data then
                player.set_shortcut_toggled("nanobots-toggle-auto-defense", player_data.enabled)
            end
        end
    end
end)

-- Обновление визуализации при смене оружия
Event.register(defines.events.on_player_cursor_stack_changed, function(event)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        -- v5.2.2: Обновляем только если визуализация включена
        if QualitySystem.is_visualization_enabled(player) then
            QualitySystem.update_radius_visualization(player)
        else
            -- Если отключена, убедимся что круг удалён
            storage.radius_rendering = storage.radius_rendering or {}
            local pdata = storage.radius_rendering[player.index]
            if pdata and pdata.circle_id then
                QualitySystem.destroy_circle(pdata.circle_id)
                pdata.circle_id = nil
            end
        end
    end
end)

-- v5.4.0: Visualization update moved into unified on_tick (poll_players)

-- Очистка при выходе игрока (сохраняем состояние для перезахода)
Event.register(defines.events.on_player_left_game, function(event)
    QualitySystem.on_player_left(event.player_index)
end)

-- Полное удаление данных при удалении игрока из игры
Event.register(defines.events.on_player_removed, function(event)
    QualitySystem.on_player_removed(event.player_index)
end)