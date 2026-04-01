-- scripts/safe_entity.lua
-- Безопасные обёртки для работы с LuaEntity
-- v5.8.0: ОПТИМИЗАЦИЯ — убраны pcall из горячих путей
-- pcall используется ТОЛЬКО для операций которые реально могут бросить ошибку
-- (destroy, revive, has_flag, get_module_inventory, get_upgrade_quality)

local SafeEntity = {}

-- Проверка валидности entity
function SafeEntity.is_valid(entity)
    return entity ~= nil and entity.valid == true
end

-- Безопасное получение свойства entity (прямой доступ, без pcall)
function SafeEntity.get_property(entity, property, default)
    if not entity or not entity.valid then
        return default
    end
    local val = entity[property]
    if val ~= nil then
        return val
    end
    return default
end

-- Безопасное получение имени
function SafeEntity.get_name(entity, default)
    if not entity or not entity.valid then return default or "unknown" end
    return entity.name or default or "unknown"
end

-- Безопасное получение позиции
function SafeEntity.get_position(entity, default)
    if not entity or not entity.valid then return default or {x=0, y=0} end
    return entity.position or default or {x=0, y=0}
end

-- Безопасное получение поверхности
function SafeEntity.get_surface(entity, default)
    if not entity or not entity.valid then return default end
    return entity.surface or default
end

-- Безопасное получение unit_number
function SafeEntity.get_unit_number(entity, default)
    if not entity or not entity.valid then return default end
    return entity.unit_number or default
end

-- Безопасное получение module inventory (pcall нужен — может бросить для некоторых типов)
function SafeEntity.get_module_inventory(entity)
    if not entity or not entity.valid then
        return nil
    end
    local success, result = pcall(function() return entity.get_module_inventory() end)
    if success and result then
        return result
    end
    return nil
end

-- Безопасное получение health ratio (прямой вызов)
function SafeEntity.get_health_ratio(entity, default)
    if not entity or not entity.valid then
        return default or 1
    end
    local result = entity.get_health_ratio()
    if result then
        return result
    end
    return default or 1
end

-- Безопасное уничтожение entity (pcall нужен)
function SafeEntity.destroy(entity, params)
    if not entity or not entity.valid then
        return false
    end
    local success = pcall(function() entity.destroy(params) end)
    return success
end

-- Безопасный revive для ghost (pcall нужен)
-- Factorio 2.0: revive() возвращает таблицу или multiple values в зависимости от версии
function SafeEntity.revive(entity, params)
    if not entity or not entity.valid then
        return false, nil, nil
    end
    -- Используем анонимную функцию для корректного вызова метода
    local success, r1, r2, r3 = pcall(function()
        return entity.revive(params)
    end)
    if not success then
        return false, nil, nil
    end
    -- r1 может быть:
    --   1) table (Factorio 2.0 dictionary: {entity=..., item_request_proxy=...})
    --   2) nil/false (revive не удался)
    --   3) collided_entities_count (старый формат: multiple returns)
    if not r1 then
        return false, nil, nil
    end
    if type(r1) == "table" then
        -- Factorio 2.0 dictionary format
        return true, r1.entity, r1.item_request_proxy
    end
    -- Старый формат: r1=collided, r2=entity, r3=proxy
    return true, r2, r3
end

-- Безопасное получение качества (Factorio 2.0) — прямой доступ
function SafeEntity.get_quality(entity, default)
    if not entity or not entity.valid then
        return default or "normal"
    end
    local quality_obj = entity.quality
    if quality_obj and quality_obj.name then
        return quality_obj.name
    end
    return default or "normal"
end

-- Безопасное получение upgrade quality (pcall нужен — может отсутствовать метод)
-- v5.8.0: get_upgrade_quality removed — use get_upgrade_target() second return value instead

-- Безопасное получение типа
function SafeEntity.get_type(entity, default)
    if not entity or not entity.valid then return default or "unknown" end
    return entity.type or default or "unknown"
end

-- Безопасная проверка флагов (pcall нужен)
function SafeEntity.has_flag(entity, flag_name)
    if not entity or not entity.valid then
        return false
    end
    local success, result = pcall(function() return entity.has_flag(flag_name) end)
    return success and result
end

-- Безопасное получение prototype (прямой доступ)
function SafeEntity.get_prototype(entity, property)
    if not entity or not entity.valid then
        return nil
    end
    local proto = entity.prototype
    if not proto then return nil end
    if property then
        return proto[property]
    end
    return proto
end

-- v5.4.4: Проверка наличия burner
function SafeEntity.has_burner(entity)
    if not entity or not entity.valid then return false end
    return entity.burner ~= nil
end

-- v5.4.4: Проверка наличия ammo inventory
function SafeEntity.has_ammo_inventory(entity)
    if not entity or not entity.valid then return false end
    local success, result = pcall(function()
        local turret_inv = entity.get_inventory(defines.inventory.turret_ammo)
        if turret_inv and turret_inv.valid then return true end
        local spider_inv = entity.get_inventory(defines.inventory.spider_ammo)
        if spider_inv and spider_inv.valid then return true end
        local car_inv = entity.get_inventory(defines.inventory.car_ammo)
        if car_inv and car_inv.valid then return true end
        return false
    end)
    return success and result
end

-- v5.4.19: Проверка наличия trunk inventory
function SafeEntity.has_trunk(entity)
    if not entity or not entity.valid then return false end
    local success, result = pcall(function()
        local trunk = entity.get_inventory(defines.inventory.car_trunk) or
                     entity.get_inventory(defines.inventory.spider_trunk) or
                     entity.get_inventory(defines.inventory.cargo_wagon)
        return trunk ~= nil and trunk.valid
    end)
    return success and result
end

-- v5.4.19: Проверка наличия equipment grid
function SafeEntity.has_equipment_grid(entity)
    if not entity or not entity.valid then return false end
    local grid = entity.grid
    return grid ~= nil and grid.valid
end

return SafeEntity
