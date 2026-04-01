-- constants.lua
-- v5.4.0: Centralized constants for Nanobots3
-- All magic numbers and configuration values in one place

local CONSTANTS = {}

-- === PERFORMANCE === 
CONSTANTS.CACHE_DURATION_TICKS = 60  -- How long to cache quality calculations (1 second)
CONSTANTS.CLEANUP_INTERVAL_TICKS = 60 * 60 * 10  -- Clean old caches every 10 minutes
CONSTANTS.REPAIR_SCAN_THROTTLE_TICKS = 60  -- How often to scan for damaged entities per player (1 second)
-- GHOST_SCAN_THROTTLE removed in v5.4.3 - it blocked item-request-proxy processing

-- === RENDERING ===
CONSTANTS.CIRCLE_TTL_TICKS = 300  -- Circle time-to-live (5 seconds)
CONSTANTS.CIRCLE_REFRESH_TICKS = 270  -- Refresh circle before TTL expires (4.5 seconds)
CONSTANTS.CIRCLE_WIDTH = 2  -- Width of visualization circle
CONSTANTS.VISUALIZATION_UPDATE_TICKS = 30  -- Update visualization every 0.5 seconds

-- === QUALITY MULTIPLIERS ===
CONSTANTS.QUALITY_BONUSES = {
    normal = {speed = 1.00, radius = 1.00},
    uncommon = {speed = 1.10, radius = 1.10},
    rare = {speed = 1.30, radius = 1.30},
    epic = {speed = 1.50, radius = 1.50},
    legendary = {speed = 1.75, radius = 1.75}
}

-- === AMMO COLORS ===
CONSTANTS.AMMO_COLORS = {
    ["nano-ammo"] = {r = 0, g = 1, b = 0},  -- Green
    ["nano-ammo-termites"] = {r = 0.8, g = 0.4, b = 0},  -- Orange
    ["nano-ammo-constructors"] = {r = 0, g = 1, b = 0},  -- Green
    ["nano-ammo-deconstructors"] = {r = 1, g = 0, b = 0},  -- Red
    ["nano-ammo-scrappers"] = {r = 0.5, g = 0.5, b = 0.5}  -- Gray
}
CONSTANTS.DEFAULT_AMMO_COLOR = {r = 0, g = 1, b = 0}  -- Green fallback

-- === LOGGING ===
CONSTANTS.DEBUG_MODE = false  -- Enable/disable debug logging

return CONSTANTS
