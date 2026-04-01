-- cache.lua
-- v5.4.0: Caching system for expensive operations
-- Performance optimization: cache quality calculations, reduce redundant computations

local CONSTANTS = require('scripts/constants')
local Cache = {}

---Initialize quality cache storage
function Cache.init_quality_cache()
    storage.quality_cache = storage.quality_cache or {}
end

---Get cached quality data for a player
---@param player_index number
---@param current_tick number
---@return table|nil cached_data {gun_quality_name, gun_bonus, ammo_quality_name, ammo_bonus, ammo_name}
function Cache.get_quality_cache(player_index, current_tick)
    -- v5.4.2: Safety check - ensure cache exists
    if not storage.quality_cache then
        return nil
    end
    
    local cache = storage.quality_cache[player_index]
    
    if not cache then
        return nil
    end
    
    -- Check if cache is still valid
    if (current_tick - cache.last_update) > CONSTANTS.CACHE_DURATION_TICKS then
        return nil  -- Cache expired
    end
    
    return cache
end

---Update quality cache for a player
---@param player_index number
---@param current_tick number
---@param gun_quality_name string
---@param gun_bonus number
---@param ammo_quality_name string
---@param ammo_bonus number
---@param ammo_name string
function Cache.set_quality_cache(player_index, current_tick, gun_quality_name, gun_bonus, ammo_quality_name, ammo_bonus, ammo_name)
    -- v5.4.2: Safety - ensure storage exists
    storage.quality_cache = storage.quality_cache or {}
    
    storage.quality_cache[player_index] = {
        gun_quality_name = gun_quality_name,
        gun_bonus = gun_bonus,
        ammo_quality_name = ammo_quality_name,
        ammo_bonus = ammo_bonus,
        ammo_name = ammo_name,
        last_update = current_tick
    }
end

---Clear quality cache for a player (e.g., when they leave)
---@param player_index number
function Cache.clear_quality_cache(player_index)
    if storage.quality_cache then
        storage.quality_cache[player_index] = nil
    end
end

---Periodic cleanup of old cache entries (call every ~10 minutes)
---@param current_tick number
function Cache.cleanup_old_caches(current_tick)
    if not storage.quality_cache then return end
    
    for player_index, cache in pairs(storage.quality_cache) do
        if (current_tick - cache.last_update) > CONSTANTS.CLEANUP_INTERVAL_TICKS then
            storage.quality_cache[player_index] = nil
        end
    end
end

return Cache
