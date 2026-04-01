---@class JetpackModData
---@field tile_effects {[string]: "space"|"bounce"|"stop"|"bump"}
---@field bounce_entities string[]
---@field optional_takeoff_blocked_message {[string]: LocalisedString}

data:extend{
  {
    type = "mod-data",
    name = "jetpack",
    ---@type JetpackModData
    data = {
      tile_effects = {
        ["se-space"] = "space",

        ["out-of-map"] = "bounce",
        ["interior-divider"] = "bounce",

        ["se-spaceship-floor"] = "stop",
      },
      bounce_entities = {
        "se-spaceship-wall",
        "se-spaceship-gate",
        "se-spaceship-rocket-engine",
        "se-spaceship-ion-engine",
        "se-spaceship-antimatter-engine",
        "se-spaceship-clamp",
      },
      optional_takeoff_blocked_message = { -- just for "stop"
        ["se-spaceship-floor"] = {"jetpack.cant_fly_inside"},
      },
    },
  },
}
