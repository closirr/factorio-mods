-- Auto-Defense System MVP (v5.5.0)
-- Automatic turret ammunition delivery
-- v5.6.5: Performance optimizations for megabases

local AutoDefense = {}

-- Dependencies
local SafeEntity = require("scripts.safe_entity")
local QualitySystem = require("scripts.quality_system")
local config = require("config")

-- OPTIMIZATION: Local references to commonly used functions
local pairs = pairs
local ipairs = ipairs
local type = type
local math_floor = math.floor
local math_max = math.max
local math_ceil = math.ceil
local string_format = string.format
local string_match = string.match

-- ═══════════════════════════════════════════════════════════════════════════
-- DEBUG LOGGING
-- ═══════════════════════════════════════════════════════════════════════════

-- v5.8.0: Cached debug flag (updated in on_runtime_mod_setting_changed)
local debug_defense_enabled = false

local function update_debug_defense_flag()
    debug_defense_enabled = false
    if _G.DEBUG_NANO and _G.DEBUG_NANO >= 1 then
        if settings and settings.global then
            local setting = settings.global["nanobots-debug-defense-system"]
            if setting and setting.value then
                debug_defense_enabled = true
            end
        end
    end
end

-- Initialize on load
pcall(update_debug_defense_flag)

local function debug_log(player, message)
    if not debug_defense_enabled then return end
    if not player or not player.valid then return end
    player.print("[Auto-Defense DEBUG] " .. message, {r=1, g=0.5, b=0})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

local TURRET_PATTERNS = {
    "gun%-turret",
    "laser%-turret",
    "artillery%-turret",
    "turret$"  -- Match any *-turret
}

local SINGLE_SHOT_TURRETS = {
    ["artillery-turret"] = true,
}

-- v5.8.0: Module-level constants (avoid re-creation on each call)
local QUALITY_COLORS = {
    normal = {r = 1, g = 1, b = 1},
    uncommon = {r = 0.09, g = 0.75, b = 0.26},
    rare = {r = 0.17, g = 0.56, b = 1},
    epic = {r = 0.69, g = 0.18, b = 1},
    legendary = {r = 1, g = 0.63, b = 0.15}
}

local QUALITY_ORDER = {
    normal = 1,
    uncommon = 2,
    rare = 3,
    epic = 4,
    legendary = 5
}

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

function AutoDefense.init()
    -- Safety check: storage might not be ready yet
    if not storage then
        return
    end
    
    storage.auto_defense = storage.auto_defense or {}
    
    -- Safety check: game might not be ready yet
    if not game then
        return
    end
    
    for _, player in pairs(game.players) do
        AutoDefense.init_player(player)
    end
end

function AutoDefense.init_player(player)
    if not player or not player.valid then return end
    if not storage or not storage.auto_defense then 
        storage = storage or {}
        storage.auto_defense = storage.auto_defense or {}
    end
    
    local player_index = player.index
    
    storage.auto_defense[player_index] = storage.auto_defense[player_index] or {
        enabled = false,
        blacklist = {},
        last_scan_tick = 0,
        statistics = {
            turrets_rearmed = 0,
            total_ammo_delivered = 0,
            items_delivered = {},
            nano_charges_used = 0,
            session_start_tick = 0
        },
        -- v5.7.0: Cumulative stats (never reset)
        lifetime_stats = {
            turrets_rearmed = 0,
            total_ammo_delivered = 0,
            nano_charges_used = 0,
            sessions_count = 0
        },
        -- Performance cache
        cached_radius = nil,
        cached_radius_tick = 0,
        -- Warning throttling (per turret type)
        last_warnings = {},  -- [turret_name] = last_tick
        -- v5.7.0: Low nano ammo warning throttle
        last_low_nano_tick = nil,
        -- v5.7.0: GUI visibility
        gui_visible = false
    }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

-- v5.8.0: Using built-in table_size from Factorio 2.0
-- (removed custom table_size implementation)

local function table_keys(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, tostring(k)) end
    return keys
end

-- v5.8.0: Wrong ammo warning (throttled per player)
local wrong_ammo_warn_ticks = {}  -- [player_index] = last_warn_tick

local function warn_wrong_ammo(player, ammo_name)
    if not (player and player.valid) then return end
    local pi = player.index
    
    -- Get interval from setting (0 = disabled) — прямой доступ, т.к. get_player_setting ещё не определена
    local interval_str = "30"
    if player.mod_settings and player.mod_settings["nanobots-wrong-ammo-warning-interval"] then
        interval_str = player.mod_settings["nanobots-wrong-ammo-warning-interval"].value or "30"
    end
    local interval_sec = tonumber(interval_str) or 30
    if interval_sec <= 0 then return end  -- Disabled
    
    local interval_ticks = interval_sec * 60
    local current_tick = game.tick
    local last = wrong_ammo_warn_ticks[pi] or 0
    
    if (current_tick - last) < interval_ticks then return end
    wrong_ammo_warn_ticks[pi] = current_tick
    
    -- Get localized ammo name
    local ammo_locale = prototypes.item[ammo_name] and prototypes.item[ammo_name].localised_name or ammo_name
    
    pcall(function()
        player.create_local_flying_text({
            text = {"auto-defense.wrong-ammo", ammo_locale},
            position = player.character.position,
            color = {r = 1, g = 0.6, b = 0},
            time_to_live = 180,
            speed = 0.3
        })
    end)
end

local function get_nanobot_radius(player)
    -- Get player's current nano-emitter radius (same logic as nanobots.lua)
    -- Returns: radius, nano_ammo (ammo stack reference for drain)
    if not (player and player.valid and player.character and player.character.valid) then
        return 7, nil  -- Default fallback
    end
    
    local gun_inv = player.character.get_inventory(defines.inventory.character_guns)
    local ammo_inv = player.character.get_inventory(defines.inventory.character_ammo)
    if not (gun_inv and ammo_inv) then return 7, nil end
    
    -- Find nano-emitter
    local gun, ammo
    if not player.mod_settings['nanobots-active-emitter-mode'].value then
        local index
        gun, index = gun_inv.find_item_stack('gun-nano-emitter')
        ammo = gun and ammo_inv[index]
    else
        local index = player.character.selected_gun_index
        gun, ammo = gun_inv[index], ammo_inv[index]
        if not (gun and gun.valid_for_read and gun.name == 'gun-nano-emitter') then
            gun, ammo = nil, nil
        end
    end
    
    if not (gun and gun.valid_for_read and ammo and ammo.valid_for_read) then
        return 7, nil  -- No nano-emitter found
    end
    
    -- v5.8.0: Auto-defense работает ТОЛЬКО с конструкторами, НЕ с термитами
    local ammo_name = ammo.name
    if ammo_name ~= "ammo-nano-constructors" then
        -- Warn player about wrong ammo type (throttled)
        warn_wrong_ammo(player, ammo_name)
        return 7, nil  -- Wrong ammo type (termites, etc.)
    end
    
    -- v5.8.0: Use config.BOT_RADIUS instead of duplicated table; direct access without pcall
    local modifier = 0
    if ammo.prototype and ammo.prototype.ammo_category then
        modifier = player.force.get_ammo_damage_modifier(ammo.prototype.ammo_category.name) or 0
    end
    
    modifier = math_floor(modifier + 0.5)
    
    local base_radius = config.BOT_RADIUS[modifier] or 7
    
    -- Apply quality multiplier
    local _, quality_multiplier = QualitySystem.get_ammo_quality(player, ammo)
    local max_radius = QualitySystem.apply_quality_to_radius(base_radius, quality_multiplier)
    
    return max_radius, ammo
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SETTINGS HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

-- v5.8.0: Per-player settings cache (invalidated on setting change)
local player_settings_cache = {}  -- [player_index] = {[setting_name] = {value, tick}}
local PLAYER_SETTINGS_TTL = 300  -- Cache for 5 seconds

local function get_player_setting(player, name)
    if not player or not player.valid then return nil end
    
    local pi = player.index
    local cache = player_settings_cache[pi]
    if cache then
        local entry = cache[name]
        if entry and (game.tick - entry.tick) < PLAYER_SETTINGS_TTL then
            return entry.value
        end
    end
    
    if not player.mod_settings then return nil end
    local setting = player.mod_settings[name]
    if not setting then return nil end
    
    -- Cache the value
    if not cache then
        cache = {}
        player_settings_cache[pi] = cache
    end
    cache[name] = {value = setting.value, tick = game.tick}
    
    return setting.value
end

local function get_global_setting(name)
    if not settings or not settings.global then return nil end
    local setting = settings.global[name]
    if not setting then return nil end
    return setting.value
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SETTINGS CACHE (OPTIMIZATION)
-- ═══════════════════════════════════════════════════════════════════════════

local cached_global_settings = {
    scan_interval = 60,
    max_per_tick = 5
}

local function update_cached_global_settings()
    cached_global_settings.scan_interval = get_global_setting("nanobots-auto-defense-scan-interval") or 60
    cached_global_settings.max_per_tick = get_global_setting("nanobots-auto-defense-max-per-tick") or 5
end

-- Initialize cache on load
update_cached_global_settings()

-- ═══════════════════════════════════════════════════════════════════════════
-- ADAPTIVE SCAN INTERVAL
-- ═══════════════════════════════════════════════════════════════════════════

-- Enemy detection cache per player
local enemy_cache = {}  -- [player_index] = {enemies_nearby = bool, last_check_tick = 0}
local ENEMY_CHECK_INTERVAL = 180  -- Check enemies every 3 seconds
local COMBAT_SCAN_DIVISOR = 2     -- Scan 2x faster in combat

local function check_enemies_nearby(player, radius)
    if not (player and player.valid and player.character and player.character.valid) then
        return false
    end
    
    local pi = player.index
    local current_tick = game.tick
    local cache = enemy_cache[pi]
    
    if cache and (current_tick - cache.last_check_tick) < ENEMY_CHECK_INTERVAL then
        return cache.enemies_nearby
    end
    
    -- Check for enemies within extended area (square, 1.5x size)
    local search_size = radius * 1.5  -- Check slightly beyond turret range
    local pos = player.character.position
    local area = {{pos.x - search_size, pos.y - search_size}, {pos.x + search_size, pos.y + search_size}}
    local enemy_count = player.character.surface.count_entities_filtered({
        area = area,
        force = "enemy",
        limit = 1
    })
    
    local result = enemy_count > 0
    enemy_cache[pi] = {enemies_nearby = result, last_check_tick = current_tick}
    return result
end

local function get_effective_scan_interval(player, radius)
    local base_interval = cached_global_settings.scan_interval
    
    -- Check adaptive mode setting
    local adaptive = get_player_setting(player, "nanobots-auto-defense-adaptive-scan")
    if not adaptive then
        return base_interval
    end
    
    -- In combat: scan faster
    if check_enemies_nearby(player, radius) then
        return math_max(15, math_floor(base_interval / COMBAT_SCAN_DIVISOR))
    end
    
    -- Peaceful: scan slower
    return math_floor(base_interval * 1.5)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COMBAT MODE (auto-switch ammo priority)
-- ═══════════════════════════════════════════════════════════════════════════

local function get_effective_ammo_priorities(player, radius)
    local combat_mode = get_player_setting(player, "nanobots-auto-defense-combat-mode")
    
    -- Get player's manual settings (used in peace mode or when combat mode disabled)
    local type_priority = get_player_setting(player, "nanobots-auto-defense-ammo-type-priority") or "best-damage"
    local quality_priority = get_player_setting(player, "nanobots-auto-defense-ammo-quality-priority") or "best-quality"
    
    if combat_mode then
        local in_combat = check_enemies_nearby(player, radius)
        if in_combat then
            -- Combat: ALWAYS use best ammo (maximum effectiveness)
            return "best-damage", "best-quality"
        else
            -- Peace: use player's configured settings (economy mode)
            return type_priority, quality_priority
        end
    end
    
    -- Combat mode disabled: always use player settings
    return type_priority, quality_priority
end

local function parse_threshold_or_delivery(value_str)
    -- Parse "5" or "50%" into {type, value}
    if not value_str then
        return "absolute", 5  -- Safe default
    end
    
    if value_str:match("%%$") then
        local percent = tonumber(value_str:match("(%d+)%%"))
        return "percent", percent
    else
        return "absolute", tonumber(value_str)
    end
end

local function show_warning_if_needed(player, player_data, entity)
    -- Check if enough time passed since last warning FOR THIS SPECIFIC TURRET TYPE
    local warning_interval = player.mod_settings["nanobots-auto-defense-warning-interval"].value
    local interval_ticks = warning_interval * 60  -- Convert seconds to ticks
    local current_tick = game.tick
    
    -- Initialize warnings table if needed
    if not player_data.last_warnings then
        player_data.last_warnings = {}
    end
    
    -- Get turret name for throttling (e.g. "gun-turret", "rocket-turret", etc.)
    local turret_type = entity.name
    local last_warning_tick = player_data.last_warnings[turret_type] or 0
    
    -- Check if enough time passed
    if (current_tick - last_warning_tick) < interval_ticks then
        return  -- Too soon, don't spam
    end
    
    -- Get localized turret name
    local entity_proto = entity.prototype
    local turret_name = entity_proto and entity_proto.localised_name or entity.name
    
    -- Show warning with turret name
    player.print({"auto-defense.warning-no-ammo", turret_name}, {r=1, g=0.5, b=0})
    
    -- Update throttle for this specific turret type
    player_data.last_warnings[turret_type] = current_tick
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TURRET DETECTION (OPTIMIZED)
-- ═══════════════════════════════════════════════════════════════════════════

-- Known vanilla turrets for fast lookup
local KNOWN_TURRETS = {
    ["gun-turret"] = true,
    ["artillery-turret"] = true,
    ["flamethrower-turret"] = true,
    ["rocket-turret"] = true,
    ["railgun-turret"] = true,
}

-- Cache for modded turret names (built at runtime)
local turret_name_cache = {}

local function is_turret(entity)
    if not entity or not entity.valid then return false end
    
    local name = entity.name
    
    -- Fast lookup for known turrets
    if KNOWN_TURRETS[name] then
        return true
    end
    
    -- Check cache for modded turrets
    if turret_name_cache[name] ~= nil then
        return turret_name_cache[name]
    end
    
    -- Slow pattern matching only for unknown names (runs once per unique name)
    for _, pattern in ipairs(TURRET_PATTERNS) do
        if name:match(pattern) then
            turret_name_cache[name] = true
            return true
        end
    end
    
    turret_name_cache[name] = false
    return false
end

local function requires_ammo(entity)
    if not entity or not entity.valid then return false end
    
    -- Laser and electric turrets don't need ammo
    local name = entity.name
    if name:match("laser") or name:match("electric") then
        return false
    end
    
    -- Check if has ammo inventory
    local ammo_inv = entity.get_inventory(defines.inventory.turret_ammo)
    if not ammo_inv or not ammo_inv.valid then
        return false
    end
    
    return true
end

local function is_single_shot(entity)
    if not entity or not entity.valid then return false end
    
    -- Known single-shot turrets
    if SINGLE_SHOT_TURRETS[entity.name] then
        return true
    end
    
    return false
end

local function is_enabled_type(player, entity)
    local name = entity.name
    local etype = entity.type
    
    -- Vanilla gun turrets
    if name == "gun-turret" or name:match("^gun%-turret") then
        return get_player_setting(player, "nanobots-auto-defense-gun-turrets")
    end
    
    -- Artillery (vanilla and modded)
    if etype == "artillery-turret" or name:match("artillery") then
        return get_player_setting(player, "nanobots-auto-defense-artillery-turrets")
    end
    
    -- Everything else: ammo-turret type = modded turrets
    -- This covers rocket-turret, railgun-turret, and any modded ammo turrets
    if etype == "ammo-turret" then
        return get_player_setting(player, "nanobots-auto-defense-modded-turrets")
    end
    
    -- Fluid turrets (flamethrower) — don't use ammo from inventory
    -- but some mods may create fluid turrets that accept ammo
    if etype == "fluid-turret" then
        return get_player_setting(player, "nanobots-auto-defense-modded-turrets")
    end
    
    return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- AMMO CALCULATION
-- ═══════════════════════════════════════════════════════════════════════════

local function get_current_ammo_count(entity)
    local ammo_inv = entity.get_inventory(defines.inventory.turret_ammo)
    if not ammo_inv or not ammo_inv.valid then return 0 end
    
    local total = 0
    for i = 1, #ammo_inv do
        local stack = ammo_inv[i]
        if stack and stack.valid and stack.valid_for_read and stack.count > 0 then
            total = total + stack.count
        end
    end
    
    return total
end

local function get_magazine_capacity(entity)
    local ammo_inv = entity.get_inventory(defines.inventory.turret_ammo)
    if not ammo_inv or not ammo_inv.valid then return 0 end
    
    -- Calculate total capacity across all slots
    local capacity = 0
    for i = 1, #ammo_inv do
        local stack = ammo_inv[i]
        if stack and stack.valid then
            -- Get stack size from prototype
            if stack.valid_for_read and stack.name then
                local prototype = prototypes.item[stack.name]
                if prototype then
                    capacity = capacity + prototype.stack_size
                end
            else
                -- Empty slot - use default firearm magazine size
                local prototype = prototypes.item["firearm-magazine"]
                if prototype then
                    capacity = capacity + prototype.stack_size
                end
            end
        end
    end
    
    -- If empty, estimate based on typical ammo
    if capacity == 0 then
        capacity = 200  -- Default for gun turret
    end
    
    return capacity
end

local function calculate_threshold(player, entity)
    -- Artillery special handling
    local is_artillery = entity.name:match("artillery")
    local setting_name = is_artillery and "nanobots-auto-defense-artillery-threshold" 
                         or "nanobots-auto-defense-threshold"
    
    local value_str = get_player_setting(player, setting_name)
    local threshold_type, value = parse_threshold_or_delivery(value_str)
    
    debug_log(player, string.format("Threshold for %s: %s (%s)", 
        entity.name, value_str, threshold_type))
    
    -- Check magazine capacity
    local capacity = get_magazine_capacity(entity)
    
    -- Single-shot special case: only refill when empty
    if capacity == 1 then
        debug_log(player, "Single-shot turret, threshold=0")
        return 0
    end
    
    if threshold_type == "absolute" then
        return math.min(value, capacity)
    else
        -- Percent
        return math.floor(capacity * value / 100)
    end
end

local function calculate_delivery_amount(player, entity, current_ammo)
    -- Artillery special handling
    local is_artillery = entity.name:match("artillery")
    local setting_name = is_artillery and "nanobots-auto-defense-artillery-delivery" 
                         or "nanobots-auto-defense-delivery"
    
    local value_str = get_player_setting(player, setting_name)
    local delivery_type, value = parse_threshold_or_delivery(value_str)
    
    local capacity = get_magazine_capacity(entity)
    local space_available = capacity - current_ammo
    
    debug_log(player, string.format("Delivery for %s: capacity=%d, current=%d, space=%d, setting=%s", 
        entity.name, capacity, current_ammo, space_available, value_str))
    
    -- Single-shot special case: check magazine size
    if capacity == 1 then
        debug_log(player, "Single-shot turret, delivering 1")
        return math.min(1, space_available)
    end
    
    local amount
    if delivery_type == "absolute" then
        amount = value
    else
        -- Percent
        amount = math.floor(capacity * value / 100)
    end
    
    local final = math.min(amount, space_available)
    debug_log(player, string.format("Calculated delivery: %d (limited by space: %d)", amount, final))
    return final
end

-- ═══════════════════════════════════════════════════════════════════════════
-- AMMO DELIVERY
-- ═══════════════════════════════════════════════════════════════════════════

-- v5.8.0: Ammo compatibility cache (per turret name + player)
local ammo_compat_cache = {}  -- [turret_name .. "_" .. player_index] = {result, tick}
local AMMO_CACHE_TTL = 300  -- 5 seconds

local function find_compatible_ammo(player, entity, player_data_radius)
    -- Check cache first
    local cache_key = entity.name .. "_" .. player.index
    local cached = ammo_compat_cache[cache_key]
    if cached and (game.tick - cached.tick) < AMMO_CACHE_TTL then
        return cached.result
    end
    
    -- Get what's already in the turret
    local ammo_inv = entity.get_inventory(defines.inventory.turret_ammo)
    if not ammo_inv or not ammo_inv.valid then 
        debug_log(player, "ERROR: No ammo inventory on turret")
        return nil 
    end
    
    -- Check what type of ammo turret already has
    for i = 1, #ammo_inv do
        local stack = ammo_inv[i]
        if stack and stack.valid and stack.valid_for_read and stack.count > 0 then
            local existing_quality = "normal"
            if stack.quality then
                if type(stack.quality) == "table" and stack.quality.name then
                    existing_quality = stack.quality.name
                elseif type(stack.quality) == "string" then
                    existing_quality = stack.quality
                end
            end
            debug_log(player, "Turret has existing ammo: " .. stack.name .. " (quality: " .. existing_quality .. ")")
            return {
                name = stack.name,
                quality = existing_quality
            }
        end
    end
    
    debug_log(player, "Turret empty, searching for compatible ammo...")
    
    -- Turret empty - find compatible ammo in player inventory
    local player_inv = player.get_main_inventory()
    if not player_inv or not player_inv.valid then 
        debug_log(player, "ERROR: No player inventory")
        return nil 
    end
    
    -- Get turret's accepted ammo categories
    local entity_proto = entity.prototype
    if not entity_proto then 
        debug_log(player, "ERROR: No entity prototype")
        return nil 
    end
    
    if not entity_proto.attack_parameters then 
        debug_log(player, "ERROR: No attack_parameters on entity")
        return nil 
    end
    
    local accepted_categories = {}
    if entity_proto.attack_parameters.ammo_categories then
        -- Multiple categories (Factorio 2.0+)
        for _, cat in pairs(entity_proto.attack_parameters.ammo_categories) do
            accepted_categories[cat] = true
            debug_log(player, "Turret accepts ammo category: " .. cat)
        end
    elseif entity_proto.attack_parameters.ammo_category then
        -- Single category (older API)
        accepted_categories[entity_proto.attack_parameters.ammo_category] = true
        debug_log(player, "Turret accepts ammo category: " .. entity_proto.attack_parameters.ammo_category)
    else
        debug_log(player, "ERROR: No ammo_category found on turret")
        return nil
    end
    
    if next(accepted_categories) == nil then 
        debug_log(player, "ERROR: No accepted categories")
        return nil 
    end
    
    -- Search for compatible ammo in player inventory
    -- In Factorio 2.0: get_contents() returns ItemWithQualityCounts
    -- Array format: {[index] = {name=string, quality=string, count=number}}
    local contents = player_inv.get_contents()
    
    debug_log(player, "Scanning player inventory for compatible ammo...")
    
    -- v5.8.0: Cached damage tier lookup (item names don't change at runtime)
    local damage_tier_cache = {}
    
    local function get_damage_tier(item_name)
        if damage_tier_cache[item_name] ~= nil then
            return damage_tier_cache[item_name]
        end
        
        local tier = 1
        local name_lower = string.lower(item_name)
        if string.find(name_lower, "uranium") then
            tier = 5
        elseif string.find(name_lower, "explosive") or string.find(name_lower, "atomic") then
            tier = 4
        elseif string.find(name_lower, "piercing") then
            tier = 3
        elseif string.find(name_lower, "magazine") or string.find(name_lower, "basic") then
            tier = 2
        elseif string.find(name_lower, "artillery%-shell") then
            tier = 3
        end
        
        damage_tier_cache[item_name] = tier
        return tier
    end
    
    -- Collect ALL compatible ammo with their properties
    local compatible_ammo = {}
    
    -- Iterate through inventory contents
    for index, item_data in pairs(contents) do
        local item_name = item_data.name
        local item_count = item_data.count
        
        -- In Factorio 2.0, quality is a LuaQualityPrototype object, not a string
        local item_quality = "normal"
        if item_data.quality then
            if type(item_data.quality) == "table" and item_data.quality.name then
                item_quality = item_data.quality.name
            elseif type(item_data.quality) == "string" then
                item_quality = item_data.quality
            end
        end
        
        -- Get prototype using Factorio 2.0 API: prototypes.item[name]
        if not prototypes or not prototypes.item then
            debug_log(player, "ERROR: prototypes.item not available!")
            return nil
        end
        
        local item_prototype = prototypes.item[item_name]
        if not item_prototype then
            goto continue
        end
        
        -- Check if it's ammo
        if item_prototype.type == "ammo" then
            -- Access ammo_category property
            local ammo_category = item_prototype.ammo_category
            if ammo_category and ammo_category.name then
                local category_name = ammo_category.name
                
                -- Check if this category is accepted by turret
                if accepted_categories[category_name] then
                    -- v5.8.0: Cached damage tier lookup
                    local damage_tier = get_damage_tier(item_name)
                    
                    table.insert(compatible_ammo, {
                        name = item_name,
                        quality = item_quality,
                        count = item_count,
                        damage_tier = damage_tier,
                        prototype = item_prototype
                    })
                    debug_log(player, "Found compatible: " .. item_name .. " (quality: " .. item_quality .. ", tier: " .. damage_tier .. ", count: " .. item_count .. ")")
                end
            end
        end
        
        ::continue::
    end
    
    if #compatible_ammo == 0 then
        debug_log(player, "No compatible ammo found in inventory")
        ammo_compat_cache[cache_key] = {result = nil, tick = game.tick}
        return nil
    end
    
    -- Sort ammo based on player preferences (or combat mode auto-switch)
    local ammo_type_priority, ammo_quality_priority = get_effective_ammo_priorities(player, player_data_radius or 15)
    
    debug_log(player, "Sorting " .. #compatible_ammo .. " ammo types (type: " .. ammo_type_priority .. ", quality: " .. ammo_quality_priority .. ")")
    
    -- Debug: show all found ammo before sorting
    if #compatible_ammo > 1 then
        for i, ammo in ipairs(compatible_ammo) do
            debug_log(player, "  [" .. i .. "] " .. ammo.name .. " | quality: " .. ammo.quality .. " | tier: " .. ammo.damage_tier .. " | count: " .. ammo.count)
        end
    end
    
    -- Sort function
    table.sort(compatible_ammo, function(a, b)
        -- Primary sort: ammo type (damage tier)
        if a.damage_tier ~= b.damage_tier then
            if ammo_type_priority == "best-damage" then
                return a.damage_tier > b.damage_tier  -- Higher tier first
            else
                return a.damage_tier < b.damage_tier  -- Lower tier first
            end
        end
        
        -- Secondary sort: quality
        -- v5.8.0: Using module-level QUALITY_ORDER constant
        local a_quality_value = QUALITY_ORDER[a.quality] or 1
        local b_quality_value = QUALITY_ORDER[b.quality] or 1
        
        if ammo_quality_priority == "best-quality" then
            return a_quality_value > b_quality_value  -- Higher quality first
        else
            return a_quality_value < b_quality_value  -- Lower quality first
        end
    end)
    
    -- Debug: show sorted result
    if #compatible_ammo > 1 then
        debug_log(player, "After sorting:")
        for i, ammo in ipairs(compatible_ammo) do
            debug_log(player, "  [" .. i .. "] " .. ammo.name .. " | quality: " .. ammo.quality .. " | tier: " .. ammo.damage_tier)
        end
    end
    
    -- Return the best ammo according to priorities
    local best_ammo = compatible_ammo[1]
    debug_log(player, "Selected: " .. best_ammo.name .. " (quality: " .. best_ammo.quality .. ")")
    
    -- v5.8.0: Cache the result
    local result = {
        name = best_ammo.name,
        quality = best_ammo.quality
    }
    ammo_compat_cache[cache_key] = {result = result, tick = game.tick}
    
    return result
end

local function deliver_ammo(player, entity, ammo_name, ammo_quality, amount)
    if not player or not player.valid then return false end
    if not entity or not entity.valid then return false end
    if amount <= 0 then return false end
    
    local player_inv = player.get_main_inventory()
    if not player_inv or not player_inv.valid then return false end
    
    local ammo_inv = entity.get_inventory(defines.inventory.turret_ammo)
    if not ammo_inv or not ammo_inv.valid then return false end
    
    -- Check player has ammo with this quality
    -- In Factorio 2.0, we need to specify quality when checking/removing items
    local available = player_inv.get_item_count({name = ammo_name, quality = ammo_quality})
    if available <= 0 then
        debug_log(player, "Player doesn't have " .. ammo_name .. " with quality " .. ammo_quality)
        return false
    end
    
    -- Calculate how much to actually deliver
    local to_deliver = math.min(amount, available)
    
    debug_log(player, "Attempting to remove " .. to_deliver .. " x " .. ammo_name .. " (quality: " .. ammo_quality .. ")")
    
    -- Remove from player WITH QUALITY
    local removed = player_inv.remove({name = ammo_name, quality = ammo_quality, count = to_deliver})
    if removed == 0 then
        debug_log(player, "Failed to remove items from player inventory")
        return false
    end
    
    debug_log(player, "Removed " .. removed .. " items, inserting into turret...")
    
    -- Insert into turret WITH QUALITY
    local inserted = ammo_inv.insert({name = ammo_name, quality = ammo_quality, count = removed})
    
    debug_log(player, "Inserted " .. inserted .. " items into turret")
    
    -- Return leftover to player
    if inserted < removed then
        player_inv.insert({name = ammo_name, quality = ammo_quality, count = removed - inserted})
    end
    
    -- Show flying text and play sound
    if inserted > 0 and player and player.valid and entity and entity.valid then
        -- v5.7.0: Projectile visual (player → turret)
        local show_projectile = get_player_setting(player, "nanobots-auto-defense-show-projectile")
        if show_projectile and player.character and player.character.valid then
            local surface = player.character.surface
            if surface and surface.valid then
                pcall(function()
                    surface.create_entity({
                        name = 'nano-projectile-defense',
                        force = player.force,
                        position = player.character.position,
                        target = entity,
                        speed = 0.5
                    })
                end)
            end
        end
        
        -- Get localized item name
        local item_proto = prototypes.item[ammo_name]
        local item_localized_name = item_proto and item_proto.localised_name or ammo_name
        
        -- Quality colors matching Factorio's quality system
        -- v5.8.0: Using module-level QUALITY_COLORS constant
        
        -- Build display text
        local display_text
        if ammo_quality and ammo_quality ~= "normal" then
            local quality_proto = prototypes.quality and prototypes.quality[ammo_quality]
            local quality_localized = quality_proto and quality_proto.localised_name or ammo_quality
            local quality_color = QUALITY_COLORS[ammo_quality] or QUALITY_COLORS.normal
            local color_hex = string_format("%02x%02x%02x", 
                math_floor(quality_color.r * 255),
                math_floor(quality_color.g * 255),
                math_floor(quality_color.b * 255))
            
            display_text = {"", 
                "+", inserted, " ",
                item_localized_name, 
                " ([color=#", color_hex, "]",
                quality_localized,
                "[/color])"
            }
        else
            display_text = {"", "+", inserted, " ", item_localized_name}
        end
        
        -- Show flying text
        player.create_local_flying_text({
            text = display_text,
            position = entity.position,
            color = {r = 0.5, g = 1, b = 0.5},
            time_to_live = 60,
            speed = 1
        })
        
        -- Play ammo insertion sound using registered sound prototypes
        local sound_name
        if ammo_name:match("artillery") then
            sound_name = "nano-ammo-artillery"
        elseif ammo_name:match("cannon") or ammo_name:match("rocket") or ammo_name:match("railgun") then
            sound_name = "nano-ammo-large"
        else
            sound_name = "nano-ammo-small"
        end
        
        player.character.surface.play_sound({
            path = sound_name,
            position = entity.position,
            volume_modifier = 1.0
        })
    end
    
    return inserted > 0, inserted
end

-- ═══════════════════════════════════════════════════════════════════════════
-- NANO AMMO DRAIN
-- ═══════════════════════════════════════════════════════════════════════════

--- Drain 1 charge from nano-emitter ammo (same logic as nanobots.lua ammo_drain)
--- @param player LuaPlayer
--- @param nano_ammo LuaItemStack nano-emitter ammo stack
--- @return boolean true if drain succeeded
local function nano_ammo_drain(player, nano_ammo)
    if not (player and player.valid) then return false end
    if player.cheat_mode then return true end
    if not (nano_ammo and nano_ammo.valid_for_read) then return false end
    
    local name = nano_ammo.name
    
    nano_ammo.drain_ammo(1)
    
    -- If ammo depleted, try to load next stack from inventory
    if not nano_ammo.valid_for_read then
        local inv = player.get_main_inventory()
        if inv and inv.valid then
            local new = inv.find_item_stack(name)
            if new then
                nano_ammo.set_stack(new)
                new.clear()
            end
        end
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN SCAN LOOP
-- ═══════════════════════════════════════════════════════════════════════════

local function scan_and_rearm_turrets(player)
    if not player or not player.valid then 
        return 
    end
    
    if not storage or not storage.auto_defense then 
        -- Try to initialize
        if storage then
            storage.auto_defense = storage.auto_defense or {}
        end
        return 
    end
    
    local player_data = storage.auto_defense[player.index]
    
    if not player_data or not player_data.enabled then return end
    
    -- Get nanobot radius and nano-ammo reference
    local radius, nano_ammo
    local CACHE_DURATION = 300  -- 5 seconds = 300 ticks
    local current_tick = game.tick
    
    if player_data.cached_radius and 
       player_data.cached_radius_tick and 
       (current_tick - player_data.cached_radius_tick) < CACHE_DURATION then
        -- Use cached radius, but always get fresh nano_ammo reference
        radius = player_data.cached_radius
        _, nano_ammo = get_nanobot_radius(player)
    else
        -- Recalculate and cache
        radius, nano_ammo = get_nanobot_radius(player)
        player_data.cached_radius = radius
        player_data.cached_radius_tick = current_tick
    end
    
    -- No nano ammo = no delivery (skip scan entirely)
    if not nano_ammo or not nano_ammo.valid_for_read then
        return
    end
    
    -- v5.7.0: Check for combat mode changes and notify player
    local combat_mode_enabled = get_player_setting(player, "nanobots-auto-defense-combat-mode")
    if combat_mode_enabled then
        local in_combat = check_enemies_nearby(player, radius)
        local prev_mode = player_data.last_combat_state
        
        if prev_mode ~= nil and prev_mode ~= in_combat then
            -- Mode changed! Notify player
            pcall(function()
                if in_combat then
                    -- Switched to COMBAT mode (best ammo)
                    player.create_local_flying_text({
                        text = {"auto-defense.mode-combat"},
                        position = player.character.position,
                        color = {r = 1, g = 0.3, b = 0.3},
                        time_to_live = 120,
                        speed = 0.5
                    })
                else
                    -- Switched to ECONOMY mode (worst ammo)
                    player.create_local_flying_text({
                        text = {"auto-defense.mode-economy"},
                        position = player.character.position,
                        color = {r = 0.3, g = 1, b = 0.3},
                        time_to_live = 120,
                        speed = 0.5
                    })
                end
            end)
        end
        player_data.last_combat_state = in_combat
    end
    
    -- v5.7.0: Adaptive scan interval (faster in combat, slower in peace)
    local scan_interval = get_effective_scan_interval(player, radius)
    
    -- Check if enough time passed since last scan
    local time_since_scan = current_tick - player_data.last_scan_tick
    
    if time_since_scan < scan_interval then
        return
    end
    
    player_data.last_scan_tick = current_tick
    
    -- OPTIMIZATION: Use type filter to avoid scanning ALL entities
    -- This dramatically reduces entities returned on megabases
    -- NOTE: Using area (square) for consistency with nanobots.lua construction/repair
    local turret_types = {"ammo-turret", "artillery-turret", "fluid-turret"}
    local pos = player.character.position
    local area = {{pos.x - radius, pos.y - radius}, {pos.x + radius, pos.y + radius}}
    
    local turrets = player.character.surface.find_entities_filtered({
        area = area,
        force = player.force,
        type = turret_types
    })
    
    local turret_count = #turrets
    
    -- Only log if we actually found turrets to check
    if debug_defense_enabled and turret_count > 0 then
        debug_log(player, string.format("=== Scan: %d turrets in %d tile radius ===", turret_count, radius))
    end
    
    local max_per_tick = cached_global_settings.max_per_tick
    local processed = 0
    
    for _, entity in ipairs(turrets) do
        if processed >= max_per_tick then 
            break 
        end
        
        -- Entity validity check (type filter guarantees these are turrets)
        if not entity.valid then
            goto continue
        end
        
        if debug_defense_enabled then
            debug_log(player, string.format("Checking turret: %s", entity.name))
        end
        
        -- Check if enabled type
        if is_enabled_type(player, entity) then
            -- Check if requires ammo
            if requires_ammo(entity) then
                -- Check if blacklisted
                if not player_data.blacklist[entity.unit_number] then
                    -- Get current ammo count
                    local current_ammo = get_current_ammo_count(entity)
                    local threshold = calculate_threshold(player, entity)
                    
                    if debug_defense_enabled then
                        debug_log(player, string.format("  Ammo: %d, Threshold: %d", current_ammo, threshold))
                    end
                    
                    -- Check if below threshold
                    if current_ammo < threshold then
                        debug_log(player, "  → Below threshold! Searching ammo...")
                            
                            -- Find compatible ammo
                            local ammo_data = find_compatible_ammo(player, entity, radius)
                            
                            if ammo_data then
                                debug_log(player, string.format("  → Found: %s (%s), delivering %d", ammo_data.name, ammo_data.quality, calculate_delivery_amount(player, entity, current_ammo)))
                                
                                -- Check nano ammo is still valid before delivering
                                if not (nano_ammo and nano_ammo.valid_for_read) then
                                    debug_log(player, "  ✗ Nano ammo depleted, stopping")
                                    break
                                end
                                
                                -- Calculate delivery amount
                                local amount = calculate_delivery_amount(player, entity, current_ammo)
                                
                                -- Deliver ammo with quality
                                local success, delivered = deliver_ammo(player, entity, ammo_data.name, ammo_data.quality, amount)
                                
                                if success then
                                    -- Drain 1 nano-emitter charge per delivery
                                    nano_ammo_drain(player, nano_ammo)
                                    
                                    debug_log(player, string.format("  ✓ Delivered %d rounds (1 nano charge used)", delivered))
                                    
                                    -- Update statistics
                                    player_data.statistics.turrets_rearmed = player_data.statistics.turrets_rearmed + 1
                                    player_data.statistics.total_ammo_delivered = player_data.statistics.total_ammo_delivered + delivered
                                    player_data.statistics.nano_charges_used = (player_data.statistics.nano_charges_used or 0) + 1
                                    
                                    -- Track items by name+quality
                                    local items = player_data.statistics.items_delivered
                                    local item_key = ammo_data.name .. "|" .. ammo_data.quality
                                    items[item_key] = (items[item_key] or 0) + delivered
                                    
                                    processed = processed + 1
                                end
                            else
                                -- No compatible ammo found - show warning with turret name
                                show_warning_if_needed(player, player_data, entity)
                            end
                        end
                    end
                end
            end
        
        ::continue::
    end
    
    if processed > 0 then
        debug_log(player, string.format("=== Scan complete: %d turrets rearmed ===", processed))
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RADIUS CACHE UPDATE
-- ═══════════════════════════════════════════════════════════════════════════

function AutoDefense.update_radius(player)
    if not (player and player.valid) then return end
    local player_data = storage.auto_defense and storage.auto_defense[player.index]
    if not player_data then return end
    
    -- Invalidate radius cache so next scan recalculates
    player_data.cached_radius = nil
    player_data.cached_radius_tick = 0
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TOGGLE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════

function AutoDefense.toggle(player)
    if not player or not player.valid then return end
    if not storage or not storage.auto_defense then 
        AutoDefense.init()
    end
    
    AutoDefense.init_player(player)
    
    if not storage or not storage.auto_defense then return end
    local player_data = storage.auto_defense[player.index]
    if not player_data then return end
    
    player_data.enabled = not player_data.enabled
    
    -- Sync shortcut button state
    player.set_shortcut_toggled("nanobots-toggle-auto-defense", player_data.enabled)
    
    if player_data.enabled then
        player_data.enabled_tick = game.tick  -- For forced debug
    end
    
    -- Show simple status message
    if player_data.enabled then
        local radius = get_nanobot_radius(player)
        player.print({"auto-defense.enabled", radius})
        
        -- Reset session statistics on enable
        player_data.statistics.turrets_rearmed = 0
        player_data.statistics.total_ammo_delivered = 0
        player_data.statistics.items_delivered = {}
        player_data.statistics.nano_charges_used = 0
        player_data.statistics.session_start_tick = game.tick
        
        -- Ensure lifetime_stats exists and increment sessions
        if not player_data.lifetime_stats then
            player_data.lifetime_stats = {turrets_rearmed = 0, total_ammo_delivered = 0, nano_charges_used = 0, sessions_count = 0}
        end
        player_data.lifetime_stats.sessions_count = (player_data.lifetime_stats.sessions_count or 0) + 1
    else
        player.print({"auto-defense.disabled"})
        
        -- Accumulate into lifetime stats
        local stats = player_data.statistics
        if not player_data.lifetime_stats then
            player_data.lifetime_stats = {turrets_rearmed = 0, total_ammo_delivered = 0, nano_charges_used = 0, sessions_count = 0, items_delivered = {}}
        end
        local lt = player_data.lifetime_stats
        lt.turrets_rearmed = (lt.turrets_rearmed or 0) + (stats.turrets_rearmed or 0)
        lt.total_ammo_delivered = (lt.total_ammo_delivered or 0) + (stats.total_ammo_delivered or 0)
        lt.nano_charges_used = (lt.nano_charges_used or 0) + (stats.nano_charges_used or 0)
        
        -- Accumulate items_delivered into lifetime
        if not lt.items_delivered then lt.items_delivered = {} end
        if stats.items_delivered then
            for item_key, count in pairs(stats.items_delivered) do
                lt.items_delivered[item_key] = (lt.items_delivered[item_key] or 0) + count
            end
        end
        
        -- Save last session snapshot for GUI display when disabled
        player_data.last_session = {
            turrets_rearmed = stats.turrets_rearmed or 0,
            total_ammo_delivered = stats.total_ammo_delivered or 0,
            nano_charges_used = stats.nano_charges_used or 0,
            items_delivered = stats.items_delivered or {},
            duration_ticks = game.tick - (stats.session_start_tick or game.tick)
        }
        
        -- Show session statistics if any turrets were rearmed
        if stats.turrets_rearmed > 0 then
            -- Calculate session duration
            local duration_ticks = game.tick - (stats.session_start_tick or 0)
            local duration_sec = math_floor(duration_ticks / 60)
            local minutes = math_floor(duration_sec / 60)
            local seconds = duration_sec % 60
            
            player.print({"auto-defense.stats-header"})
            player.print({"auto-defense.stats-duration", minutes, seconds})
            player.print({"auto-defense.stats-turrets", stats.turrets_rearmed})
            player.print({"auto-defense.stats-ammo", stats.total_ammo_delivered})
            player.print({"auto-defense.stats-nano-charges", stats.nano_charges_used or 0})
            
            -- Show breakdown by ammo type with quality
            if stats.items_delivered and table_size(stats.items_delivered) > 0 then
                -- v5.8.0: Using module-level QUALITY_COLORS constant
                
                for item_key, count in pairs(stats.items_delivered) do
                    -- Parse "item_name|quality" format
                    local item_name, quality = item_key:match("([^|]+)|([^|]+)")
                    
                    if item_name and quality then
                        -- Get localized names
                        local item_proto = prototypes.item[item_name]
                        local item_localized = item_proto and item_proto.localised_name or item_name
                        
                        if quality ~= "normal" then
                            -- Show quality in color
                            local quality_proto = prototypes.quality[quality]
                            local quality_localized = quality_proto and quality_proto.localised_name or quality
                            
                            local quality_color = QUALITY_COLORS[quality] or QUALITY_COLORS.normal
                            local color_hex = string.format("%02x%02x%02x", 
                                math.floor(quality_color.r * 255),
                                math.floor(quality_color.g * 255),
                                math.floor(quality_color.b * 255))
                            
                            -- Format: "    - Firearm magazine (legendary): 100"
                            player.print({"", 
                                "    - ", item_localized, 
                                " ([color=#", color_hex, "]", quality_localized, "[/color]): ",
                                count
                            })
                        else
                            -- No quality suffix for normal
                            player.print({"auto-defense.stats-item", count, item_localized})
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EVENT HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════

function AutoDefense.on_tick()
    -- v5.7.0: Auto-enable/disable based on enemy presence (checked every 3 seconds)
    local auto_enable_check_interval = 180  -- 3 seconds
    if game.tick % auto_enable_check_interval == 0 then
        for _, player in pairs(game.connected_players) do
            if player.valid and player.character and player.character.valid then
                local auto_enable = get_player_setting(player, "nanobots-auto-defense-auto-enable-combat")
                if auto_enable then
                    local player_data = storage.auto_defense and storage.auto_defense[player.index]
                    if player_data then
                        -- Get radius for enemy check
                        local radius = player_data.cached_radius or 15
                        local in_combat = check_enemies_nearby(player, radius)
                        
                        -- Track previous auto-enable state (different from combat_mode state)
                        local prev_auto_state = player_data.last_auto_enable_state
                        
                        if prev_auto_state ~= in_combat then
                            -- State changed!
                            player_data.last_auto_enable_state = in_combat
                            
                            if in_combat and not player_data.enabled then
                                -- Enable system
                                player_data.enabled = true
                                player_data.statistics.session_start_tick = game.tick
                                player_data.last_scan_tick = 0
                                
                                -- Increment session count
                                if not player_data.lifetime_stats then
                                    player_data.lifetime_stats = {turrets_rearmed = 0, total_ammo_delivered = 0, nano_charges_used = 0, sessions_count = 0, items_delivered = {}}
                                end
                                player_data.lifetime_stats.sessions_count = (player_data.lifetime_stats.sessions_count or 0) + 1
                                
                                player.set_shortcut_toggled("nanobots-toggle-auto-defense", true)
                                
                                pcall(function()
                                    player.create_local_flying_text({
                                        text = {"auto-defense.auto-enabled"},
                                        position = player.character.position,
                                        color = {r = 1, g = 0.5, b = 0},
                                        time_to_live = 120,
                                        speed = 0.5
                                    })
                                end)
                                
                            elseif not in_combat and player_data.enabled then
                                -- Disable system and save stats
                                local stats = player_data.statistics
                                if not player_data.lifetime_stats then
                                    player_data.lifetime_stats = {turrets_rearmed = 0, total_ammo_delivered = 0, nano_charges_used = 0, sessions_count = 0, items_delivered = {}}
                                end
                                local lt = player_data.lifetime_stats
                                lt.turrets_rearmed = (lt.turrets_rearmed or 0) + (stats.turrets_rearmed or 0)
                                lt.total_ammo_delivered = (lt.total_ammo_delivered or 0) + (stats.total_ammo_delivered or 0)
                                lt.nano_charges_used = (lt.nano_charges_used or 0) + (stats.nano_charges_used or 0)
                                if not lt.items_delivered then lt.items_delivered = {} end
                                if stats.items_delivered then
                                    for item_key, count in pairs(stats.items_delivered) do
                                        lt.items_delivered[item_key] = (lt.items_delivered[item_key] or 0) + count
                                    end
                                end
                                
                                -- Save last session
                                player_data.last_session = {
                                    turrets_rearmed = stats.turrets_rearmed or 0,
                                    total_ammo_delivered = stats.total_ammo_delivered or 0,
                                    nano_charges_used = stats.nano_charges_used or 0,
                                    items_delivered = stats.items_delivered or {},
                                    duration_ticks = game.tick - (stats.session_start_tick or game.tick)
                                }
                                
                                -- Reset session stats
                                stats.turrets_rearmed = 0
                                stats.total_ammo_delivered = 0
                                stats.items_delivered = {}
                                stats.nano_charges_used = 0
                                
                                player_data.enabled = false
                                player.set_shortcut_toggled("nanobots-toggle-auto-defense", false)
                                
                                pcall(function()
                                    player.create_local_flying_text({
                                        text = {"auto-defense.auto-disabled"},
                                        position = player.character.position,
                                        color = {r = 0.5, g = 1, b = 0.5},
                                        time_to_live = 120,
                                        speed = 0.5
                                    })
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Optimization: Distribute player scans across ticks to reduce CPU spikes
    -- Each player is scanned every N ticks, but on different ticks
    
    local scan_interval = cached_global_settings.scan_interval
    
    -- Only process on scan interval boundaries
    if game.tick % scan_interval ~= 0 then return end
    
    -- Count total connected players
    local connected_players = {}
    for _, player in pairs(game.players) do
        if player.valid and player.connected then
            connected_players[#connected_players + 1] = player
        end
    end
    
    if #connected_players == 0 then return end
    
    -- Distribute players across scan intervals
    -- Example: 10 players, 60 tick interval → process ~1-2 players per interval
    local players_per_scan = math.max(1, math.ceil(#connected_players / (scan_interval / 60)))
    
    -- Calculate which players to process this tick
    local scan_cycle = math.floor(game.tick / scan_interval)
    local start_index = ((scan_cycle * players_per_scan) % #connected_players) + 1
    
    for i = 0, players_per_scan - 1 do
        local player_index = ((start_index + i - 1) % #connected_players) + 1
        local player = connected_players[player_index]
        if player then
            local ok, err = pcall(scan_and_rearm_turrets, player)
            if not ok then
                log("[Nanobots3 Auto-Defense] Error in scan: " .. tostring(err))
            end
        end
    end
end

function AutoDefense.on_player_created(event)
    local player = game.get_player(event.player_index)
    if player then
        AutoDefense.init_player(player)
    end
end

function AutoDefense.on_player_joined(event)
    local player = game.get_player(event.player_index)
    if player then
        AutoDefense.init_player(player)
        AutoDefense.update_radius(player)
        
        -- Restore shortcut state from saved data
        if storage and storage.auto_defense and storage.auto_defense[player.index] then
            local player_data = storage.auto_defense[player.index]
            player.set_shortcut_toggled("nanobots-toggle-auto-defense", player_data.enabled)
        end
    end
end

function AutoDefense.on_runtime_mod_setting_changed(event)
    -- Update cached global settings
    if event.setting_type == "runtime-global" then
        if event.setting:match("^nanobots%-auto%-defense") then
            update_cached_global_settings()
        end
        -- v5.8.0: Update debug flag on any relevant setting change
        if event.setting:match("^nanobots%-debug") or event.setting:match("^nanobots%-log") then
            pcall(update_debug_defense_flag)
        end
    end
    
    if event.setting_type == "runtime-per-user" then
        local player = game.get_player(event.player_index)
        if player and event.setting:match("^nanobots%-auto%-defense") then
            AutoDefense.update_radius(player)
            -- v5.8.0: Invalidate player settings cache
            player_settings_cache[player.index] = nil
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- v5.7.0: STATISTICS GUI
-- ═══════════════════════════════════════════════════════════════════════════

local GUI_NAME = "nano_defense_stats"
local GUI_UPDATE_INTERVAL = 60  -- Update GUI every 1 second

function AutoDefense.destroy_gui(player)
    if not (player and player.valid) then return end
    local gui = player.gui.left[GUI_NAME]
    if gui then gui.destroy() end
end

function AutoDefense.toggle_gui(player)
    if not (player and player.valid) then return end
    
    local player_data = storage.auto_defense and storage.auto_defense[player.index]
    if not player_data then return end
    
    local gui = player.gui.left[GUI_NAME]
    if gui then
        gui.destroy()
        player_data.gui_visible = false
        return
    end
    
    player_data.gui_visible = true
    AutoDefense.create_gui(player)
end

function AutoDefense.create_gui(player)
    if not (player and player.valid) then return end
    
    -- Remove existing
    local existing = player.gui.left[GUI_NAME]
    if existing then existing.destroy() end
    
    local player_data = storage.auto_defense and storage.auto_defense[player.index]
    if not player_data then return end
    
    local stats = player_data.statistics
    local lt = player_data.lifetime_stats or {turrets_rearmed = 0, total_ammo_delivered = 0, nano_charges_used = 0, sessions_count = 0}
    local radius = player_data.cached_radius or 0
    local is_enabled = player_data.enabled
    
    -- Build frame
    local frame = player.gui.left.add({
        type = "frame",
        name = GUI_NAME,
        direction = "vertical",
        caption = {"auto-defense.gui-title"}
    })
    frame.style.maximal_width = 300
    frame.style.padding = 4
    
    -- Status line
    local status_flow = frame.add({type = "flow", direction = "horizontal"})
    
    if is_enabled then
        local in_combat = check_enemies_nearby(player, radius)
        local status_label = status_flow.add({
            type = "label",
            name = "status_label",
            caption = in_combat and {"auto-defense.gui-combat"} or {"auto-defense.gui-peaceful"}
        })
        status_label.style.font_color = in_combat and {r=1, g=0.3, b=0.3} or {r=0.3, g=1, b=0.3}
        status_label.style.font = "default-bold"
        status_flow.add({type = "label", caption = {"auto-defense.gui-radius", radius}})
    else
        local status_label = status_flow.add({
            type = "label",
            name = "status_label",
            caption = {"auto-defense.gui-disabled"}
        })
        status_label.style.font_color = {r=0.6, g=0.6, b=0.6}
        status_label.style.font = "default-bold"
    end
    
    -- Helper: add ammo breakdown table to frame
    local function add_breakdown(parent, items_data)
        if not items_data or not next(items_data) then return end
        local items_tbl = parent.add({type = "table", column_count = 2})
        items_tbl.style.column_alignments[2] = "right"
        items_tbl.style.horizontally_stretchable = true
        items_tbl.style.left_padding = 8
        
        local sorted_items = {}
        for item_key, count in pairs(items_data) do
            sorted_items[#sorted_items + 1] = {key = item_key, count = count}
        end
        table.sort(sorted_items, function(a, b) return a.count > b.count end)
        
        for i, entry in ipairs(sorted_items) do
            if i > 8 then break end
            local item_name, quality = entry.key:match("([^|]+)|([^|]+)")
            if item_name then
                local item_proto = prototypes.item[item_name]
                local display_name = item_proto and item_proto.localised_name or item_name
                
                if quality and quality ~= "normal" then
                    local qp = prototypes.quality and prototypes.quality[quality]
                    local ql = qp and qp.localised_name or quality
                    items_tbl.add({type = "label", caption = {"", "  ", display_name, " (", ql, ")"}})
                else
                    items_tbl.add({type = "label", caption = {"", "  ", display_name}})
                end
                items_tbl.add({type = "label", caption = tostring(entry.count)})
            end
        end
    end
    
    -- === Session stats ===
    if is_enabled then
        -- Live session
        local duration_ticks = game.tick - (stats.session_start_tick or game.tick)
        local duration_sec = math_floor(duration_ticks / 60)
        local minutes = math_floor(duration_sec / 60)
        local seconds = duration_sec % 60
        
        frame.add({type = "line"})
        local session_hdr = frame.add({type = "label", caption = {"auto-defense.gui-session-header"}})
        session_hdr.style.font = "default-semibold"
        
        local tbl = frame.add({type = "table", column_count = 2, name = "stats_table"})
        tbl.style.column_alignments[2] = "right"
        tbl.style.horizontally_stretchable = true
        
        tbl.add({type = "label", caption = {"auto-defense.gui-duration"}})
        tbl.add({type = "label", caption = string_format("%d:%02d", minutes, seconds)})
        
        tbl.add({type = "label", caption = {"auto-defense.gui-turrets-rearmed"}})
        tbl.add({type = "label", caption = tostring(stats.turrets_rearmed or 0)})
        
        tbl.add({type = "label", caption = {"auto-defense.gui-ammo-delivered"}})
        tbl.add({type = "label", caption = tostring(stats.total_ammo_delivered or 0)})
        
        tbl.add({type = "label", caption = {"auto-defense.gui-nano-charges"}})
        tbl.add({type = "label", caption = tostring(stats.nano_charges_used or 0)})
        
        add_breakdown(frame, stats.items_delivered)
        
    elseif player_data.last_session and (player_data.last_session.turrets_rearmed or 0) > 0 then
        -- Show last session snapshot when disabled
        local ls = player_data.last_session
        local duration_sec = math_floor((ls.duration_ticks or 0) / 60)
        local minutes = math_floor(duration_sec / 60)
        local seconds = duration_sec % 60
        
        frame.add({type = "line"})
        local session_hdr = frame.add({type = "label", caption = {"auto-defense.gui-last-session"}})
        session_hdr.style.font = "default-semibold"
        
        local tbl = frame.add({type = "table", column_count = 2, name = "stats_table"})
        tbl.style.column_alignments[2] = "right"
        tbl.style.horizontally_stretchable = true
        
        tbl.add({type = "label", caption = {"auto-defense.gui-duration"}})
        tbl.add({type = "label", caption = string_format("%d:%02d", minutes, seconds)})
        
        tbl.add({type = "label", caption = {"auto-defense.gui-turrets-rearmed"}})
        tbl.add({type = "label", caption = tostring(ls.turrets_rearmed or 0)})
        
        tbl.add({type = "label", caption = {"auto-defense.gui-ammo-delivered"}})
        tbl.add({type = "label", caption = tostring(ls.total_ammo_delivered or 0)})
        
        tbl.add({type = "label", caption = {"auto-defense.gui-nano-charges"}})
        tbl.add({type = "label", caption = tostring(ls.nano_charges_used or 0)})
        
        add_breakdown(frame, ls.items_delivered)
    end
    
    -- === Lifetime stats (always shown if data exists) ===
    if (lt.turrets_rearmed or 0) > 0 then
        frame.add({type = "line"})
        local lt_hdr = frame.add({type = "label", caption = {"auto-defense.gui-lifetime-header"}})
        lt_hdr.style.font = "default-semibold"
        
        local lt_tbl = frame.add({type = "table", column_count = 2, name = "lt_table"})
        lt_tbl.style.column_alignments[2] = "right"
        lt_tbl.style.horizontally_stretchable = true
        
        lt_tbl.add({type = "label", caption = {"auto-defense.gui-sessions"}})
        lt_tbl.add({type = "label", caption = tostring(lt.sessions_count or 0)})
        
        lt_tbl.add({type = "label", caption = {"auto-defense.gui-turrets-rearmed"}})
        lt_tbl.add({type = "label", caption = tostring(lt.turrets_rearmed or 0)})
        
        lt_tbl.add({type = "label", caption = {"auto-defense.gui-ammo-delivered"}})
        lt_tbl.add({type = "label", caption = tostring(lt.total_ammo_delivered or 0)})
        
        lt_tbl.add({type = "label", caption = {"auto-defense.gui-nano-charges"}})
        lt_tbl.add({type = "label", caption = tostring(lt.nano_charges_used or 0)})
        
        add_breakdown(frame, lt.items_delivered)
    end
    
    -- Close button
    local btn_flow = frame.add({type = "flow", direction = "horizontal"})
    btn_flow.style.horizontally_stretchable = true
    btn_flow.style.horizontal_align = "right"
    btn_flow.add({
        type = "button",
        name = "nano_defense_stats_close",
        caption = {"auto-defense.gui-close"},
        style = "mini_button"
    })
end

function AutoDefense.update_gui(player)
    if not (player and player.valid) then return end
    
    local gui = player.gui.left[GUI_NAME]
    if not gui then return end
    
    local player_data = storage.auto_defense and storage.auto_defense[player.index]
    if not player_data then
        gui.destroy()
        return
    end
    
    -- v5.8.0: Try incremental update for active session (just update numbers)
    local stats = player_data.statistics
    if player_data.enabled and gui.stats_table then
        local tbl = gui.stats_table
        local children = tbl.children
        -- stats_table has pairs: [label, value, label, value, ...]
        -- Duration is at index 2, turrets at 4, ammo at 6, nano at 8
        if #children >= 8 then
            local duration_ticks = game.tick - (stats.session_start_tick or game.tick)
            local duration_sec = math_floor(duration_ticks / 60)
            local minutes = math_floor(duration_sec / 60)
            local seconds = duration_sec % 60
            children[2].caption = string_format("%d:%02d", minutes, seconds)
            children[4].caption = tostring(stats.turrets_rearmed or 0)
            children[6].caption = tostring(stats.total_ammo_delivered or 0)
            children[8].caption = tostring(stats.nano_charges_used or 0)
            return  -- Done, no need to recreate
        end
    end
    
    -- Fallback: full recreate if structure doesn't match
    AutoDefense.create_gui(player)
end

function AutoDefense.on_gui_click(event)
    if event.element and event.element.valid and event.element.name == "nano_defense_stats_close" then
        local player = game.get_player(event.player_index)
        if player then
            AutoDefense.destroy_gui(player)
            local player_data = storage.auto_defense and storage.auto_defense[player.index]
            if player_data then
                player_data.gui_visible = false
            end
        end
    end
end

-- Called from on_tick to update open GUIs periodically
function AutoDefense.update_open_guis()
    if game.tick % GUI_UPDATE_INTERVAL ~= 0 then return end
    
    for _, player in pairs(game.connected_players) do
        if player.valid then
            local player_data = storage.auto_defense and storage.auto_defense[player.index]
            if player_data and player_data.gui_visible and player_data.enabled then
                AutoDefense.update_gui(player)
            end
        end
    end
end

-- Cleanup enemy cache when player leaves
function AutoDefense.on_player_left(player_index)
    enemy_cache[player_index] = nil
end

return AutoDefense
