local NANO = {}

NANO.DEBUG = false

--Combat robot names, indexed by capsule name
NANO.COMBAT_ROBOTS = {
    {capsule = 'bob-laser-robot-capsule', unit = 'bob-laser-robot', qty = 5, rank = 75},
    {capsule = 'destroyer-capsule', unit = 'destroyer', qty = 5, rank = 50},
    {capsule = 'defender-capsule', unit = 'defender', qty = 1, rank = 25},
    {capsule = 'distractor-capsule', unit = 'distractor', qty = 1, rank = 1}
}

NANO.FOOD = {
    ['alien-goop-cracking-cotton-candy'] = 100,
    ['cooked-biter-meat'] = 50,
    ['cooked-fish'] = 40,
    ['raw-fish'] = 20,
    ['raw-biter-meat'] = 20
}

NANO.TRANSPORT_TYPES = {
    ['transport-belt'] = 2,
    ['underground-belt'] = 2,
    ['splitter'] = 8,
    ['loader'] = 2
}

NANO.ALLOWED_NOT_ON_MAP = {
    ['entity-ghost'] = true,
    ['tile-ghost'] = true,
    ['item-on-ground'] = true
}

--Tables linked to technologies, values are the tile radius
NANO.BOT_RADIUS = {[0] = 7, [1] = 9, [2] = 11, [3] = 13, [4] = 15}
NANO.QUEUE_SPEED_BONUS = {[0] = 0, [1] = 2, [2] = 4, [3] = 6, [4] = 8}

-- v5.2: Quality bonuses for Factorio 2.0
NANO.QUALITY_BONUSES = {
    -- Radius multipliers (ammo quality affects range)
    radius = {
        normal = 1.0,
        uncommon = 1.15,   -- +15%
        rare = 1.30,       -- +30%
        epic = 1.50,       -- +50%
        legendary = 1.75   -- +75%
    },
    -- Speed multipliers (gun quality affects work speed)
    speed = {
        normal = 1.0,
        uncommon = 1.15,   -- +15%
        rare = 1.30,       -- +30%
        epic = 1.50,       -- +50%
        legendary = 1.75   -- +75%
    }
}

-- Visualization colors for radius display
NANO.RADIUS_COLORS = {
    constructors = {r = 0.0, g = 1.0, b = 0.0, a = 0.3},  -- Green
    deconstructors = {r = 1.0, g = 0.0, b = 0.0, a = 0.3}, -- Red
    repair = {r = 0.0, g = 0.5, b = 1.0, a = 0.3},        -- Blue
    termites = {r = 1.0, g = 0.5, b = 0.0, a = 0.3}       -- Orange
}

NANO.control = {}
NANO.control.loglevel = 2

return NANO
