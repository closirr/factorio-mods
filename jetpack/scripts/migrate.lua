local Migrate = {}

function Migrate.migrations()
  if not storage.version then storage.version = 0 end
  if storage.version < Version then
    if storage.version < 0003006 then Migrate.v0_3_006() end
    if storage.version < 0003012 then Migrate.v0_3_012() end
    if storage.version < 0004008 then Migrate.v0_4_008() end
  end
end

function Migrate.v0_3_006()
  storage.player_toggle_cooldown = {}
  storage.current_fuel_by_character = {}
  if storage.players then
    for player_index, playerdata in pairs(storage.players) do
      local player = game.get_player(player_index)
      if player and player.character and player.character.valid and playerdata.saved_fuel then
        storage.current_fuel_by_character[player.character.unit_number] = playerdata.saved_fuel
        -- This will miss players who are in the middle of remote view, but whatever.
      end
    end
    storage.players = nil
  end
end

function Migrate.v0_3_012()
  storage.robot_collections = storage.robot_collections or {}
  storage.disabled_on = storage.disabled_on or {}
  storage.last_printed_thrust = storage.last_printed_thrust or {}

  for _, jetpack in pairs(storage.jetpacks) do
    jetpack.speed = util.vector_length(jetpack.velocity)
    jetpack.flame_timer = 0
    jetpack.smoke_timer = 0
  end
end

function Migrate.v0_4_008()
  -- remove old rendering API shape numbers
  local function remove_if_number(jetpack, property)
    if jetpack[property] and type(jetpack[property]) == "number" then
      local rendering_object = rendering.get_object_by_id(jetpack[property])
      if rendering_object then
        rendering_object.destroy()
      end
      jetpack[property] = nil
    end
  end
  for _, jetpack in pairs(storage.jetpacks) do
    for _, property in pairs({"animation_shadow", "animation_base", "animation_mask", "animation_flame"}) do
      remove_if_number(jetpack, property)
    end
  end
end

return Migrate