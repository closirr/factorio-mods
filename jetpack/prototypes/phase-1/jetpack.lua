local data_util = require("data_util")

local jetpack_equipment_prototypes = {
  ["jetpack-1"] = {
    tier = 1, grid_width = 2, grid_height = 2, power = "100kW", order = "a",
    ingredients = {
      {type = "item", name = "steel-plate", amount = 10},
      {type = "item", name = "pipe", amount = 10},
      {type = "item", name = "electronic-circuit", amount = 10},
    },
    science_packs = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
    },
    prerequisites = {
      "solar-panel-equipment",
      "rocket-fuel",
    }
  },

  ["jetpack-2"] = {
    tier = 2, grid_width = 2, grid_height = 2, power = "200kW", order = "b",
    ingredients = {
      {type = "item", name = "jetpack-1", amount = 2},
      {type = "item", name = "electric-engine-unit", amount = 20},
      {type = "item", name = "advanced-circuit", amount = 20},
    },
    science_packs = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
    },
    prerequisites = {
      "jetpack-1",
      "electric-engine",
      "advanced-circuit"
    }
  },

  ["jetpack-3"] = {
    tier = 3, grid_width = 2, grid_height = 2, power = "400kW", order = "c",
    ingredients = {
      {type = "item", name = "jetpack-2", amount = 2 },
      {type = "item", name = "processing-unit", amount = 30},
      {type = "item", name = "low-density-structure", amount = 30},
    },
    science_packs = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
      { "utility-science-pack", 1 },
    },
    prerequisites = {
      "jetpack-2",
      "processing-unit",
      "low-density-structure",
      "utility-science-pack"
    }
  },

  ["jetpack-4"] = {
    tier = 4, grid_width = 2, grid_height = 2, power = "800kW", order = "d",
    ingredients = {
      {type = "item", name = "jetpack-3", amount = 2},
      {type = "item", name = "speed-module-3", amount = 40},
      {type = "item", name = "efficiency-module-3", amount = 40},
    },
    science_packs = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
      { "utility-science-pack", 1 },
      { "space-science-pack", 1 },
    },
    prerequisites = {
      "jetpack-3",
      "speed-module-3",
      "efficiency-module-3",
      "space-science-pack"
    }
  },
}

for name, jep in pairs(jetpack_equipment_prototypes) do

  local jetpack_equipment = table.deepcopy(data.raw["battery-equipment"]["battery-equipment"])
  jetpack_equipment.name = name
  jetpack_equipment.movement_bonus = 0
  jetpack_equipment.energy_source = {
    type = "electric",
    usage_priority = "tertiary"

  }
  --jetpack_equipment.energy_consumption = "1kW"
  jetpack_equipment.sprite = { filename = "__jetpack__/graphics/equipment/"..name..".png", width = 128, height = 128, priority = "medium" }
  --jetpack_equipment.background_color = { r = 0.2, g = 0.3, b = 0.6, a = 1 }
  jetpack_equipment.shape = { width = jep.grid_width, height = jep.grid_width, type = "full" }
  jetpack_equipment.categories = {"armor-jetpack"}

  local jetpack_item = table.deepcopy(data.raw["item"]["battery-equipment"])
  jetpack_item.name = name
  jetpack_item.icon = "__jetpack__/graphics/icons/"..name..".png"
  jetpack_item.icon_size = 64
  jetpack_item.place_as_equipment_result = name
  jetpack_item.order = "c[jetpack]-"..jep.order.."["..name.."]"

  local jetpack_recipe = table.deepcopy(data.raw["recipe"]["battery-equipment"])
  jetpack_recipe.name = name
  jetpack_recipe.icon = icon_path
  jetpack_recipe.icon_size = 32
  jetpack_recipe.enabled = false
  jetpack_recipe.results = {{type = "item", name = name, amount = 1}}
  jetpack_recipe.ingredients = jep.ingredients
  jetpack_recipe.energy_required = jep.tier * 10
  jetpack_recipe.category = "crafting"
  jetpack_recipe.order = "c[jetpack]-"..jep.order.."["..name.."]"

  local jetpack_tech = {
    type = "technology",
    name = name,
    effects = { { type = "unlock-recipe", recipe = name } },
    icons = data_util.technology_icon_constant_equipment("__jetpack__/graphics/technology/"..name..".png", 256),
    order = "e-g",
    prerequisites = jep.prerequisites,
    unit = {
     count = jep.tier * 100,
     time = 30,
     ingredients = jep.science_packs
    },
  }

  data:extend({
    jetpack_equipment,
    jetpack_item,
    jetpack_recipe,
    jetpack_tech
  })

end

data:extend ({
  {
    name = "armor-jetpack",
    type = "equipment-category",
  },
})
