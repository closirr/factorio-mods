local Jetpack = {}

---@class jetpack_struct
  ---@field status jetpack_status
  ---@field character LuaEntity
  ---@field unit_number uint
  ---@field force_name string
  ---@field player_index uint
  ---@field velocity {x:number, y:number}
  ---@field speed float
  ---@field smoke_timer float
  ---@field flame_timer float
  ---@field altitude float
  ---@field sound LuaEntity?
  ---@field thrust float
  ---@field character_type string
  ---@field orientation float?
  ---@field last_selected_angle float?
  ---@field animation_shadow LuaRenderObject?
  ---@field animation_base LuaRenderObject?
  ---@field animation_mask LuaRenderObject?
  ---@field animation_flame LuaRenderObject?

---@class fuel_struct
  ---@field name string
  ---@field energy float
  ---@field thrust float

--TODO: interaction with vehicles?

Jetpack.on_character_swapped_event = "on_character_swapped"
--{new_unit_number = uint, old_unit_number = uint, new_character = luaEntity, old_character = luaEntity}

Jetpack.name_event = "jetpack"
Jetpack.name_character_suffix = "-jetpack"
Jetpack.name_jetpack_shadow = "jetpack-animation-shadow"
Jetpack.name_jetpack_sound = "jetpack-sound"
Jetpack.name_animation_base = "jetpack-animation"
Jetpack.name_animation_mask = "jetpack-animation-mask"
Jetpack.name_animation_flame = "jetpack-animation-flame"
Jetpack.drag = 0.01
Jetpack.brake = 0.001
Jetpack.printed_thrust_multiplier = 1000
Jetpack.thrust_multiplier_before_move = 0.001
Jetpack.shadow_base_offset = {x = 1, y = 0.1}
Jetpack.altitude_target = 3
Jetpack.altitude_base_increase = 0.01
Jetpack.altitude_percentage_increase = 0.05
Jetpack.altitude_decrease = 0.2
Jetpack.altitude_decrease_falling = Jetpack.altitude_decrease * 2
Jetpack.falling_orientation_spin = 1/12
Jetpack.fuel_use_base = 25000
Jetpack.fuel_use_thrust = 50000
Jetpack.jump_base_thrust = 0.15 -- excluding suit thrust
Jetpack.jump_thrust_multiplier = 5 -- multiplies suit thrust
Jetpack.landing_collision_snap_radius = 3
Jetpack.toggle_cooldown = 15
Jetpack.damage_cooldown = 90
Jetpack.last_selected_angle_timeout = 3000

---@type JetpackModData
Jetpack.mod_data = prototypes.mod_data["jetpack"].data
Jetpack.tile_effects = Jetpack.mod_data.tile_effects
Jetpack.bounce_entities = {}
for _, entity_name in ipairs(Jetpack.mod_data.bounce_entities) do
  if prototypes.entity[entity_name] then
    table.insert(Jetpack.bounce_entities, entity_name)
  end
end

---@type {[string]: true}
Jetpack.no_jetpacking_tiles = {}
---@type {[string]: true}
Jetpack.space_tiles = {}

for tile_name, tile_effect in pairs(Jetpack.tile_effects) do
  if tile_effect == "bounce" or tile_effect == "stop" then
    Jetpack.no_jetpacking_tiles[tile_name] = true
  elseif tile_effect == "space" then
    Jetpack.space_tiles[tile_name] = true
  end
end

---@enum jetpack_status
Jetpack.statuses = {
  walking = 1,
  spacewalking = 2,
  rising = 3,
  stopping = 4,
  falling = 5, -- After damage
  flying = 6,
}

---@type {[string]: {thrust: integer}}
Jetpack.jetpack_equipment = {
  ["jetpack-1"] = {thrust = 1},
  ["jetpack-2"] = {thrust = 2},
  ["jetpack-3"] = {thrust = 3},
  ["jetpack-4"] = {thrust = 4},
}
---@type {[string]: {thrust: integer}}
Jetpack.jetpack_armor = {
  ["se-thruster-suit"  ] = {thrust = 1},
  ["se-thruster-suit-2"] = {thrust = 2},
  ["se-thruster-suit-3"] = {thrust = 3},
  ["se-thruster-suit-4"] = {thrust = 4},
}

---@type {[string]: {thrust: number}}
Jetpack.default_fuels = { -- sorted by preference
  ["rocket-fuel"] = {thrust = 1.2},
  ["kr-advanced-fuel"] = {thrust = 1.1}, -- K2
  ["nuclear-fuel"] = {thrust = 1.1},
  ["rocket-booster"] = {thrust = 1.1}, -- Angel's petrochem
  ["kr-fuel"] = {thrust = 1}, -- K2
  ["processed-fuel"] = {thrust = 1},
  ["kr-bio-fuel"] = {thrust = 0.9}, -- K2
  ["solid-fuel"] = {thrust = 0.5},
}

local space_travel_active = script.feature_flags["space_travel"] ~= nil
---List of armors that has inherent flying capability provided by the Factorio DLC
---@type table<string, boolean>
Jetpack.armors_that_provide_flight = {}
if space_travel_active then
  for armor_name, prototype in pairs(prototypes.get_item_filtered({{filter = "type", type = "armor"}})) do
    if prototype.provides_flight then
      Jetpack.armors_that_provide_flight[armor_name] = true
    end
  end
end

-- SPACEWALK
Jetpack.spacewalk_jump_base_thrust = 0.08
Jetpack.spacewalk_base_thrust = 0.07
Jetpack.spacewalk_thrust_multiplier = 0.5
Jetpack.spacewalk_no_drag_threshold = 0.5

-- Global var to temporary keep track of newly added jetpacks without messing up the current iteration through storage.jetpacks
Jetpack.jetpacks_to_add = {}

---@param character LuaEntity
---@return true?
function Jetpack.on_space_tile(character)
  local tile = character.surface.get_tile(character.position.x, character.position.y)
  return Jetpack.space_tiles[tile.name]
end

---@param character LuaEntity
---@return jetpack_struct
function Jetpack.from_character(character)
  return storage.jetpacks[character.unit_number]
end

---@param jetpack jetpack_struct
---@return boolean
function Jetpack.is_moving(jetpack)
  return jetpack.speed > 0.001
end

---@param jetpack jetpack_struct?
---@return jetpack_status
local function get_jetpack_status(jetpack)
  if not jetpack then
    return Jetpack.statuses.walking
  else
    return jetpack.status
  end
end

---@param character LuaEntity
---@param message Any|LocalisedString
local function character_print(character, message)
  if message == nil then return end

  if character.player then
    character.player.print(message)
  end
end

-- Get first availaible fuel from inventory.
-- Does not consume any fuel.
---@param character LuaEntity
---@return fuel_struct?
local function get_fuel_from_inventory(character)
  local inventory = character.get_main_inventory()
  if not inventory then return nil end
  for _, compatible_fuel in pairs(storage.compatible_fuels) do
    local fuel_name = compatible_fuel.fuel_name
    if prototypes.item[fuel_name] then
      local count = inventory.get_item_count(fuel_name)
      if count > 0 then
        return { name = fuel_name, energy = prototypes.item[fuel_name].fuel_value, thrust = compatible_fuel.thrust }
      end
    end
  end
end

-- Get first availaible fuel, either fuel currently in use by the character, or fuel from inventory.
-- Does not consume any fuel.
---@param character LuaEntity
---@return fuel_struct?
local function get_fuel(character)
  local current_fuel = storage.current_fuel_by_character[character.unit_number]
  if current_fuel and current_fuel.energy > 0 then
    return current_fuel
  else
    return get_fuel_from_inventory(character)
  end
end

-- Take inventory fuel matching name and set it as currently used fuel by character.
---@param character LuaEntity
---@param fuel fuel_struct
---@return boolean
local function use_inventory_fuel(character, fuel)
  local inventory = character.get_main_inventory() --[[@as LuaInventory]]
  local fuel_removed = inventory.remove({name=fuel.name, count=1})
  if fuel_removed == 0 then return false end
  local item_prod_stats = character.force.get_item_production_statistics(character.surface)
  storage.current_fuel_by_character[character.unit_number] = fuel
  item_prod_stats.on_flow(fuel.name, -1)

  local burnt_result = prototypes.item[fuel.name].burnt_result
  if burnt_result then
    inventory.insert({name=burnt_result.name})
    item_prod_stats.on_flow(burnt_result.name, 1)
  end
  return true
end

---@param jetpack jetpack_struct
local function spend_fuel_energy(jetpack)
  local fuel_consumption_rate = Settings.get_setting_global("jetpack-fuel-consumption") / 100
  local character = jetpack.character
  local current_fuel = storage.current_fuel_by_character[character.unit_number]

  if not current_fuel or current_fuel.energy <= 0 then
    local stopping = true
    local fuel = get_fuel_from_inventory(character)
    if fuel then
      local thrust = Jetpack.get_current_thrust(character, fuel)
      jetpack.thrust = thrust
      if jetpack.thrust > 0 then
        use_inventory_fuel(character, fuel)
        current_fuel = fuel
        stopping = false
      end
    end
    if stopping then
      jetpack.status = Jetpack.statuses.stopping
      character_print(character, {"jetpack.ran_out_of_fuel"})
      return
    end
  end

  current_fuel.energy = current_fuel.energy - Jetpack.fuel_use_base * fuel_consumption_rate

  if character.walking_state.walking and jetpack.status ~= Jetpack.statuses.spacewalking then -- Thrusting in a direction
    current_fuel.energy = current_fuel.energy - Jetpack.fuel_use_thrust * fuel_consumption_rate
  end
end

---@type table<string, true>
local energy_shield_set = nil
local function populate_energy_shield_set()
  energy_shield_set = {}
  for energy_shield_name, _energy_shield_prototype in pairs(prototypes.get_equipment_filtered({{filter="type", type="energy-shield-equipment"}})) do
    if not string.find(energy_shield_name, "armour", 1, true) then
      energy_shield_set[energy_shield_name] = true
    end
  end
  log("energy_shield_set: " .. serpent.line(energy_shield_set))
end

---@param equipment_name string
---@return true?
local function is_energy_shield(equipment_name)
  if not energy_shield_set then populate_energy_shield_set() end
  return energy_shield_set[equipment_name]
end

---@param jetpack jetpack_struct
---@param tick uint
local function damage_shields(jetpack, tick)
  if tick%5 == 0 and jetpack.character.grid and jetpack.character.grid.shield > 0 then
    local shield_reduction = math.min(1, jetpack.speed / 10 * Settings.get_setting_global("jetpack-speed-reduces-shields") / 100)
    if shield_reduction > 0 then
      for _, eq in pairs(jetpack.character.grid.equipment) do
        if is_energy_shield(eq.name) then
          eq.shield = math.max(0, eq.shield - (eq.max_shield + 9 * eq.shield) / 10 * shield_reduction)
        end
      end
    end
  end
end

---@param player LuaPlayer
---@return boolean?
function Jetpack.is_wearing_flying_armor(player)
  local armor_inv = player.get_inventory(defines.inventory.character_armor)
  if not (armor_inv and armor_inv[1] and armor_inv[1].valid_for_read) then return end
  return Jetpack.armors_that_provide_flight[armor_inv[1].name] ~= nil
end

-- Instantly swap to walking state
---@param jetpack jetpack_struct
---@return LuaEntity?
function Jetpack.land_and_start_walking(jetpack)
  local surface = jetpack.character.surface
  local land_character
  if Jetpack.character_is_flying_version(jetpack.character.name) then
    local non_colliding = surface.find_non_colliding_position(
      util.replace(jetpack.character.name, Jetpack.name_character_suffix, ""), -- name
      jetpack.character.position, -- center
      Jetpack.landing_collision_snap_radius, --radius
      0.1, -- precision
      false --force_to_tile_center
    )
    if non_colliding then jetpack.character.teleport(non_colliding) end
    land_character = Jetpack.swap_to_land_character(jetpack.character)
  else
    land_character = jetpack.character
  end

  if land_character then
    local landing_tile = surface.get_tile(land_character.position.x, land_character.position.y)
    storage.jetpacks[jetpack.unit_number] = nil

    local player = land_character.player
    if player and Jetpack.is_wearing_flying_armor(player) then
      -- Do not start space walking. The armor will fly across space tiles.
    elseif Jetpack.space_tiles[landing_tile.name] then -- Start spacewalking, keep the jetpack object around
      jetpack.status = Jetpack.statuses.spacewalking
      jetpack.character = land_character
      jetpack.unit_number = land_character.unit_number
      jetpack.character_type = "land"
      jetpack.orientation = nil

      Jetpack.jetpacks_to_add[jetpack.unit_number] = jetpack
    else
      JetpackGraphicsSound.create_land_effects(land_character, landing_tile.name)
    end
  end

  JetpackGraphicsSound.cleanup(jetpack)

  return land_character
end

---@param surface LuaSurface
---@param position Position
---@return LuaEntity?
local function find_bounce_entity(surface, position)
  local bounce_entity = surface.find_entities_filtered({name = Jetpack.bounce_entities, position = position, limit = 1})[1]
  if not bounce_entity then return nil end

  if bounce_entity.type == "gate" and bounce_entity.is_closed() == false then
    return nil
  end

  return bounce_entity
end

---@param jetpack jetpack_struct
---@param skip_bounce_entity_check boolean?
local function movement_collision_bounce(jetpack, skip_bounce_entity_check)
  local character = jetpack.character
  local surface = character.surface
  local tiles = surface.find_tiles_filtered{area = Util.position_to_area(character.position, 1.49)}
  local best_vector
  local best_distance = math.huge
  for _, tile in pairs(tiles) do
    if not Jetpack.no_jetpacking_tiles[tile.name] then
      local position = Util.tile_to_position(tile.position)
      local v = Util.vectors_delta(character.position, position)
      local d = Util.vector_length(v)
      if d < best_distance then
        if skip_bounce_entity_check or find_bounce_entity(surface, position) == nil then
          best_distance = d
          best_vector = v
        end
      end
    end
  end
  jetpack.speed = 0.05
  if best_vector then
    jetpack.velocity = Util.vector_set_length(best_vector, jetpack.speed)
    local new_position = {x = character.position.x + jetpack.velocity.x*4, y = character.position.y + jetpack.velocity.y*4}
    character.teleport(new_position)
  else
    local x_part = jetpack.character.position.x % 1 - 0.5
    local y_part = jetpack.character.position.y % 1 - 0.5
    jetpack.velocity = {x = x_part, y = y_part}
    jetpack.velocity = Util.vector_set_length(jetpack.velocity, jetpack.speed)
  end
end

---@param jetpack jetpack_struct
---@param tick uint
---@param disallow_thrust true?
local function movement_tick(jetpack, tick, disallow_thrust)
  local spacewalking = jetpack.status == Jetpack.statuses.spacewalking
  local character = jetpack.character
  local surface = character.surface

  -- drag
  if spacewalking then
    if jetpack.speed > Jetpack.spacewalk_no_drag_threshold then
      local m = 1 - Jetpack.drag * (jetpack.speed - Jetpack.spacewalk_no_drag_threshold) / jetpack.speed -- reduction
      jetpack.velocity.x = jetpack.velocity.x * m
      jetpack.velocity.y = jetpack.velocity.y * m
      jetpack.speed = jetpack.speed * m
    end
  else
    jetpack.velocity.x = jetpack.velocity.x * (1-Jetpack.drag)
    jetpack.velocity.y = jetpack.velocity.y * (1-Jetpack.drag)
    jetpack.speed = jetpack.speed * (1-Jetpack.drag)
    damage_shields(jetpack, tick)
  end

  local walking_state = character.walking_state
  if walking_state.walking and not disallow_thrust then -- Player is pressing a direction
    local direction_vector = util.direction_to_vector(walking_state.direction)
    local thrust
    if spacewalking then
      thrust = Jetpack.spacewalk_base_thrust
      JetpackGraphicsSound.create_spacewalking_smoke(character)
    else
      thrust = jetpack.thrust -- get from equipment + fuel
    end
    thrust = thrust * Jetpack.thrust_multiplier_before_move
    local thrust_vector = {x = direction_vector.x * thrust, y = direction_vector.y * thrust}
    jetpack.velocity.x = jetpack.velocity.x + thrust_vector.x
    jetpack.velocity.y = jetpack.velocity.y + thrust_vector.y
    jetpack.speed = util.vector_length(jetpack.velocity)

  elseif not spacewalking then -- Not pressing a direction, slow down (except when spacewalking)
    local new_speed = jetpack.speed - Jetpack.brake
    if new_speed < 0.001 then
      jetpack.velocity.x = 0
      jetpack.velocity.y = 0
      jetpack.speed = 0
    else
      jetpack.velocity.x = jetpack.velocity.x * new_speed / jetpack.speed
      jetpack.velocity.y = jetpack.velocity.y * new_speed / jetpack.speed
      jetpack.speed = new_speed
    end
  end

  local new_position = {x = character.position.x + jetpack.velocity.x, y = character.position.y + jetpack.velocity.y}

  local target_tile = surface.get_tile(new_position.x, new_position.y)
  if target_tile then
    local tile_effect = Jetpack.tile_effects[target_tile.name]
    if tile_effect == "bounce" then -- always bounce off these tiles
      movement_collision_bounce(jetpack, true)
      return
    elseif tile_effect == "bump" then -- bounce if there is something to bump into
      if find_bounce_entity(surface, util.tile_to_position(target_tile.position)) then
        movement_collision_bounce(jetpack, false)
        return
      end
    elseif tile_effect == "stop" then -- bounce if there is something to bump into, or stop the jetpack
      if find_bounce_entity(surface, util.tile_to_position(target_tile.position)) then
        movement_collision_bounce(jetpack, true)
      else
        -- Instant stop
        character.teleport(new_position)
        Jetpack.land_and_start_walking(jetpack)
      end
      return
    end
    if Jetpack.is_moving(jetpack) then
      character.teleport(new_position)
       -- End of spacewalking
       -- We do this here instead of on_player_changed_position because a character could be moving without a player attached.
       -- e.g. remote view in SE
      if spacewalking and not Jetpack.space_tiles[target_tile.name] then
        storage.jetpacks[jetpack.unit_number] = nil -- "walking"
        JetpackGraphicsSound.create_land_effects(jetpack.character, target_tile.name)
      end
    end
  else
    jetpack.velocity.x = jetpack.velocity.x / 2
    jetpack.velocity.y = jetpack.velocity.y / 2
    jetpack.speed = jetpack.speed / 2
  end
end

---@param jetpack jetpack_struct
---@param tick uint
local function on_tick_flying(jetpack, tick)
  spend_fuel_energy(jetpack)
  movement_tick(jetpack, tick)
  if jetpack.character.valid then -- Could have instantly landed in movement_tick
    JetpackGraphicsSound.update_graphics(jetpack)
    JetpackGraphicsSound.update_sound(jetpack, tick)
    JetpackGraphicsSound.create_smoke(jetpack)
  end
end

local function on_tick_spacewalking(jetpack, tick)
  movement_tick(jetpack, tick)
end

---@param jetpack jetpack_struct
---@param tick uint
local function on_tick_rising(jetpack, tick)
  if jetpack.altitude < Jetpack.altitude_target then
    local difference = Jetpack.altitude_target - jetpack.altitude
    local change =  math.min(difference, difference * Jetpack.altitude_percentage_increase + Jetpack.altitude_base_increase)
    jetpack.altitude = jetpack.altitude + change
    jetpack.character.teleport({x = jetpack.character.position.x, y = jetpack.character.position.y - change})
  else
    jetpack.status = Jetpack.statuses.flying
  end

  on_tick_flying(jetpack, tick)
end

---@param jetpack jetpack_struct
---@param tick uint
local function on_tick_stopping(jetpack, tick)
  if jetpack.altitude > 0 then
    jetpack.altitude = math.max(0, jetpack.altitude - Jetpack.altitude_decrease)
    jetpack.character.teleport({x = jetpack.character.position.x, y = jetpack.character.position.y + Jetpack.altitude_decrease})
    movement_tick(jetpack, tick)
    if jetpack.character.valid then -- Could have instantly landed in movement_tick
      JetpackGraphicsSound.update_graphics(jetpack)
      JetpackGraphicsSound.update_sound(jetpack, tick)
    end
  else -- Reached the floor
    Jetpack.land_and_start_walking(jetpack)
  end
end

---@param jetpack jetpack_struct
---@param tick uint
local function on_tick_falling(jetpack, tick)
  if jetpack.altitude > 0 then
    jetpack.altitude = math.max(0, jetpack.altitude - Jetpack.altitude_decrease_falling)
    jetpack.character.teleport({x = jetpack.character.position.x, y = jetpack.character.position.y + Jetpack.altitude_decrease})
    jetpack.orientation = jetpack.orientation + Jetpack.falling_orientation_spin -- Spin
    movement_tick(jetpack, tick, true) -- Momentum, but disallow thrust
    if jetpack.character.valid then -- Could have instantly landed in movement_tick
      JetpackGraphicsSound.update_graphics(jetpack)
      JetpackGraphicsSound.update_sound(jetpack, tick)
    end
  else -- Reached the floor
    local landing_tile_name = jetpack.character.surface.get_tile(jetpack.character.position.x, jetpack.character.position.y).name
    if not Jetpack.space_tiles[landing_tile_name] then
      jetpack.character.surface.create_entity({name="small-scorchmark-tintable", position=jetpack.character.position})
      JetpackGraphicsSound.create_land_effects(jetpack.character, landing_tile_name, 4, 1.8) -- Some extra dust circles
    end
    Jetpack.land_and_start_walking(jetpack)
  end
end

---@type {jetpack_status: fun(jetpack_struct, uint)}
local on_tick_actions = {
  [Jetpack.statuses.flying] = on_tick_flying,
  [Jetpack.statuses.spacewalking] = on_tick_spacewalking,
  [Jetpack.statuses.rising] = on_tick_rising,
  [Jetpack.statuses.stopping] = on_tick_stopping,
  [Jetpack.statuses.falling] = on_tick_falling,
}

---@param jetpack jetpack_struct
---@param tick uint
function Jetpack.on_tick_jetpack(jetpack, tick)

  -- Character died or was destroyed
  if not (jetpack.character and jetpack.character.valid) then
    storage.jetpacks[jetpack.unit_number] = nil
    return JetpackGraphicsSound.cleanup(jetpack)
  end

  local action = on_tick_actions[jetpack.status]
  if action then
    action(jetpack, tick)
  end -- else is "walking", do nothing
end

---@param event EventData.on_tick
function Jetpack.on_tick(event)
  for _unit_number, jetpack in pairs(storage.jetpacks) do
    Jetpack.on_tick_jetpack(jetpack, event.tick)
  end

  for unit_number, jetpack in pairs(Jetpack.jetpacks_to_add) do
    storage.jetpacks[unit_number] = jetpack
    Jetpack.jetpacks_to_add[unit_number] = nil
  end

  -- Re-attach personal construction bots after character swap
  for k, robot_collection in pairs(storage.robot_collections) do
    if not (robot_collection.character and robot_collection.character.valid) then
      storage.robot_collections[k] = nil
    elseif robot_collection.character.logistic_cell and robot_collection.character.logistic_cell.valid
      and robot_collection.character.logistic_cell.logistic_network and robot_collection.character.logistic_cell.logistic_network.valid then
      for _, robot in pairs(robot_collection.robots) do
        if robot.valid and robot.surface == robot_collection.character.surface then
          robot.logistic_network = robot_collection.character.logistic_cell.logistic_network
        end
      end
      storage.robot_collections[k] = nil
    end
  end
end
Event.addListener(defines.events.on_tick, Jetpack.on_tick)

---@param old LuaEntity
---@param new_name string
---@return LuaEntity?
local function swap_character(old, new_name)
  if not prototypes.entity[new_name] then return end
  local buffer_capacity = 1000
  local position = old.position
  if not Jetpack.character_is_flying_version(new_name) then
    position = old.surface.find_non_colliding_position(new_name, position, 1, 0.25, false) or position
  end
  local new = old.player.surface.create_entity({
    name = new_name,
    position = position,
    force = old.force,
    direction = old.direction, -- Factorio bug: Diagonals are forced into cardinal directions
  }) --[[@as LuaEntity]]

  local follow_list = storage.following_spidertrons[old.unit_number]
  if follow_list then
    for follower_unit_number, follower in pairs(follow_list) do
      if follower and follower.valid then
        local follow_target = follower.follow_target
        if follow_target and follow_target == old then
          local old_follow_offset = follower.follow_offset
          follower.follow_target = new
          follower.follow_offset = old_follow_offset
        else
          follow_list[follower_unit_number] = nil
        end
      end
    end
  end
  storage.following_spidertrons[new.unit_number] = follow_list
  storage.following_spidertrons[old.unit_number] = nil

  for _, robot in pairs (old.following_robots) do
    robot.combat_robot_owner = new
  end

  new.character_inventory_slots_bonus = old.character_inventory_slots_bonus + buffer_capacity
  old.character_inventory_slots_bonus = old.character_inventory_slots_bonus + buffer_capacity

  -- Save crafting queue
  local vehicle = old.vehicle
  local save_queue = nil
  local crafting_queue_progress = old.crafting_queue_progress
  if old.crafting_queue then
    save_queue = {}
    for i = old.crafting_queue_size, 1, -1 do
      if old.crafting_queue and old.crafting_queue[i] then
        table.insert(save_queue, old.crafting_queue[i])
        old.cancel_crafting(old.crafting_queue[i])
      end
    end
  end

  -- Save personal construction robots
  if old.logistic_cell and old.logistic_cell.logistic_network and #old.logistic_cell.logistic_network.robots > 0 then
    table.insert(storage.robot_collections, {character = new, robots = old.logistic_cell.logistic_network.robots})
  end

  new.character_health_bonus = old.character_health_bonus
  new.character_crafting_speed_modifier = old.character_crafting_speed_modifier
  new.character_mining_speed_modifier = old.character_mining_speed_modifier
  new.character_running_speed_modifier = old.character_running_speed_modifier
  new.character_build_distance_bonus = old.character_build_distance_bonus
  new.character_reach_distance_bonus = old.character_reach_distance_bonus
  new.character_resource_reach_distance_bonus = old.character_resource_reach_distance_bonus
  new.character_item_pickup_distance_bonus = old.character_item_pickup_distance_bonus
  new.character_loot_pickup_distance_bonus = old.character_loot_pickup_distance_bonus
  new.character_item_drop_distance_bonus = old.character_item_drop_distance_bonus
  new.character_inventory_slots_bonus = old.character_inventory_slots_bonus
  new.character_trash_slot_count_bonus = old.character_trash_slot_count_bonus
  new.character_maximum_following_robot_count_bonus = old.character_maximum_following_robot_count_bonus
  new.health = old.health
  new.copy_settings(old)
  new.selected_gun_index = old.selected_gun_index

  -- Copy personal logistic requests
  local old_logi_point = old.get_logistic_point(defines.logistic_member_index.character_requester)
  local new_logi_point = new.get_logistic_point(defines.logistic_member_index.character_requester)
  if old_logi_point and new_logi_point then
    new_logi_point.enabled = old_logi_point.enabled
    new_logi_point.trash_not_requested = old_logi_point.trash_not_requested
    -- Ensure we are working from a clean slate. (New characters start with a default section)
    for i = 1, new_logi_point.sections_count do
      new_logi_point.remove_section(i)
    end
    for i, logi_section in pairs(old_logi_point.sections) do
      local new_section
      if logi_section.group and logi_section.group ~= "" then
        new_section = new_logi_point.add_section(logi_section.group)
      else -- "[No group assigned]" section
        new_section = new_logi_point.add_section()
        new_section.filters = logi_section.filters
      end
      new_section.active = logi_section.active
      new_section.multiplier = logi_section.multiplier
    end
  end
  new.allow_dispatching_robots = old.allow_dispatching_robots

  local hand_location
  local cursor_ghost
  local cursor_stack_temporary
  local opened_armor
  local spidertron_remote_selection

  local old_position
  local old_surface
  local old_controller
  local old_zoom
  if old.player then
    hand_location = old.player.hand_location
    cursor_ghost = old.player.cursor_ghost
    spidertron_remote_selection = old.player.spidertron_remote_selection  -- API limitation: only saves selection if remote in hand, otherwise it is lost

    -- Set cooldown only if there's no higher cooldown already in place
    if not storage.player_toggle_cooldown[old.player.index] or storage.player_toggle_cooldown[old.player.index] < game.tick + Jetpack.toggle_cooldown then
      storage.player_toggle_cooldown[old.player.index] = game.tick + Jetpack.toggle_cooldown
    end

    -- Handles players holding temporary blueprints e.g. blank upgrade, deconstruction planners, copy paste
    cursor_stack_temporary = old.player.cursor_stack_temporary

    -- Swap character controlled
    local opened_self = old.player.opened_self
    opened_armor = old.player.opened == old.grid
    old_position = old.player.position
    old_surface = old.player.surface
    old_controller = old.player.controller_type
    old_zoom = old.player.zoom
    old.player.set_controller{type=defines.controllers.character, character=new}
    new.teleport(position,old.surface,false,false)
    if opened_self then new.player.opened = new end
  end

  -- Much faster (and easier) to just transfer armor from one character to the other.
  -- The problem is this changes the inventory size of `old` which causes a slow recalc of the logistic networks with large inventory sizes.
  -- If that issue is ever fixed, change to this code instead of copying everything in the grid.
  -- `buffer` should handle inventory overflow during the swap.

  --[[
  local old_inv_armor_slot = old.get_inventory(defines.inventory.character_armor)[1]
  if old_inv_armor_slot and old_inv_armor_slot.valid_for_read then
    local new_inv_armor = new.get_inventory(defines.inventory.character_armor)
    new.get_inventory(defines.inventory.character_armor)[1].swap_stack(old_inv_armor_slot)
    if opened_armor and player then
      player.opened = new_inv_armor[1]
    end
  end
  ]]

  -- need to stop inventory overflow when armor is swapped
  local old_inv = old.get_inventory(defines.inventory.character_armor)
  if old_inv and old_inv[1] and old_inv[1].valid_for_read then
    local new_inv = new.get_inventory(defines.inventory.character_armor)
    new_inv.insert({name = old_inv[1].name, count = 1})
    if opened_armor and new.player then
      new.player.opened = new_inv[1]
    end
  end

  -- With the introduction of util.copy_or_swap_entity_inventory(old, new, defines.inventory.character_armor) below,
  -- we no longer need to actually copy the grid over as we instead copy/swap the armour inventory itself.

  if new.player then
    new.cursor_stack.swap_stack(old.cursor_stack)
    new.player.cursor_stack_temporary = cursor_stack_temporary
    new.player.spidertron_remote_selection = spidertron_remote_selection

    if hand_location then
      new.player.hand_location = hand_location
    end
    if old_controller == defines.controllers.remote then
      new.player.set_controller{type=defines.controllers.remote, position=old_position, surface=old_surface}
    end
    new.player.zoom = old_zoom
    if cursor_ghost then
      new.player.cursor_ghost = cursor_ghost
    end
  end

  -- Copy as much as we can for performance gains.
  -- Swap non-fungible items (remotes, blueprints, etc.) to keep quickbar references.
  util.copy_or_swap_entity_inventory(old, new, defines.inventory.character_main)
  util.copy_or_swap_entity_inventory(old, new, defines.inventory.character_trash)
  util.copy_or_swap_entity_inventory(old, new, defines.inventory.character_armor)
  util.copy_entity_inventory(old, new, defines.inventory.character_guns)
  util.copy_entity_inventory(old, new, defines.inventory.character_ammo)

  if save_queue then
    for i = #save_queue, 1, -1 do
      local cci = save_queue[i]
      if cci then
        cci.silent = true
        new.begin_crafting(cci)
      end
    end
    new.crafting_queue_progress = math.min(1, crafting_queue_progress)
  end
  new.character_inventory_slots_bonus = new.character_inventory_slots_bonus - buffer_capacity -- needs to be before raise_event

  if storage.current_fuel_by_character[old.unit_number] then
    storage.current_fuel_by_character[new.unit_number] = storage.current_fuel_by_character[old.unit_number]
    storage.current_fuel_by_character[old.unit_number] = nil
  end

  raise_event(Jetpack.on_character_swapped_event, {
      new_unit_number = new.unit_number,
      old_unit_number = old.unit_number,
      new_character = new,
      old_character = old
    })
  if old.valid then
    old.destroy()
  end
  if vehicle then
    if not vehicle.get_driver() then
      vehicle.set_driver(new)
    elseif not vehicle.get_passenger() then
      vehicle.set_passenger(new)
    end
  end

  return new
end

---@param old_character LuaEntity
---@return LuaEntity?
function Jetpack.swap_to_land_character(old_character)
  return swap_character(old_character, util.replace(old_character.name, Jetpack.name_character_suffix, ""))
end

---@param old_character LuaEntity
---@return LuaEntity?
function Jetpack.swap_to_flying_character(old_character)
  return swap_character(old_character, old_character.name .. Jetpack.name_character_suffix)
end

---@param event EventData.on_player_placed_equipment|EventData.on_player_removed_equipment|EventData.on_player_armor_inventory_changed
function Jetpack.on_armor_changed(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  if player.character then
    local character = player.character
    local jetpack = Jetpack.from_character(character)
    if jetpack then
      local fuel = get_fuel(character)
      local thrust = Jetpack.get_current_thrust(character, fuel)
      jetpack.thrust = thrust
      if thrust <= 0 then
        jetpack.status = Jetpack.statuses.stopping
      end
    end
  end
end
Event.addListener(defines.events.on_player_placed_equipment, Jetpack.on_armor_changed)
Event.addListener(defines.events.on_player_removed_equipment, Jetpack.on_armor_changed)
Event.addListener(defines.events.on_player_armor_inventory_changed, Jetpack.on_armor_changed)

---@param character LuaEntity
---@return float
local function get_current_jetpack_equipment_thrust(character)
  local armor_thrust = 0
  -- thruster suits have thrust
  local armor_inv = character.get_inventory(defines.inventory.character_armor)
  if armor_inv and armor_inv[1] and armor_inv[1].valid_for_read then
    local armor = armor_inv[1]
    if Jetpack.jetpack_armor[armor.name] then
      armor_thrust = armor_thrust + Jetpack.jetpack_armor[armor.name].thrust
    end
  end

  local thrust = armor_thrust
  -- jetpack equipment has thrust
  if character.grid then
    for _, equipment in pairs(character.grid.get_contents()) do
      local name = equipment.name
      local count = equipment.count
      if Jetpack.jetpack_equipment[name] ~= nil then
        if Settings.get_setting_global("jetpack-thrust-stacks") then
          thrust = thrust + count * (Jetpack.jetpack_equipment[name].thrust or 0)
        else
          local this_thrust = armor_thrust + Jetpack.jetpack_equipment[name].thrust
          if this_thrust > thrust then
            thrust = this_thrust
          end
        end
      end
    end
  end

  return thrust --[[@as float]]
end

---@param character LuaEntity
---@param fuel fuel_struct?
---@return float
function Jetpack.get_current_thrust(character, fuel)
  if not fuel then return 0 end

  local thrust = get_current_jetpack_equipment_thrust(character)

  if thrust == 0 then return 0 end -- No jetpack equipment, no need to go further.

  -- Apply fuel multiplier
  local fuel_thrust_multiplier = fuel.thrust or 1
  thrust = thrust * fuel_thrust_multiplier

  -- Slow down with weight
  local grid_slots = character.grid and (character.grid.width * character.grid.height) or 0
  local weight = #character.get_main_inventory() / 10 + grid_slots
  local final_thrust = Jetpack.printed_thrust_multiplier * thrust / weight

  -- Print thrust
  if character.player and Settings.get_setting_player(character.player.index, "jetpack-print-thrust") then
    if fuel and final_thrust ~= storage.last_printed_thrust[character.player.index] then -- Don't print thrust when you have no fuel
      if fuel_thrust_multiplier == 1 then
        character.player.print({"jetpack.jetpack_acceleration", string.format("%.2f", final_thrust)})
      else
        local fuel_bonus_percentage = string.format("%.f", (fuel_thrust_multiplier - 1) * 100)
        if fuel_thrust_multiplier > 1 then fuel_bonus_percentage = "+" .. fuel_bonus_percentage end
        local fuel_prototype = prototypes.item[fuel.name]
        local fuel_icon = "[img=item/" ..fuel.name.. "]"
        local fuel_localised_name = fuel_prototype and fuel_prototype.localised_name or "Unknown fuel"
        character.player.print({"jetpack.jetpack_acceleration_with_fuel_bonus", string.format("%.2f", final_thrust), fuel_bonus_percentage, fuel_icon, fuel_localised_name})
      end
      storage.last_printed_thrust[character.player.index] = final_thrust
    end
  end

  return final_thrust ^ 0.5 --[[@as float]]
end

function Jetpack.character_is_flying_version(name)
  if string.find(name, Jetpack.name_character_suffix, 1, true) then return true else return false end
end

-- Creates a new jetpack object and swaps character if needed.
-- Sometimes character swap is not needed, e.g. from walking to spacewalking.
-- This method always assumes the character starts from walking state.
---@param character LuaEntity
---@param thrust float
---@param default_status jetpack_status
---@return jetpack_struct?
function Jetpack.start_on_character(character, thrust, default_status)
  default_status = default_status or Jetpack.statuses.rising
  local player = character.player
  local force_name = character.force.name

  if not player then return end
  if character.vehicle or character.cargo_pod or character.hub or storage.disabled_on[character.unit_number] then return end

  local tile = character.surface.get_tile(character.position.x, character.position.y)
  if Jetpack.no_jetpacking_tiles[tile.name] then
    character_print(character, Jetpack.mod_data.optional_takeoff_blocked_message[tile.name])
    return
  end

  local walking_state = character.walking_state
  local new_character
  if default_status == Jetpack.statuses.rising or default_status == Jetpack.statuses.flying then
    if not Jetpack.character_is_flying_version(character.name) then
      new_character = Jetpack.swap_to_flying_character(character)
      if not new_character then
        for _, jetpack in pairs(storage.jetpacks) do
          if jetpack.character == character then return end
        end
        new_character = character
      end
    end
  else
    if Jetpack.character_is_flying_version(character.name) then
      new_character = Jetpack.swap_to_land_character(character)
      if not new_character then
        for _, jetpack in pairs(storage.jetpacks) do
          if jetpack.character == character then return end
        end
        new_character = character
      end
    end
  end
  ---@type jetpack_struct
  local jetpack = {
    status = default_status,
    character = new_character or character,
    unit_number = new_character and new_character.unit_number or character.unit_number,
    force_name = force_name,
    player_index = player.index,
    velocity = {x=0, y=0},
    speed = 0,
    smoke_timer = 0,
    flame_timer = 0,
    altitude = 0,
    thrust = thrust,
    character_type = (default_status == Jetpack.statuses.rising or default_status == Jetpack.statuses.flying) and "fly" or "land"
  }
  if walking_state.walking == true then
    local direction_vector = util.direction_to_vector(walking_state.direction)
    if direction_vector then
      local thrust = Jetpack.thrust_multiplier_before_move * jetpack.thrust -- get from equipment + fuel
      local base_thrust = jetpack.status == Jetpack.statuses.spacewalking and Jetpack.spacewalk_jump_base_thrust or Jetpack.jump_base_thrust
      jetpack.velocity.x = direction_vector.x * (base_thrust + Jetpack.jump_thrust_multiplier * thrust)
      jetpack.velocity.y = direction_vector.y * (base_thrust + Jetpack.jump_thrust_multiplier * thrust)
      jetpack.speed = base_thrust + Jetpack.jump_thrust_multiplier * thrust
    end
  end
  JetpackGraphicsSound.update_graphics(jetpack)
  JetpackGraphicsSound.update_sound(jetpack, game.tick)
  Jetpack.jetpacks_to_add[jetpack.unit_number] = jetpack
  return jetpack
end

---@param event EventData.on_player_changed_position
function Jetpack.on_player_changed_position(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  if player and player.connected and player.character then
    local jetpack = Jetpack.from_character(player.character)
    if not jetpack  -- "walking"
      and Jetpack.on_space_tile(player.character)
      and not Jetpack.is_wearing_flying_armor(player) then
      -- Starting spacewalking
      local character = player.character
      Jetpack.start_on_character(character, 0, Jetpack.statuses.spacewalking)
    end
  end
end
Event.addListener(defines.events.on_player_changed_position, Jetpack.on_player_changed_position)

---@param event EventData.on_player_joined_game
function Jetpack.on_player_joined_game(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  if player and player.connected and player.character then
    if Jetpack.character_is_flying_version(player.character.name) then
      local character = player.character
      local fuel = get_fuel(character)
      local thrust = Jetpack.get_current_thrust(character, fuel)
      local jetpack = Jetpack.start_on_character(character, thrust, Jetpack.statuses.flying)
      if jetpack then
        jetpack.altitude = Jetpack.altitude_target
      end
    end
  end
end
Event.addListener(defines.events.on_player_joined_game, Jetpack.on_player_joined_game)

---@param event EventData.on_entity_damaged
function Jetpack.on_character_damaged(event)
  if Settings.get_setting_global("jetpack-fall-on-damage") then
    local jetpack = Jetpack.from_character(event.entity)
    local status = get_jetpack_status(jetpack)
    if event.damage_type.name ~= "suffocation" and event.damage_type.name ~= "radioactive" -- Don't fall down from SE's suffocation and K2's uranium
    and (status == Jetpack.statuses.flying or status == Jetpack.statuses.rising or status == Jetpack.statuses.stopping) then
      jetpack.status = Jetpack.statuses.falling
      -- jetpack.altitude_decrease = Jetpack.altitude_decrease * 2 -- Fall twice as fast
      JetpackGraphicsSound.create_damage_effects(jetpack.character)
      local player = event.entity.player
      if player then -- If you detach your character just before getting hit then you avoid the cooldown, sure to be a crucial speedrunning technique lol
        storage.player_toggle_cooldown[player.index] = event.tick + Jetpack.damage_cooldown
      end
    end
  end
end
script.on_event(defines.events.on_entity_damaged, Jetpack.on_character_damaged, {{filter="type", type = "character"}})

---@param jetpack jetpack_struct
function Jetpack.stop_jetpack(jetpack)
  jetpack.status = Jetpack.statuses.stopping
end

---@param character LuaEntity
function Jetpack.toggle(character)
  local jetpack = Jetpack.from_character(character)
  local status = get_jetpack_status(jetpack)

  -- To prevent enableing/disabling a Jetpack while using the remote controller.
  if storage.disabled_on[character.unit_number] then return end

  if status == Jetpack.statuses.walking or status == Jetpack.statuses.spacewalking or status == Jetpack.statuses.stopping then
    if character.vehicle then character.player.play_sound{path="utility/cannot_build"} return end

    local fuel = get_fuel(character)
    if not fuel then
      if get_current_jetpack_equipment_thrust(character) == 0 then -- Warn about no jetpack before no fuel
        character_print(character, {"jetpack.need_jetpack"})
      else
        character_print(character, {"jetpack.need_fuel"})
      end
      return
    end

    local thrust = Jetpack.get_current_thrust(character, fuel)
    if thrust == 0 then
      character_print(character, {"jetpack.need_jetpack"})
      return
    end

    if status == Jetpack.statuses.walking then
      Jetpack.start_on_character(character, thrust, Jetpack.statuses.rising)

    elseif status == Jetpack.statuses.spacewalking then
      -- Swap jetpack type from spacewalking to flying
      local flying_character = Jetpack.swap_to_flying_character(character)
      if flying_character then
        storage.jetpacks[jetpack.unit_number] = nil

        jetpack.character = flying_character
        jetpack.unit_number = flying_character.unit_number
        jetpack.status = Jetpack.statuses.rising
        jetpack.character_type = "fly"
        jetpack.orientation = nil
        jetpack.thrust = thrust

        Jetpack.jetpacks_to_add[jetpack.unit_number] = jetpack
      end

    else -- "stopping"
      jetpack.status = Jetpack.statuses.rising
      jetpack.thrust = thrust
    end
  else -- rising or flying
    jetpack.status = Jetpack.statuses.stopping
  end
end

---@param event EventData.CustomInputEvent
function Jetpack.on_jetpack_keypress(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  if player.character then
    if (not storage.player_toggle_cooldown[event.player_index]) or storage.player_toggle_cooldown[event.player_index] < event.tick then
      storage.player_toggle_cooldown[event.player_index] = event.tick + Jetpack.toggle_cooldown
      Jetpack.toggle(player.character)
    else
      player.play_sound{path="utility/cannot_build"}
    end
  end
end
Event.addListener(Jetpack.name_event, Jetpack.on_jetpack_keypress)

-- As far as I can tell, when flying you can only enter vehicles via scripts.
-- For example, ironclad.
---@param event EventData.on_player_driving_changed_state
function Jetpack.on_player_driving_changed_state(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  if not player or not player.character or not player.character.valid then return end
  local jetpack = Jetpack.from_character(player.character)
  if not jetpack or not jetpack.character.valid then return end

  if Jetpack.character_is_flying_version(jetpack.character.name) then
    Jetpack.land_and_start_walking(jetpack)
  end
end
script.on_event(defines.events.on_player_driving_changed_state, Jetpack.on_player_driving_changed_state)

---@param event EventData.on_player_used_spidertron_remote
function Jetpack.on_player_used_spidertron_remote(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  local spidertrons = player.spidertron_remote_selection
  for _, spidertron in pairs(spidertrons or {}) do
    local target = spidertron.follow_target
    if target and target.type == "character" then
      -- Add the spidertron to the follow list of the player
      local follow_list = storage.following_spidertrons[target.unit_number] or {}
      follow_list[spidertron.unit_number] = spidertron
      storage.following_spidertrons[target.unit_number] = follow_list
    end
  end
end
script.on_event(defines.events.on_player_used_spidertron_remote, Jetpack.on_player_used_spidertron_remote)

local function load_compatible_fuels()
  local compatible_fuels_table = Jetpack.default_fuels
  for interface, functions in pairs(remote.interfaces) do
    if functions["jetpack_fuels"] then
      local mod_fuels = remote.call(interface, "jetpack_fuels")
      if mod_fuels then
        ---@cast mod_fuels table
        for fuel_name, thrust in pairs(mod_fuels) do
          if not compatible_fuels_table[fuel_name] then
            compatible_fuels_table[fuel_name] = {thrust = math.min(1.1, tonumber(thrust) or 1)}
          end
        end
      end
    end
  end

  -- Convert table to array so we can have an order, for prioritisation of fuels
  storage.compatible_fuels = {}
  for fuel_name, fuel_stats in pairs(compatible_fuels_table) do
    table.insert(storage.compatible_fuels, {fuel_name = fuel_name, thrust = fuel_stats.thrust})
  end
  table.sort(storage.compatible_fuels, function(a, b) return a.thrust > b.thrust end) -- Higher thrust first
end

---@param event EventData.on_player_controller_changed
function Jetpack.on_player_controller_changed(event)
  -- 29/10/2024 This code was added to prevent changing Jetpack state while in Remote View as it caused crashes.
  -- Now that the swap code no longer causes a crash we can allow changing state manually during a Remote View.
  -- The only side effect is still the "zoom" change that requires an update to the Factorio Lua API to let us
  -- Read the previous zoom, so we can set it again after (we already can Write zoom, just no way of reading it).

  -- -- Same as remote call "block_jetpack" we have to handle the remote view and prevent Jetpack changes.
  -- local player = game.players[event.player_index]
  -- if    player.controller_type == defines.controllers.remote
  --   and event.old_type == defines.controllers.character
  --   and player.character
  --   and player.character.valid
  -- then
  --   storage.disabled_on[player.character.unit_number] = player.character.unit_number
  -- end

  -- -- Same as remote call "unblock_jetpack" we have to handle the remote view and reenable Jetpack changes.
  -- if    player.controller_type == defines.controllers.character
  --   and event.old_type == defines.controllers.remote
  --   and player.character
  --   and player.character.valid
  -- then
  --   storage.disabled_on[player.character.unit_number] = nil
  -- end
end
Event.addListener(defines.events.on_player_controller_changed, Jetpack.on_player_controller_changed)

---@param event EventData.on_pre_player_toggled_map_editor
function Jetpack.on_pre_player_toggled_map_editor(event)
  local player = game.get_player(event.player_index)
  if player.character and Jetpack.character_is_flying_version(player.character.name) then
    local jetpack = Jetpack.from_character(player.character)
    jetpack.character.teleport({jetpack.character.position.x, jetpack.character.position.y + jetpack.altitude})
    Jetpack.land_and_start_walking(jetpack)
  end
end
Event.addListener(defines.events.on_pre_player_toggled_map_editor, Jetpack.on_pre_player_toggled_map_editor)

function Jetpack.on_init()
  storage.jetpacks = {}
  storage.current_fuel_by_character = {}
  storage.player_toggle_cooldown = {}
  storage.robot_collections = {}
  storage.disabled_on = {}
  storage.last_printed_thrust = {}
  storage.following_spidertrons = {}
  load_compatible_fuels()
end
Event.addListener("on_init", Jetpack.on_init, true)

local function on_configuration_changed()
  storage.following_spidertrons = storage.following_spidertrons or {}
  load_compatible_fuels()
end
Event.addListener("on_configuration_changed", on_configuration_changed, true)

return Jetpack
