local util = require("__core__/lualib/util.lua")

util.mod_prefix = "aai-" -- update strings.cfg

util.min = math.min
util.max = math.max
util.floor = math.floor
util.abs = math.abs
util.sqrt = math.sqrt
util.sin = math.sin
util.cos = math.cos
util.atan = math.atan
util.pi = math.pi
util.remove = table.remove
util.insert = table.insert
util.str_gsub = string.gsub

function util.remove_from_table(list, item)
    local index = 0
    for _,_item in ipairs(list) do
        if item == _item then
            index = _
            break
        end
    end
    if index > 0 then
        util.remove(list, index)
    end
end

function util.position_to_area(position, radius)
  return {{x = position.x - radius, y = position.y - radius},
          {x = position.x + radius, y = position.y + radius}}
end

function util.position_to_tile(position)
    return {x = math.floor(position.x), y = math.floor(position.y)}
end

function util.tile_to_position(tile_position)
    return {x = tile_position.x+0.5, y = tile_position.y+0.5}
end

function util.lerp(a, b, alpha)
    return a + (b - a) * alpha
end

function util.lerp_angles(a, b, alpha)
    local da = b - a

    if da <= -0.5 then
        da = da + 1
    elseif da >= 0.5 then
        da = da - 1
    end
    local na = a + da * alpha
    if na < 0 then
        na = na + 1
    elseif na >= 1 then
        na = na - 1
    end
    return na
end

function util.step_angles(a, b, step)
    local da = b - a

    if da <= -0.5 then
        da = da + 1
    elseif da >= 0.5 then
        da = da - 1
    end
    local na = a + Util.sign(da) * math.min(math.abs(da), step)
    if na < 0 then
        na = na + 1
    elseif na >= 1 then
        na = na - 1
    end
    return na
end

function util.array_to_vector(array)
    return {x = array[1], y = array[2]}
end

function util.vectors_delta(a, b) -- from a to b
    if not a and b then return 0 end
    return {x = b.x - a.x, y = b.y - a.y}
end

function util.vectors_delta_length(a, b)
    return util.vector_length_xy(b.x - a.x, b.y - a.y)
end

function util.vector_length(a)
    return (a.x * a.x + a.y * a.y) ^ 0.5
end

function util.vector_length_xy(x, y)
    return (x * x + y * y) ^ 0.5
end

function util.vector_dot(a, b)
    return a.x * b.x + a.y * b.y
end

function util.vector_multiply(a, multiplier)
    return {x = a.x * multiplier, y = a.y * multiplier}
end

function util.vector_dot_projection(a, b)
    local n = util.vector_normalise(a)
    local d = util.vector_dot(n, b)
    return {x = n.x * d, y = n.y * d}
end

function util.vector_normalise(a)
    local length = util.vector_length(a)
    return {x = a.x/length, y = a.y/length}
end

function util.vector_set_length(a, length)
    local old_length = util.vector_length(a)
    if old_length == 0 then return {x = 0, y = -length} end
    return {x = a.x/old_length*length, y = a.y/old_length*length}
end

function util.orientation_from_to(a, b)
    return util.vector_to_orientation_xy(b.x - a.x, b.y - a.y)
end

function util.orientation_to_vector(orientation, length)
    return {x = length * util.sin(orientation * 2 * util.pi), y = -length * util.cos(orientation * 2 * util.pi)}
end

function util.rotate_vector(orientation, a)
    return {
      x = -a.y * util.sin(orientation * 2 * util.pi) + a.x * util.sin((orientation + 0.25) * 2 * util.pi),
      y = a.y * util.cos(orientation * 2 * util.pi) -a.x * util.cos((orientation + 0.25) * 2 * util.pi)}
end

function util.vectors_add(a, b)
    return {x = a.x + b.x, y = a.y + b.y}
end

function util.lerp_vectors(a, b, alpha)
    return {x = a.x + (b.x - a.x) * alpha, y = a.y + (b.y - a.y) * alpha}
end

function util.move_to(a, b, max_distance, eliptical)
    -- move from a to b with max_distance.
    -- if eliptical, reduce y change (i.e. turret muzzle flash offset)
    local eliptical_scale = 0.9
    local delta = util.vectors_delta(a, b)
    if eliptical then
        delta.y = delta.y / eliptical_scale
    end
    local length = util.vector_length(delta)
    if (length > max_distance) then
        local partial = max_distance / length
        delta = {x = delta.x * partial, y = delta.y * partial}
    end
    if eliptical then
        delta.y = delta.y * eliptical_scale
    end
    return {x = a.x + delta.x, y = a.y + delta.y}
end

function util.vector_to_orientation(v)
    return util.vector_to_orientation_xy(v.x, v.y)
end

function util.vector_to_orientation_xy(x, y)
    if x == 0 then
        if y > 0 then
            return 0.5
        else
            return 0
        end
    elseif y == 0 then
        if x < 0 then
            return 0.75
        else
            return 0.25
        end
    else
        if y < 0 then
            if x > 0 then
                return util.atan(x / -y) / util.pi / 2
            else
                return 1 + util.atan(x / -y) / util.pi / 2
            end
        else
            return 0.5 + util.atan(x / -y) / util.pi / 2
        end
    end
end

function util.direction_to_orientation(direction)
  if direction == defines.direction.north then
    return 0
  elseif direction == defines.direction.northnortheast then
    return 0.0625
  elseif direction == defines.direction.northeast then
    return 0.125
  elseif direction == defines.direction.eastnortheast then
    return 0.1875
  elseif direction == defines.direction.east then
    return 0.25
  elseif direction == defines.direction.eastsoutheast then
    return 0.3125
  elseif direction == defines.direction.southeast then
    return 0.375
  elseif direction == defines.direction.southsoutheast then
    return 0.4375
  elseif direction == defines.direction.south then
    return 0.5
  elseif direction == defines.direction.southsouthwest then
    return 0.5625
  elseif direction == defines.direction.southwest then
    return 0.625
  elseif direction == defines.direction.westsouthwest then
    return 0.6875
  elseif direction == defines.direction.west then
    return 0.75
  elseif direction == defines.direction.westnorthwest then
    return 0.8125
  elseif direction == defines.direction.northwest then
    return 0.875
  elseif direction == defines.direction.northnorthwest then
    return 0.9375
  end
  return 0
end

function util.orientation_to_direction(orientation)
  orientation = (orientation + 0.03125) % 1
  if orientation <= 0.5 then
    if orientation <= 0.25 then
      if orientation <= 0.125 then
        return orientation <= 0.0625 and defines.direction.north or defines.direction.northnortheast
      else -- 0.125 < orientation <= 0.25
        return orientation <= 0.1875 and defines.direction.northeast or defines.direction.eastnortheast
      end
    else -- 0.25 < orientation <= 0.5
      if orientation <= 0.375 then
        return orientation <= 0.3125 and defines.direction.east or defines.direction.eastsoutheast
      else -- 0.375 < orientation <= 0.5
        return orientation <= 0.4375 and defines.direction.southeast or defines.direction.southsoutheast
      end
    end
  else -- 0.5 < orientation
    if orientation <= 0.75 then
      if orientation <= 0.625 then
        return orientation <= 0.5625 and defines.direction.south or defines.direction.southsouthwest
      else -- 0.625 < orientation <= 0.75
        return orientation <= 0.6875 and defines.direction.southwest or defines.direction.westsouthwest
      end
    else -- 0.75 < orientation <= 1
      if orientation <= 0.875 then
        return orientation <= 0.8125 and defines.direction.west or defines.direction.westnorthwest
      else -- 0.875 < orientation <= 1
        return orientation <= 0.9375 and defines.direction.northwest or defines.direction.northnorthwest
      end
    end
  end
end

function util.replace(str, what, with)
    what = util.str_gsub(what, "[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1") -- escape pattern
    with = util.str_gsub(with, "[%%]", "%%%%") -- escape replacement
    return util.str_gsub(str, what, with)
end

-- Update to using __core__ defined direction_vectors table, normalizing where the vector is not unit length.
-- local direction_to_vector = {
--   [defines.direction.east] = {x=1,y=0},
--   [defines.direction.north] = {x=0,y=-1},
--   [defines.direction.northeast] = util.vector_normalise{x=1,y=-1},
--   [defines.direction.northwest] = util.vector_normalise{x=-1,y=-1},
--   [defines.direction.south] = {x=0,y=1},
--   [defines.direction.southeast] = util.vector_normalise{x=1,y=1},
--   [defines.direction.southwest] = util.vector_normalise{x=-1,y=1},
--   [defines.direction.west] = {x=-1,y=0},
-- }
function util.direction_to_vector(direction)
  local vector = util.direction_vectors[direction]
  vector = {x=vector[1], y=vector[2]} -- direction_vectors returns {int, int}
  if util.vector_length(vector) ~= 1 then
    vector = util.vector_normalise(vector)
  end
  return vector
end

function util.sign(x)
   if x<0 then
     return -1
   elseif x>0 then
     return 1
   else
     return 0
   end
end

---Copies the given `inventory` of `src` to the same inventory of `dst`.
---@param src LuaEntity Entity to copy inventory from
---@param dst LuaEntity Entity to copy inventory to
---@param inventory defines.inventory Inventory type
function util.copy_entity_inventory(src, dst, inventory)
  local inv_src = src.get_inventory(inventory)
  local inv_dst = dst.get_inventory(inventory)

  if inv_src and inv_dst then
    util.copy_inventory(inv_src, inv_dst)
  end
end

---Copies the contents of `src` to `dst`.
---@param src LuaInventory Inventory to copy from
---@param dst LuaInventory Inventory to copy to
function util.copy_inventory(src, dst)
  if src.is_filtered() and dst.supports_filters() then
    for i = 1, math.min(#src, #dst) do
      ---@cast i uint
      dst.set_filter(i, src.get_filter(i))
      dst[i].set_stack(src[i])
    end
  else
    for i = 1, math.min(#src, #dst) do
      ---@cast i uint
      dst[i].set_stack(src[i])
    end
  end
end

function util.swap_entity_inventory(entity_a, entity_b, inventory)
  util.swap_inventory(entity_a.get_inventory(inventory), entity_b.get_inventory(inventory))
end

function util.swap_inventory(inv_a, inv_b)
  if inv_a.is_filtered() then
    for i = 1, math.min(#inv_a, #inv_b) do
      inv_b.set_filter(i, inv_a.get_filter(i))
    end
  end
  for i = 1, math.min(#inv_a, #inv_b)do
    inv_b[i].swap_stack(inv_a[i])
  end
end

---Copies the given `inventory` of `src` to the same inventory of `dst`, except for items with an item_number, which we swap instead.
---Swapping those non-fungible items instead of copying allows us to keep references on player's quickbar.
---@param src LuaEntity Entity to copy/swap inventory from
---@param dst LuaEntity Entity to copy/swap inventory to
---@param inventory defines.inventory Inventory type
function util.copy_or_swap_entity_inventory(src, dst, inventory)
  local inv_src = src.get_inventory(inventory)
  local inv_dst = dst.get_inventory(inventory)

  if inv_src and inv_dst then
    util.copy_or_swap_inventory(inv_src, inv_dst)
  end
end

---Copies the contents of `src` to `dst`, except for items with an item_number, which we swap instead.
---Swapping those non-fungible items instead of copying allows us to keep references on player's quickbar.
---@param src LuaInventory Inventory to copy from
---@param dst LuaInventory Inventory to copy to
function util.copy_or_swap_inventory(src, dst)
  if src.is_filtered() and dst.supports_filters() then
    for i = 1, math.min(#src, #dst) do
      ---@cast i uint
      dst.set_filter(i, src.get_filter(i))
      ---@cast i uint
      local src_i = src[i]
      if src[i].valid_for_read then
        if src_i.item_number then
          dst[i].swap_stack(src_i)
        else
          dst[i].set_stack(src_i)
        end
      end
    end
  else
    for i = 1, math.min(#src, #dst) do
      ---@cast i uint
      local src_i = src[i]
      if src[i].valid_for_read then
        if src_i.item_number then
          dst[i].swap_stack(src_i)
        else
          dst[i].set_stack(src_i)
        end
      end
    end
  end
end

return util
