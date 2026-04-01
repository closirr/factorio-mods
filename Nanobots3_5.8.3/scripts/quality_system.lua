-- scripts/quality_system.lua
-- v5.2: Quality bonuses and radius visualization for Nanobots3
-- v5.4.0: Added quality caching for performance optimization

local config = require('config')
local SafeEntity = require('scripts/safe_entity')
local Cache = require('scripts/cache')  -- v5.4.0: Quality cache
local CONSTANTS = require('scripts/constants')  -- v5.4.0: Centralized constants

local QualitySystem = {}

-- v5.4.0: Получение бонуса качества из констант
local function get_quality_multiplier(quality_name, bonus_type)
    local quality_data = CONSTANTS.QUALITY_BONUSES[quality_name]
    if not quality_data then
        return CONSTANTS.QUALITY_BONUSES.normal[bonus_type]
    end
    return quality_data[bonus_type] or 1.0
end

-- Безопасное получение качества оружия
function QualitySystem.get_gun_quality(player)
    if not (player and player.valid and player.character and player.character.valid) then
        return "normal", 1.0
    end
    
    local gun_inv = player.character.get_inventory(defines.inventory.character_guns)
    if not (gun_inv and gun_inv.valid) then
        return "normal", 1.0
    end
    
    -- Ищем наноэмиттер
    for i = 1, #gun_inv do
        local stack = gun_inv[i]
        if stack and stack.valid_for_read then
            -- v5.8.0: Direct access without pcall
            local name = stack.name
            
            if name and name:find("nano%-emitter") then
                local quality = "normal"
                if stack.quality and stack.quality.name then
                    quality = stack.quality.name
                end
                
                local multiplier = get_quality_multiplier(quality, "speed")
                return quality, multiplier
            end
        end
    end
    
    return "normal", 1.0
end

-- Безопасное получение качества боеприпасов
function QualitySystem.get_ammo_quality(player, nano_ammo)
    if not nano_ammo then
        return "normal", 1.0
    end
    
    local quality = "normal"
    -- v5.8.0: Direct access without pcall
    if nano_ammo.quality and nano_ammo.quality.name then
        quality = nano_ammo.quality.name
    end
    
    local multiplier = get_quality_multiplier(quality, "radius")
    return quality, multiplier
end

-- Применение бонуса качества к радиусу
function QualitySystem.apply_quality_to_radius(base_radius, ammo_quality_multiplier)
    return base_radius * ammo_quality_multiplier
end

-- Применение бонуса качества к скорости
function QualitySystem.apply_quality_to_speed(base_speed, gun_quality_multiplier)
    return math.floor(base_speed * gun_quality_multiplier)
end

-- v5.4.0: Получить цвет для типа наноботов из констант
local function get_color_for_ammo_type(ammo_name)
    -- Проверяем точное совпадение
    if CONSTANTS.AMMO_COLORS[ammo_name] then
        return CONSTANTS.AMMO_COLORS[ammo_name]
    end
    
    -- Fallback на частичное совпадение
    if ammo_name:find("termite") then
        return CONSTANTS.AMMO_COLORS["nano-ammo-termites"]
    elseif ammo_name:find("constructor") then
        return CONSTANTS.AMMO_COLORS["nano-ammo-constructors"]
    elseif ammo_name:find("deconstructor") then
        return CONSTANTS.AMMO_COLORS["nano-ammo-deconstructors"]
    elseif ammo_name:find("scrapper") then
        return CONSTANTS.AMMO_COLORS["nano-ammo-scrappers"]
    else
        return CONSTANTS.DEFAULT_AMMO_COLOR
    end
end


-- Отрисовка квадрата радиуса через 4 линии (соответствует реальной зоне действия наноботов)
-- Возвращает таблицу из 4 render IDs
function QualitySystem.draw_radius_circle(player, radius, ammo_name)
    if not (player and player.valid and player.character and player.character.valid) then
        return nil
    end
    
    local color = get_color_for_ammo_type(ammo_name or "")
    local ids = {}
    local char = player.character
    local w = CONSTANTS.CIRCLE_WIDTH
    local ttl = CONSTANTS.CIRCLE_TTL_TICKS
    local surf = player.character and player.character.surface or player.surface
    local plrs = {player}
    
    pcall(function()
        -- Factorio 2.0 syntax: target = {entity = ..., offset = ...}
        -- Top line: (-r,-r) to (r,-r)
        ids[1] = rendering.draw_line {
            color = color, width = w, surface = surf, players = plrs,
            draw_on_ground = true, only_in_alt_mode = false,
            time_to_live = ttl,
            from = {entity = char, offset = {-radius, -radius}},
            to = {entity = char, offset = {radius, -radius}}
        }
        -- Right line: (r,-r) to (r,r)
        ids[2] = rendering.draw_line {
            color = color, width = w, surface = surf, players = plrs,
            draw_on_ground = true, only_in_alt_mode = false,
            time_to_live = ttl,
            from = {entity = char, offset = {radius, -radius}},
            to = {entity = char, offset = {radius, radius}}
        }
        -- Bottom line: (r,r) to (-r,r)
        ids[3] = rendering.draw_line {
            color = color, width = w, surface = surf, players = plrs,
            draw_on_ground = true, only_in_alt_mode = false,
            time_to_live = ttl,
            from = {entity = char, offset = {radius, radius}},
            to = {entity = char, offset = {-radius, radius}}
        }
        -- Left line: (-r,r) to (-r,-r)
        ids[4] = rendering.draw_line {
            color = color, width = w, surface = surf, players = plrs,
            draw_on_ground = true, only_in_alt_mode = false,
            time_to_live = ttl,
            from = {entity = char, offset = {-radius, radius}},
            to = {entity = char, offset = {-radius, -radius}}
        }
    end)
    
    if #ids > 0 then
        return ids
    end
    return nil
end

-- Удаление визуализации (одиночный ID или таблица IDs)
function QualitySystem.destroy_circle(circle_id)
    if not circle_id then return end
    
    if type(circle_id) == "table" then
        for _, id in pairs(circle_id) do
            pcall(function()
                if rendering.is_valid{id = id} then
                    rendering.destroy(id)
                end
            end)
        end
    else
        pcall(function()
            if rendering.is_valid{id = circle_id} then
                rendering.destroy(circle_id)
            end
        end)
    end
end

-- Обновление отрисовки радиуса
function QualitySystem.update_radius_visualization(player)
    if not (player and player.valid) then return end
    
    storage.radius_rendering = storage.radius_rendering or {}
    local pdata = storage.radius_rendering[player.index]
    
    if not pdata or not pdata.enabled then
        return
    end
    
    -- Получаем текущее оружие и боеприпасы
    local gun_inv = player.character and player.character.get_inventory(defines.inventory.character_guns)
    local ammo_inv = player.character and player.character.get_inventory(defines.inventory.character_ammo)
    
    if not (gun_inv and ammo_inv) then
        QualitySystem.destroy_circle(pdata.circle_id)
        pdata.circle_id = nil
        return
    end
    
    -- Ищем наноэмиттер и его боеприпасы
    -- v5.3.4: Используем ВЫБРАННОЕ оружие, а не первое найденное
    local nano_gun = nil
    local nano_ammo = nil
    local ammo_name = ""
    local gun_quality_name = "normal"
    local selected_gun_index = nil
    
    -- Определяем индекс выбранного оружия
    if player.character and player.character.valid then
        pcall(function()
            selected_gun_index = player.character.selected_gun_index
        end)
    end
    
    -- v5.3.5: ТОЛЬКО если выбранное оружие - наноэмиттер, показываем круг
    -- В противном случае - скрываем круг
    if selected_gun_index and selected_gun_index > 0 and selected_gun_index <= #gun_inv then
        local gun = gun_inv[selected_gun_index]
        if gun and gun.valid_for_read then
            local gun_name = nil
            pcall(function() gun_name = gun.name end)
            
            if gun_name and gun_name:find("nano%-emitter") then
                -- Это наноэмиттер!
                nano_gun = gun
                
                -- Получаем качество оружия
                pcall(function()
                    if gun.quality and gun.quality.name then
                        gun_quality_name = gun.quality.name
                    end
                end)
                
                -- Ищем боеприпасы для этого слота
                nano_ammo = ammo_inv[selected_gun_index]
                if nano_ammo and nano_ammo.valid_for_read then
                    pcall(function() ammo_name = nano_ammo.name end)
                end
            end
        end
    end
    
    -- Если нет наноэмиттера - удаляем круг
    if not nano_gun then
        QualitySystem.destroy_circle(pdata.circle_id)
        pdata.circle_id = nil
        return
    end
    
    if not nano_ammo or not nano_ammo.valid_for_read then
        -- v5.3.6: Информируем пользователя что патроны закончились (только один раз)
        if pdata.circle_id and not pdata.no_ammo_warned then
            -- Круг был, но патронов больше нет - показываем предупреждение
            player.print({"nanobots.no-ammo-warning"})
            pdata.no_ammo_warned = true
        end
        QualitySystem.destroy_circle(pdata.circle_id)
        pdata.circle_id = nil
        return
    end
    
    -- v5.3.6: Если патроны есть, сбрасываем флаг предупреждения
    pdata.no_ammo_warned = false
    
    -- v5.4.0: PERFORMANCE - Используем кэш для качества (обновляется раз в секунду)
    local current_tick = game.tick
    local cached_quality = Cache.get_quality_cache(player.index, current_tick)
    
    local ammo_quality_bonus, gun_quality_bonus
    
    if cached_quality and cached_quality.ammo_name == ammo_name then
        -- Используем закэшированные значения
        ammo_quality_bonus = cached_quality.ammo_bonus
        gun_quality_bonus = cached_quality.gun_bonus
        gun_quality_name = cached_quality.gun_quality_name
    else
        -- Вычисляем качество и кэшируем
        local ammo_quality_name_calc
        ammo_quality_name_calc, ammo_quality_bonus = QualitySystem.get_ammo_quality(player, nano_ammo)
        gun_quality_name, gun_quality_bonus = QualitySystem.get_gun_quality(player)
        
        -- Сохраняем в кэш
        Cache.set_quality_cache(player.index, current_tick, 
            gun_quality_name, gun_quality_bonus,
            ammo_quality_name_calc, ammo_quality_bonus,
            ammo_name)
    end
    
    -- Получаем базовый радиус из настроек
    local modifier = 0
    pcall(function()
        if nano_ammo.prototype and nano_ammo.prototype.ammo_category then
            modifier = player.force.get_ammo_damage_modifier(nano_ammo.prototype.ammo_category.name) or 0
        end
    end)
    
    local base_radius = config.BOT_RADIUS[modifier] or 7
    local effective_radius = QualitySystem.apply_quality_to_radius(base_radius, ammo_quality_bonus)
    
    -- v5.3.7: Debug - показываем информацию о бонусах качества (только при первом включении)
    if not pdata.debug_shown then
        player.print({"nanobots.quality-bonuses", 
            string.format("%.0f", (gun_quality_bonus - 1) * 100),
            string.format("%.0f", (ammo_quality_bonus - 1) * 100)
        })
        pdata.debug_shown = true
    end
    
    -- v5.4.0: Проверяем нужно ли пересоздать круг
    local need_recreate = false
    local current_tick = game.tick
    
    -- Пересоздаём если параметры изменились
    if pdata.last_radius ~= effective_radius or pdata.last_ammo ~= ammo_name or pdata.last_gun_quality ~= gun_quality_name then
        need_recreate = true
    end
    
    -- Пересоздаём до истечения TTL чтобы круг не исчез
    if not pdata.last_update_tick or (current_tick - pdata.last_update_tick) >= CONSTANTS.CIRCLE_REFRESH_TICKS then
        need_recreate = true
    end
    
    -- Пересоздаём если нет круга
    if not pdata.circle_id then
        need_recreate = true
    end
    
    -- Пересоздаём если круг стал invalid
    if pdata.circle_id then
        local is_valid = false
        pcall(function()
            if type(pdata.circle_id) == "table" then
                -- Check first line of the 4 lines
                is_valid = pdata.circle_id[1] and rendering.is_valid{id = pdata.circle_id[1]}
            else
                is_valid = rendering.is_valid{id = pdata.circle_id}
            end
        end)
        if not is_valid then
            need_recreate = true
        end
    end
    
    if not need_recreate then
        return -- Ничего не изменилось, круг ещё живой
    end
    
    -- v5.3.6: Показываем сообщение если круг появляется после отсутствия патронов
    local was_no_circle = (pdata.circle_id == nil)
    local radius_changed = (pdata.last_radius ~= effective_radius)
    
    -- Удаляем старый круг если есть
    if pdata.circle_id then
        QualitySystem.destroy_circle(pdata.circle_id)
    end
    
    -- Рисуем новый
    pdata.circle_id = QualitySystem.draw_radius_circle(player, effective_radius, ammo_name)
    pdata.last_radius = effective_radius
    pdata.last_ammo = ammo_name
    pdata.last_gun_quality = gun_quality_name
    pdata.last_update_tick = current_tick
    
    -- v5.3.6: Если круг только что появился (патроны загружены)
    if was_no_circle and pdata.circle_id then
        player.print({"nanobots.circle-restored", string.format("%.1f", effective_radius)})
    -- v5.3.7: Если радиус изменился при переключении оружия
    elseif radius_changed and pdata.circle_id then
        player.print({"nanobots.radius-updated", string.format("%.1f", effective_radius), gun_quality_name})
    end
end

-- Переключение визуализации
function QualitySystem.toggle_radius_visualization(player)
    if not (player and player.valid) then return false end
    
    storage.radius_rendering = storage.radius_rendering or {}
    local pdata = storage.radius_rendering[player.index]
    
    if not pdata then
        pdata = {
            enabled = true,
            circle_id = nil,
            last_radius = 0,
            last_ammo = "",
            last_gun_quality = "normal",
            debug_shown = false,
            last_update_tick = 0,
            no_ammo_warned = false  -- v5.3.6: Флаг что показали предупреждение о патронах
        }
        storage.radius_rendering[player.index] = pdata
        player.print({"nanobots.radius-enabled"})
    else
        pdata.enabled = not pdata.enabled
        pdata.debug_shown = false
        
        if not pdata.enabled then
            -- Выключаем - просто удаляем круг
            if pdata.circle_id then
                QualitySystem.destroy_circle(pdata.circle_id)
                pdata.circle_id = nil
                player.print({"nanobots.radius-disabled-fade"})
            end
            
            -- Очистить данные
            pdata.last_radius = 0
            pdata.last_ammo = ""
            pdata.last_gun_quality = "normal"
        else
            player.print({"nanobots.radius-enabled"})
        end
    end
    
    if pdata.enabled then
        QualitySystem.update_radius_visualization(player)
    end
    
    return pdata.enabled
end

-- Получить статус визуализации
function QualitySystem.is_visualization_enabled(player)
    if not (player and player.valid) then return false end
    
    storage.radius_rendering = storage.radius_rendering or {}
    local pdata = storage.radius_rendering[player.index]
    
    return pdata and pdata.enabled or false
end

-- Очистка рендера при выходе игрока (сохраняем enabled для перезахода)
function QualitySystem.on_player_left(player_index)
    storage.radius_rendering = storage.radius_rendering or {}
    local pdata = storage.radius_rendering[player_index]
    
    if pdata then
        -- Уничтожаем рендер-объект (он не переживёт перезаход)
        if pdata.circle_id then
            QualitySystem.destroy_circle(pdata.circle_id)
            pdata.circle_id = nil
        end
        -- НЕ удаляем pdata! enabled сохранится в storage
        pdata.last_radius = 0
        pdata.last_ammo = ""
        pdata.last_gun_quality = "normal"
    end
    
    -- v5.4.0: Очистить кэш качества
    Cache.clear_quality_cache(player_index)
end

-- Полное удаление данных игрока (только при реальном удалении из игры)
function QualitySystem.on_player_removed(player_index)
    storage.radius_rendering = storage.radius_rendering or {}
    local pdata = storage.radius_rendering[player_index]
    
    if pdata and pdata.circle_id then
        QualitySystem.destroy_circle(pdata.circle_id)
    end
    
    storage.radius_rendering[player_index] = nil
    
    -- v5.4.0: Очистить кэш качества
    Cache.clear_quality_cache(player_index)
end

-- Восстановление визуализации при перезаходе игрока
function QualitySystem.on_player_joined(player)
    if not (player and player.valid) then return end
    
    storage.radius_rendering = storage.radius_rendering or {}
    local pdata = storage.radius_rendering[player.index]
    
    -- Синхронизируем shortcut с сохранённым состоянием
    local is_enabled = pdata and pdata.enabled or false
    player.set_shortcut_toggled("nanobots-toggle-radius", is_enabled)
    
    -- Восстанавливаем рендер если было включено
    if is_enabled then
        QualitySystem.update_radius_visualization(player)
    end
end

-- v5.4.0: Инициализация системы качества
function QualitySystem.init()
    Cache.init_quality_cache()
end

-- v5.4.0: Периодическая очистка старых кэшей
function QualitySystem.cleanup_old_caches(current_tick)
    Cache.cleanup_old_caches(current_tick)
end

return QualitySystem
