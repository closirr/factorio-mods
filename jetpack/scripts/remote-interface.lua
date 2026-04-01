remote.add_interface(
  "jetpack",
  {

    get_jetpacks = function(data)
      if data.surface_index then
        local jetpacks = {}
        for _, jetpack in pairs(storage.jetpacks) do
          if jetpack and jetpack.character and jetpack.character.valid then
            if data.surface_index == jetpack.character.surface.index then
              jetpacks[jetpack.character.unit_number] = jetpack
            end
          end
        end
        return jetpacks
      end
      return storage.jetpacks
    end,

--/c remote.call("jetpack", "get_jetpack_for_character", {character=game.player.character})
    get_jetpack_for_character = function(data)
      if data.character and data.character.valid then
        return storage.jetpacks[data.character.unit_number]
      end
    end,

--/c remote.call("jetpack", "is_jetpacking", {character=game.player.character})
    is_jetpacking = function(data)
      if data.character and data.character.valid then
        return storage.jetpacks[data.character.unit_number] ~= nil
      else
        return false
      end
    end,

-- "current fuel" means the fuel saved on the characters. That's the fuel currently "loaded".
--/c remote.call("jetpack", "get_current_fuels")
    get_current_fuels = function()
      return storage.current_fuel_by_character
    end,

--/c remote.call("jetpack", "get_current_fuel_for_character", {character=game.player.character})
    get_current_fuel_for_character = function(data)
      if data.character and data.character.valid then
        return storage.current_fuel_by_character[data.character.unit_number]
      end
    end,

--/c remote.call("jetpack", "block_jetpack", {character=game.player.character})
    block_jetpack = function(data) -- prevents activation on character
      if data.character and data.character.valid then
        storage.disabled_on[data.character.unit_number] = data.character.unit_number
      end
    end,

--/c remote.call("jetpack", "unblock_jetpack", {character=game.player.character})
    unblock_jetpack = function(data) -- allows activation on character
      if data.character and data.character.valid then
        storage.disabled_on[data.character.unit_number] = nil
      end
    end,

--/c remote.call("jetpack", "stop_jetpack_immediate", {character=game.player.character})
    stop_jetpack_immediate = function(data) -- returns the new character.
      if data.character then
        local jetpack = Jetpack.from_character(data.character)
        if jetpack then
          return Jetpack.land_and_start_walking(jetpack)
        end
      end
    end,

    set_velocity = function(data)
      if data.unit_number and storage.jetpacks[data.unit_number] and data.velocity and data.velocity.x and data.velocity.y then
        storage.jetpacks[data.unit_number].velocity = data.velocity
        storage.jetpacks[data.unit_number].speed = Util.vector_length(data.velocity)
      end
    end,

--/c remote.call("jetpack", "swap_jetpack_character", {new_character = luaEntity, old_character_unit_number = number, old_character = luaEntity, })
--old_character_unit_number is required, old_character is optional
    swap_jetpack_character = function(data)
      if not data then return end
      local old_unit_number = data.old_character_unit_number or (data.old_character and data.old_character.valid and data.old_character.unit_number)
      local new_unit_number = data.new_character and data.new_character.valid and data.new_character.unit_number

      if old_unit_number and new_unit_number and storage.jetpacks and storage.jetpacks[old_unit_number] then
        storage.jetpacks[new_unit_number] = storage.jetpacks[old_unit_number]
        storage.jetpacks[new_unit_number].unit_number = new_unit_number
        storage.jetpacks[new_unit_number].character = data.new_character
        storage.jetpacks[new_unit_number].character_type = Jetpack.character_is_flying_version(data.new_character.name)
        storage.jetpacks[old_unit_number] = nil
      end
    end,

--/c remote.call("jetpack", "get_fuels")
    get_fuels = function()
      return storage.compatible_fuels -- No need to deepcopy it for write protection, remote interfaces already pass a copy.
    end,

-- To add your own custom fuels, have your mod implement a "jetpack_fuels" interface, which the Jetpack mod will call (in jetpack.lua).
-- Example: 
-- remote.add_interface("your-mod", {
--   jetpack_fuels = function() return {["slow-fuel"] = 0.5, ["fast-fuel"] = 1.1} end
-- })

-- informatron implementation
    informatron_menu = function(data)
      return Informatron.menu(data.player_index)
    end,

    informatron_page_content = function(data)
      return Informatron.page_content(data.page_name, data.player_index, data.element)
    end,
  }
)
