local data_util = require("data_util")

local char_list = {}
local shift = util.by_pixel(-0.5,-34.5)

local animation_blank =
{
  filename = "__jetpack__/graphics/entity/character/jetpack.png",
  width = 1,
  height = 1,
  line_length = 32,
  shift = shift,
  frame_count = 1,
  direction_count = 18,
  animation_speed = 0.6,
  scale = 0.5
}
local animation_base =
{
  filename = "__jetpack__/graphics/entity/character/jetpack.png",
  width = 256,
  height = 256,
  line_length = 4,
  shift = shift,
  frame_count = 1,
  direction_count = 32,
  animation_speed = 0.6,
  scale = 0.5
}
local animation_mask =
{
  apply_runtime_tint = true,
  filename = "__jetpack__/graphics/entity/character/jetpack-mask.png",
  width = 256,
  height = 256,
  line_length = 4,
  shift = shift,
  frame_count = 1,
  direction_count = 32,
  animation_speed = 0.6,
  scale = 0.5
}
local animation_flame =
{
  draw_as_glow = true,
  filename = "__jetpack__/graphics/entity/character/jetpack-flame.png",
  width = 256,
  height = 256,
  line_length = 4,
  shift = shift,
  frame_count = 1,
  direction_count = 32,
  animation_speed = 0.6,
  scale = 0.5
}
local animation_layers = {
  animation_base,
  animation_mask,
  animation_flame
}

-- make rendering animations
for i, name in pairs({"jetpack-animation", "jetpack-animation-mask", "jetpack-animation-flame"}) do
  local set = table.deepcopy(animation_layers[i])
  set.type = "animation"
  set.name = name
  set.apply_runtime_tint = true
  set.direction_count = 1
  set.frame_count = 32
  if i == 3 then
    set.blend_mode = "additive"
  end
  data:extend({ set })
end

data:extend({
  {
    type = "animation",
    name = "jetpack-animation-shadow",
    draw_as_shadow = true,
    filename = "__jetpack__/graphics/entity/character/jetpack-shadow.png",
    width = 256,
    height = 256,
    line_length = 4,
    shift = util.by_pixel(2,0),
    direction_count = 1,
    frame_count = 32,
    animation_speed = 0.6,
    scale = 0.5
  }
})

local function running_with_gun_animation(animation_layers)
  local animation_layers = table.deepcopy(animation_layers)
  for _, set in pairs(animation_layers) do
    local filename = set.filename
    local stripes = {}
    set.direction_count = 18
    set.filename = nil
    set.stripes = stripes
    for i = 1, 18 do
      if i == 1 then
        table.insert(stripes,
          {
            filename = filename,
            width_in_frames = 1,
            height_in_frames = 1,
            x = 0,
            y = 0
          })
      elseif i == 2 then
        table.insert(stripes,
          {
            filename = filename,
            width_in_frames = 1,
            height_in_frames = 1,
            x = 256,
            y = 256
          })
      elseif i == 3 then
        table.insert(stripes,
          {
            filename = filename,
            width_in_frames = 1,
            height_in_frames = 1,
            x = 3 * 256,
            y = 7 * 256
          })
      else
        table.insert(stripes,
          {
            filename = filename,
            width_in_frames = 1,
            height_in_frames = 1,
            x = ((i - 2) % 4) * 256,
            y = (math.floor((i-2) / 4)) * 256
          })
      end
    end
  end
  return animation_layers
end
local run_gun_animation_layers = running_with_gun_animation(animation_layers)

local function remove_shadows_recursive(table)
  for k, v in pairs(table) do
    if type(v) == "table" then
      if v.draw_as_shadow or k == "flipped_shadow_running_with_gun" then
        table[k] = nil
      else
        remove_shadows_recursive(v)
      end
    end
  end
end

local function set_render_layer_recursive(table, render_layer)
  for k, v in pairs(table) do
    if type(v) == "table" then
      if v.filename then
        v.render_layer = render_layer
      end
      set_render_layer_recursive(v, render_layer)
    end
  end
end

for name, character in pairs(data.raw.character) do
  if not character.prevent_jetpack == true then
    table.insert(char_list, name)
  end
end

local trigger_target_mask = data.raw["utility-constants"].default.default_trigger_target_mask_by_type["construction-robot"] -- flying, stops acid puddles from touching jetpackers

for _, name in pairs(char_list) do
  local copy = table.deepcopy(data.raw.character[name])
  copy.name = copy.name .."-jetpack"
  copy.running_speed = 0.00001
  copy.collision_mask = {
    layers = {},
    not_colliding_with_itself = true,
  }
  copy.trigger_target_mask = trigger_target_mask
  remove_shadows_recursive(copy)
  set_render_layer_recursive(copy.animations, "air-object")
  copy.render_layer = "air-object"
  copy.footstep_particle_triggers = nil
  copy.enter_vehicle_distance = 0
  copy.localised_name = {"entity-name.jetpack-character", {"entity-name."..name}}
  copy.flags = copy.flags or {}
  copy.has_belt_immunity = true
  if copy.water_reflection then
    --copy.water_reflection.pictures.shift = {0,6} -- looks weird
    copy.water_reflection = nil
  end
  copy.hidden = true
  copy.animations =
  {
    {
      idle = animation_blank,
      idle_with_gun = animation_blank,
      mining_with_tool = animation_blank,
      running_with_gun = animation_blank,
      running = animation_blank,
    }
  }
  copy.mining_with_tool_particles_animation_positions = {} -- No mining particles or sounds
  --log( serpent.block(copy, {comment = false, numformat = '%1.8g' } ) )
  data:extend({copy})
end

data:extend({
  {
    type = "sprite",
    name = "jetpack-shadow",
    priority = "extra-high-no-scale",
    filename = "__jetpack__/graphics/entity/character/character-shadow.png",
    width = 160,
    height = 160,
    draw_as_shadow = true,
    scale = 0.5
  }
})

if data.raw.technology["fuel-processing"] and data.raw.technology["fuel-processing"].enabled then
  if data.raw.technology["jetpack-1"].prerequisites[2] == "rocket-fuel" then
    data.raw.technology["jetpack-1"].prerequisites[2] = "fuel-processing"
    -- rocket-fuel brought in the chemical-science-pack dependency indirectly
    -- if we don't have it, introduce the dependency directly
    table.insert(data.raw.technology["jetpack-1"].prerequisites, "chemical-science-pack")
  end
elseif data.raw.technology["rocket-booster-1"] and data.raw.technology["rocket-booster-1"].enabled ~= false then
  -- Angels
  if data.raw.technology["jetpack-1"].prerequisites[2] == "rocket-fuel" then
    data.raw.technology["jetpack-1"].prerequisites[2] = "rocket-booster-1"
  end
end

-- The tank uses the same equipment grid as modular armor
-- Make it use its own grid here before we change armor grids
local tank_grid = table.deepcopy(data.raw["equipment-grid"]["medium-equipment-grid"])
tank_grid.name = "tank-equipment-grid"
data.raw.car.tank.equipment_grid = tank_grid.name
data:extend({tank_grid})

for _, armor in pairs (data.raw.armor) do
  if armor.equipment_grid then
    local found = 0
    local grid = data.raw['equipment-grid'][armor.equipment_grid]
    --log (serpent.block (grid))
    if type (grid.equipment_categories) == 'string' and grid.equipment_categories == 'armor' then
      found = 1
      --log ('found string type')
    elseif type (grid.equipment_categories) == 'table' and #grid.equipment_categories > 0 then
      for _, category in pairs (grid.equipment_categories) do
        if category == "armor" and found ~= 2 then
          found = 1
          --log ('found table type')
        elseif category == 'armor-jetpack' then
          found = 2 -- measure to ensure that it doesn't add the category if it's already there
        end
      end
    end
    if found == 1 then
      grid.equipment_categories = grid.equipment_categories and grid.equipment_categories[1] and grid.equipment_categories or {grid.equipment_categories}
      table.insert (grid.equipment_categories, "armor-jetpack")
      --log ('second log: '..serpent.block (grid))
    end
  end
end
