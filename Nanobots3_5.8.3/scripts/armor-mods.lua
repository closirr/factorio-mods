-------------------------------------------------------------------------------
--[[armormods]] -- Power Armor module code.
-------------------------------------------------------------------------------
local armormods = {}
local table = require('__stdlib2__/stdlib/utils/table')

local config = require('config')

-- v5.2.1: Add SafeEntity for safe entity operations
local SafeEntity = require('scripts/safe_entity')

--TODO: Store this in storage and update in on_con_changed
--TODO: Remote call for inserting/removing into table
local combat_robots = config.COMBAT_ROBOTS
local healer_capsules = config.FOOD

local Position = require('__stdlib2__/stdlib/area/position')
local max, abs, ceil, floor = math.max, math.abs, math.ceil, math.floor

--(( Helper functions ))-------------------------------------------------------

-- Loop through equipment grid and return a table of valid equipment tables indexed by equipment name
-- @param entity: the entity object
-- @return table: all equipment - name as key, arrary of named equipment as value
-- @return table: a table of valid equipment with energy in buffer - name as key, array of named equipment as value
-- @return table: shield_level = number, max_shield = number, equipment = array of shields
local function get_valid_equipment(grid)
    if grid and grid.valid then
        local all, charged, energy_shields = {}, {}, {shield_level = grid.shield, max_shield = grid.max_shield, shields = {}}
        for _, equip in pairs(grid.equipment) do
            all[equip.name] = all[equip.name] or {}
            all[equip.name][#all[equip.name] + 1] = equip
            if equip.type == 'energy-shield-equipment' and equip.shield < equip.max_shield * .75 then
                energy_shields.shields[#energy_shields.shields + 1] = equip
            end
            if equip.energy > 0 then
                charged[equip.name] = charged[equip.name] or {}
                charged[equip.name][#charged[equip.name] + 1] = equip
            end
        end
        return grid, all, charged, energy_shields
    end
end

-- Increment the y position for flying text to keep text from overlapping
-- @param position: position table - start position
-- @return function: increments position all subsequent calls
local function increment_position(position)
    local x = position.x - 1
    local y = position.y - .5
    return function()
        y = y + 0.5
        return {x = x, y = y}
    end
end

-- Is the personal roboport ready and have a radius greater than 0
-- @param entity: the entity object
-- @return bool: personal roboport construction radius > 0
local function is_personal_roboport_ready(entity, ignore_radius)
    local cell = entity.logistic_cell
    return entity.grid and cell and cell.mobile and (cell.construction_radius > 0 or ignore_radius)
end

-- Does the entity have a personal robort and construction robots. Or is in range of a roboport with construction bots.
-- @param entity: the entity object
-- @param mobile_only: bool just return available construction bots in mobile cell
-- @param stationed_only: bool if mobile only return all construction robots
-- @return number: count of available bots
local function get_bot_counts(entity, mobile_only, stationed_only)
    if not SafeEntity.is_valid(entity) then return 0 end
    
    -- v5.8.0: Direct access without pcall (entity.valid already checked)
    local network = entity.logistic_network
    
    if network then
        if mobile_only then
            local cell = entity.logistic_cell
            
            if cell and cell.mobile then
                if stationed_only then
                    return cell.stationed_construction_robot_count or 0
                else
                    return (cell.logistic_network and cell.logistic_network.available_construction_robots) or 0
                end
            end
        else
            local bots = 0
            local surface = entity.surface
            local position = entity.position
            local force = entity.force
            
            if surface and position and force then
                local networks = surface.find_logistic_networks_by_construction_area(position, force)
                for _, net in pairs(networks) do
                    bots = bots + (net.available_construction_robots or 0)
                end
            end
            return bots
        end
    else
        return 0
    end
end

local function get_health_capsules(player)
    for name, health in pairs(healer_capsules) do
        if prototypes.item[name] and player.remove_item({name = name, count = 1}) > 0 then
            return max(health, 10), prototypes.item[name].localised_name or {'nanobots.free-food-unknown'}
        end
    end
    return 10, {'nanobots.free-food'}
end

local function get_best_follower_capsule(player)
    local robot_list = {}
    for _, data in ipairs(combat_robots) do
        local count = prototypes.item[data.capsule] and player.get_item_count(data.capsule) or 0
        if count > 0 then
            robot_list[#robot_list + 1] = {capsule = data.capsule, unit = data.unit, count = count, qty = data.qty, rank = data.rank}
        end
    end
    return robot_list[1] and robot_list
end

local function get_chip_radius(player, chip_name)
    local pdata = storage.players[player.index]
    local c = player.character
    
    -- v5.8.0: Direct access without pcall
    local max_radius = 15
    if c and c.valid then
        local cell = c.logistic_cell
        if cell and cell.mobile and cell.construction_radius then
            max_radius = floor(cell.construction_radius)
        end
    end
    
    local custom_radius = pdata.ranges[chip_name] or max_radius
    return custom_radius <= max_radius and custom_radius or max_radius
end
--))

--At this point player is valid, not afk and has a character
local function get_chip_results(player, equipment, eq_name, search_type, bot_counter)
    local radius = get_chip_radius(player, eq_name)
    
    -- v5.8.0: Direct access (entity valid already checked by caller)
    local character_pos = player.character.position or {x=0, y=0}
    local surface = player.character.surface
    
    local area = Position.expand_to_area(character_pos, radius)
    local item_entities = nil
    
    if equipment and bot_counter(0) > 0 and surface then
        item_entities = surface.find_entities_filtered {area = area, type = search_type, limit = 200}
    end
    
    local num_items = item_entities and #item_entities or 0
    local num_chips = item_entities and #equipment or 0
    return equipment, item_entities, num_items, num_chips, bot_counter
end

local function mark_items(player, item_equip, items, num_items, num_item_chips, bot_counter)
    while num_items > 0 and num_item_chips > 0 and bot_counter(0) > 0 do
        local item_chip = items and item_equip[num_item_chips]
        while num_items > 0 and item_chip and item_chip.energy >= 50 do
            local item = items[num_items]
            if item and not item.to_be_deconstructed(player.force) then
                item.order_deconstruction(player.force)
                bot_counter(-1)
                item_chip.energy = item_chip.energy - 50
            end
            num_items = num_items - 1
        end
        num_item_chips = num_item_chips - 1
    end
end

--Mark items for deconstruction if player has roboport
local function process_ready_chips(player, equipment)
    if not (player and player.valid and player.character and player.character.valid) then return end
    
    -- v5.2.1: Безопасное получение construction_radius
    local rad = 0
    pcall(function()
        local cell = player.character.logistic_cell
        rad = (cell and cell.construction_radius) or 0
    end)
    
    if rad == 0 then return end
    
    -- v5.2.1: Безопасный поиск врагов
    local enemy = nil
    local character_pos = SafeEntity.get_position(player.character)
    local character_force = SafeEntity.get_property(player.character, "force")
    local surface = SafeEntity.get_surface(player.character)
    
    if surface and character_pos and character_force then
        pcall(function()
            enemy = surface.find_nearest_enemy {
                position = character_pos, 
                max_distance = rad + 10, 
                force = character_force
            }
        end)
    end
    
    if not enemy and (equipment['equipment-bot-chip-items'] or equipment['equipment-bot-chip-trees']) then
        local bots_available = get_bot_counts(player.character)
        if bots_available > 0 then
            local bot_counter = function()
                local count = bots_available
                return function(add_count)
                    count = count + add_count
                    return count
                end
            end
            bot_counter = bot_counter()
            mark_items(player, get_chip_results(player, equipment['equipment-bot-chip-items'], 'equipment-bot-chip-items', 'item-entity', bot_counter))
            mark_items(player, get_chip_results(player, equipment['equipment-bot-chip-trees'], 'equipment-bot-chip-trees', 'tree', bot_counter))
        end
    end
    
    if enemy and equipment['equipment-bot-chip-launcher'] then
        local launchers = equipment['equipment-bot-chip-launcher']
        local num_launchers = #launchers
        local capsule_data = get_best_follower_capsule(player)
        if capsule_data then
            local max_bots = player.force.maximum_following_robot_count + player.character_maximum_following_robot_count_bonus
            local existing = #player.following_robots
            local next_capsule = 1
            local capsule = capsule_data[next_capsule]
            while capsule and existing < (max_bots - capsule.qty) and capsule.count > 0 and num_launchers > 0 do
                local launcher = launchers[num_launchers]
                while capsule and existing < (max_bots - capsule.qty) and launcher and launcher.energy >= 500 do
                    if player.remove_item({name = capsule.capsule, count = 1}) == 1 then
                        -- v5.2.1: Безопасное создание entity
                        if surface and character_pos then
                            pcall(function()
                                surface.create_entity {
                                    name = capsule.unit, 
                                    position = character_pos, 
                                    force = character_force, 
                                    target = player.character
                                }
                            end)
                        end
                        launcher.energy = launcher.energy - 500
                        capsule.count = capsule.count - 1
                        existing = existing + capsule.qty
                        if capsule.count == 0 then
                            next_capsule = next_capsule + 1
                            capsule = capsule_data[next_capsule]
                        end
                    end
                end
                num_launchers = num_launchers - 1
            end
        end
    end
end

local function emergency_heal_shield(player, feeders, energy_shields)
    if not (player and player.valid and player.character and player.character.valid) then return end
    
    local num_feeders = #feeders
    -- v5.2.1: Безопасное получение позиции для flying text
    local character_pos = SafeEntity.get_position(player.character, {x=0, y=0})
    local pos = increment_position(character_pos)
    --Only run if we have less than max shield, Feeder max energy is 480
    for _, shield in pairs(energy_shields.shields) do
        while num_feeders > 0 do
            local feeder = feeders[num_feeders]
            while feeder and feeder.energy > 120 do
                if shield.shield < shield.max_shield * .75 then
                    local last_health = shield.shield
                    local heal, locale = get_health_capsules(player)
                    shield.shield = shield.shield + (heal * 1.5)
                    local health_line = {'nanobots.health_line', ceil(abs(shield.shield - last_health)), locale}
                    
                    -- v5.2.1: Безопасное создание flying text
                    local surface = SafeEntity.get_surface(player.character)
                    if surface then
                        pcall(function()
                            surface.create_entity {
                                name = 'flying-text', 
                                text = health_line, 
                                color = defines.color.green, 
                                position = pos()
                            }
                        end)
                    end
                    
                    feeder.energy = feeder.energy - 120
                else
                    break
                end
            end
            num_feeders = num_feeders - 1
        end
        if num_feeders == 0 then
            return
        end
    end
end

local function emergency_heal_player(player, feeders)
    if not (player and player.valid and player.character and player.character.valid) then return end
    
    local num_feeders = #feeders
    -- v5.2.1: Безопасное получение позиции и health
    local character_pos = SafeEntity.get_position(player.character, {x=0, y=0})
    local pos = increment_position(character_pos)
    local max_health_val = SafeEntity.get_property(player.character, "max_health", 100)
    local max_health = max_health_val * .75

    while num_feeders > 0 do
        if not SafeEntity.is_valid(player.character) then break end
        
        local feeder = feeders[num_feeders]
        while feeder and feeder.energy >= 120 do
            local current_health = SafeEntity.get_property(player.character, "health", 0)
            
            if current_health < max_health then
                local last_health = current_health
                local heal, locale = get_health_capsules(player)
                
                -- v5.2.1: Безопасная установка health
                pcall(function()
                    player.character.health = last_health + heal
                end)
                
                local new_health = SafeEntity.get_property(player.character, "health", last_health)
                local health_line = {'nanobots.health_line', ceil(abs(new_health - last_health)), locale}
                feeder.energy = feeder.energy - 120
                
                -- v5.2.1: Безопасное создание flying text
                local surface = SafeEntity.get_surface(player.character)
                if surface then
                    pcall(function()
                        surface.create_entity {
                            name = 'flying-text', 
                            text = health_line, 
                            color = defines.color.green, 
                            position = pos()
                        }
                    end)
                end
            else
                return
            end
        end
        num_feeders = num_feeders - 1
    end
end

--(( BOT CHIPS  ))-------------------------------------------------------------
function armormods.prepare_chips(player)
    if is_personal_roboport_ready(player.character) then
        local _, _, charged, energy_shields = get_valid_equipment(player.character.grid)
        if charged['equipment-bot-chip-launcher'] or charged['equipment-bot-chip-items'] or charged['equipment-bot-chip-trees'] then
            process_ready_chips(player, charged)
        end
        if charged['equipment-bot-chip-feeder'] then
            if #energy_shields.shields > 0 then
                emergency_heal_shield(player, charged['equipment-bot-chip-feeder'], energy_shields)
            elseif player.character.health < player.character.max_health * .75 then
                emergency_heal_player(player, charged['equipment-bot-chip-feeder'])
            end
        end
    end
end

return armormods
