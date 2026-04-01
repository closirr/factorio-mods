-- scripts/module_requests.lua
-- Безопасная система вставки модулей через item-request-proxy
-- Полностью переписана для предотвращения крашей

local SafeEntity = require('scripts/safe_entity')

local ModuleRequests = {}

-- Логирование (получаем DEBUG_NANO из глобального контекста)
local function log_debug(msg)
    -- DEBUG_NANO должен быть глобальным
    if _G.DEBUG_NANO and _G.DEBUG_NANO >= 2 and game then
        game.print("[NANO:MODULE] " .. msg)
    end
end

-- v5.4.22: Проверка наличия необходимых предметов
local function has_all_modules(player, entity, required_modules, request_type)
    if not (player and player.valid) then return false end
    
    local pinv = player.get_main_inventory()
    if not (pinv and pinv.valid) then return false end
    
    -- v5.4.17: Используем переданный request_type вместо определения по entity
    local is_fuel = (request_type == "fuel")
    local is_ammo = (request_type == "ammo")
    local is_trunk = (request_type == "trunk")
    local is_equipment = (request_type == "equipment")
    
    -- v5.4.22: Для fuel/ammo/trunk/equipment достаточно ЛЮБОГО предмета
    -- Для modules нужны ВСЕ предметы
    if is_fuel or is_ammo or is_trunk or is_equipment then
        -- Проверяем что ХОТЯ БЫ ОДИН предмет доступен
        local any_available = false
        
        for module_key, needed in pairs(required_modules) do
            local name, quality = module_key:match("([^:]+):(.+)")
            if not name then
                name = module_key
                quality = "normal"
            end
            
            local available = player.cheat_mode and 1 or pinv.get_item_count({name = name, quality = quality})
            
            if available > 0 then
                any_available = true
                log_debug("Доступен предмет: " .. name .. " x" .. available)
                break  -- Достаточно одного!
            else
                log_debug("Недоступен: " .. name .. " (q:" .. quality .. ")")
            end
        end
        
        if not any_available then
            if is_fuel then
                log_debug("Нет НИ ОДНОГО топлива")
            elseif is_ammo then
                log_debug("Нет НИ ОДНОГО боеприпаса")
            elseif is_trunk then
                log_debug("Нет НИ ОДНОГО предмета для trunk")
            else
                log_debug("Нет НИ ОДНОГО оборудования")
            end
            return false
        end
        
        return true
    end
    
    -- Для модулей - строгая проверка (нужно ВСЁ)
    local current_modules = {}
    local module_inv = SafeEntity.get_module_inventory(entity)
    if not module_inv then return false end
    
    for i = 1, #module_inv do
        local slot = module_inv[i]
        if slot and slot.valid_for_read then
            local name = slot.name
            current_modules[name] = (current_modules[name] or 0) + 1
        end
    end
    
    for module_key, needed in pairs(required_modules) do
        local name, quality = module_key:match("([^:]+):(.+)")
        if not name then
            name = module_key
            quality = "normal"
        end
        
        local have = current_modules[name] or 0
        local need = needed - have
        
        if need > 0 then
            local available = player.cheat_mode and need or pinv.get_item_count({name = name, quality = quality})
            
            if available < need then
                log_debug("Не хватает модулей: " .. name .. " (q:" .. quality .. ") нужно=" .. need .. " есть=" .. available)
                return false
            end
        end
    end
    
    return true
end

-- Подсчёт свободных слотов
local function count_free_slots(entity)
    local module_inv = SafeEntity.get_module_inventory(entity)
    if not module_inv then return 0 end
    
    local free = 0
    for i = 1, #module_inv do
        if not SafeEntity.is_valid(entity) then return 0 end
        local slot = module_inv[i]
        if slot and not slot.valid_for_read then
            free = free + 1
        end
    end
    
    return free
end

-- Вставка одного модуля в первый свободный слот
local function insert_single_module(entity, module_name, quality)
    local module_inv = SafeEntity.get_module_inventory(entity)
    if not module_inv then return false end
    
    for i = 1, #module_inv do
        if not SafeEntity.is_valid(entity) then return false end
        
        -- Переполучаем инвентарь для надёжности
        local current_inv = SafeEntity.get_module_inventory(entity)
        if not current_inv then return false end
        
        local slot = current_inv[i]
        if slot and not slot.valid_for_read then
            local success = pcall(function()
                slot.set_stack({name = module_name, count = 1, quality = quality})
            end)
            return success
        end
    end
    
    return false
end

-- v5.4.9: Вставка топлива (FIXED: обновляет proxy запрос на остаток)
local function insert_fuel(player, target_entity, normalized, proxy)
    if not SafeEntity.is_valid(target_entity) then 
        log_debug("insert_fuel: target_entity невалиден")
        return false 
    end
    
    local pinv = player.get_main_inventory()
    if not (pinv and pinv.valid) then 
        log_debug("insert_fuel: player inventory невалиден")
        return false 
    end
    
    log_debug("insert_fuel: начало вставки")
    local any_inserted = false
    
    for module_key, needed in pairs(normalized) do
        local name, quality = module_key:match("([^:]+):(.+)")
        if not name then
            name = module_key
            quality = "normal"
        end
        
        log_debug("insert_fuel: обработка " .. name .. " качество=" .. quality .. " нужно=" .. needed)
        
        -- v5.4.7: Проверяем сколько РЕАЛЬНО доступно
        local available = player.cheat_mode and needed or pinv.get_item_count({name = name, quality = quality})
        log_debug("insert_fuel: доступно=" .. available)
        
        if available <= 0 then
            log_debug("Топливо отсутствует: " .. name)
            goto continue_fuel
        end
        
        -- v5.4.15: Проверяем сколько УЖЕ в burner, чтобы не вставить лишнее
        local already_have = 0
        pcall(function()
            local burner = target_entity.burner
            if burner and burner.inventory then
                already_have = burner.inventory.get_item_count({name = name, quality = quality})
            end
        end)
        
        log_debug("insert_fuel: уже в burner=" .. already_have .. " нужно=" .. needed)
        
        -- Реально нужно вставить = запрошено - уже есть
        local actually_needed = math.max(0, needed - already_have)
        
        if actually_needed == 0 then
            log_debug("insert_fuel: уже достаточно топлива")
            goto continue_fuel
        end
        
        -- v5.4.7: Вставляем СТОЛЬКО СКОЛЬКО ЕСТЬ, но не больше чем РЕАЛЬНО нужно
        local to_insert = math.min(available, actually_needed)
        log_debug("insert_fuel: будем вставлять=" .. to_insert)
        
        local actual_inserted = 0
        
        -- Вставляем топливо через burner.inventory
        local success, error_msg = pcall(function()
            local burner = target_entity.burner
            log_debug("insert_fuel: получен burner=" .. tostring(burner ~= nil))
            
            if burner and burner.inventory then
                log_debug("insert_fuel: burner.inventory существует")
                local inserted = burner.inventory.insert({name = name, quality = quality, count = to_insert})
                log_debug("insert_fuel: вставлено=" .. inserted .. " из " .. to_insert)
                actual_inserted = inserted
                
                if inserted > 0 then
                    -- Удаляем из инвентаря игрока ТОЛЬКО то что реально вставили
                    if not player.cheat_mode then
                        local removed = pinv.remove({name = name, quality = quality, count = inserted})
                        log_debug("insert_fuel: удалено из инвентаря=" .. removed)
                    end
                    log_debug("Топливо вставлено: " .. name .. " x" .. inserted)
                    any_inserted = true
                else
                    log_debug("insert_fuel: НЕ УДАЛОСЬ вставить (inserted=0)")
                end
            else
                log_debug("insert_fuel: НЕТ burner.inventory!")
            end
        end)
        
        if not success then
            log_debug("Ошибка при вставке топлива: " .. name .. " error=" .. tostring(error_msg))
        end
        
        ::continue_fuel::
    end
    
    log_debug("insert_fuel: завершено, any_inserted=" .. tostring(any_inserted))
    
    -- v5.4.15: ПРОСТОЕ РЕШЕНИЕ - уничтожаем proxy только когда ВСЁ доставлено
    -- proxy.item_requests is READ-ONLY, мы не можем его обновить
    -- Поэтому: proxy показывает исходный запрос до полной доставки
    if any_inserted and proxy and SafeEntity.is_valid(proxy) then
        local success, error_msg = pcall(function()
            -- Получаем текущие запросы
            local current_requests = proxy.item_requests
            if not current_requests then 
                log_debug("insert_fuel: нет current_requests")
                return 
            end
            
            -- Проверяем - ВСЁ ли доставлено?
            local all_delivered = true
            
            for item_name, request_data in pairs(current_requests) do
                local name = request_data.name or item_name
                local requested_count = request_data.count or 0
                local quality = request_data.quality or "normal"
                
                -- Проверяем сколько реально в burner
                local delivered = 0
                pcall(function()
                    local burner = target_entity.burner
                    if burner and burner.inventory then
                        delivered = burner.inventory.get_item_count({name = name, quality = quality})
                    end
                end)
                
                log_debug("insert_fuel: " .. name .. " запрошено=" .. requested_count .. " доставлено=" .. delivered)
                
                -- Если хотя бы один предмет не полностью доставлен
                if delivered < requested_count then
                    all_delivered = false
                    log_debug("insert_fuel: НЕ полностью доставлено: " .. name)
                    break
                end
            end
            
            -- Уничтожаем proxy ТОЛЬКО если ВСЁ доставлено
            if all_delivered then
                proxy.destroy()
                log_debug("insert_fuel: proxy уничтожен (всё доставлено полностью)")
            else
                log_debug("insert_fuel: proxy оставлен (частичная доставка, иконка покажет исходный запрос)")
            end
        end)
        
        if not success then
            log_debug("insert_fuel: ОШИБКА при проверке proxy: " .. tostring(error_msg))
        end
    end
    
    return any_inserted
end

-- v5.4.9: Вставка боеприпасов (FIXED: обновляет proxy запрос на остаток)
local function insert_ammo(player, target_entity, normalized, proxy)
    if not SafeEntity.is_valid(target_entity) then return false end
    
    local pinv = player.get_main_inventory()
    if not (pinv and pinv.valid) then return false end
    
    -- v5.4.26: Проверяем car_ammo ПЕРВЫМ (для tank/car), потом turret/spider
    local ammo_inv = nil
    local ammo_type = "unknown"
    pcall(function()
        -- v5.4.26: Car_ammo ПЕРВЫМ (tank имеет И turret_ammo И car_ammo!)
        ammo_inv = target_entity.get_inventory(defines.inventory.car_ammo)
        if ammo_inv and ammo_inv.valid then
            ammo_type = "car_ammo"
            return
        end
        
        -- Для турелей
        ammo_inv = target_entity.get_inventory(defines.inventory.turret_ammo)
        if ammo_inv and ammo_inv.valid then
            ammo_type = "turret_ammo"
            return
        end
        
        -- Для spidertron
        ammo_inv = target_entity.get_inventory(defines.inventory.spider_ammo)
        if ammo_inv and ammo_inv.valid then
            ammo_type = "spider_ammo"
            return
        end
    end)
    
    if not (ammo_inv and ammo_inv.valid) then
        log_debug("Нет ammo inventory (ни turret_ammo, ни spider_ammo, ни car_ammo)")
        return false
    end
    
    log_debug("insert_ammo: используем " .. ammo_type)
    
    local any_inserted = false
    
    for module_key, needed in pairs(normalized) do
        local name, quality = module_key:match("([^:]+):(.+)")
        if not name then
            name = module_key
            quality = "normal"
        end
        
        -- v5.4.7: Проверяем сколько РЕАЛЬНО доступно
        local available = player.cheat_mode and needed or pinv.get_item_count({name = name, quality = quality})
        
        if available <= 0 then
            log_debug("Боеприпасы отсутствуют: " .. name)
            goto continue_ammo
        end
        
        -- v5.4.15: Проверяем сколько УЖЕ в ammo_inv
        local already_have = ammo_inv.get_item_count({name = name, quality = quality})
        log_debug("insert_ammo: уже в ammo_inv=" .. already_have .. " нужно=" .. needed)
        
        -- Реально нужно вставить = запрошено - уже есть
        local actually_needed = math.max(0, needed - already_have)
        
        if actually_needed == 0 then
            log_debug("insert_ammo: уже достаточно боеприпасов")
            goto continue_ammo
        end
        
        -- v5.4.7: Вставляем СТОЛЬКО СКОЛЬКО ЕСТЬ, но не больше чем РЕАЛЬНО нужно
        local to_insert = math.min(available, actually_needed)
        
        -- Вставляем боеприпасы
        local inserted = ammo_inv.insert({name = name, quality = quality, count = to_insert})
        if inserted > 0 then
            -- Удаляем из инвентаря игрока ТОЛЬКО то что реально вставили
            if not player.cheat_mode then
                pinv.remove({name = name, quality = quality, count = inserted})
            end
            log_debug("Боеприпасы вставлены: " .. name .. " x" .. inserted)
            any_inserted = true
        end
        
        ::continue_ammo::
    end
    
    -- v5.4.15: ПРОСТОЕ РЕШЕНИЕ - уничтожаем proxy только когда ВСЁ доставлено
    if any_inserted and proxy and SafeEntity.is_valid(proxy) then
        pcall(function()
            local current_requests = proxy.item_requests
            if not current_requests then return end
            
            -- v5.4.23: Получаем правильный ammo inventory (turret, spider, или car)
            local ammo_inv = target_entity.get_inventory(defines.inventory.turret_ammo)
            if not (ammo_inv and ammo_inv.valid) then
                ammo_inv = target_entity.get_inventory(defines.inventory.spider_ammo)
            end
            if not (ammo_inv and ammo_inv.valid) then
                ammo_inv = target_entity.get_inventory(defines.inventory.car_ammo)
            end
            
            if not (ammo_inv and ammo_inv.valid) then return end
            
            -- Проверяем - ВСЁ ли доставлено?
            local all_delivered = true
            
            for item_name, request_data in pairs(current_requests) do
                local name = request_data.name or item_name
                local requested_count = request_data.count or 0
                local quality = request_data.quality or "normal"
                
                local delivered = ammo_inv.get_item_count({name = name, quality = quality})
                
                log_debug("insert_ammo: " .. name .. " запрошено=" .. requested_count .. " доставлено=" .. delivered)
                
                if delivered < requested_count then
                    all_delivered = false
                    break
                end
            end
            
            -- Уничтожаем proxy ТОЛЬКО если ВСЁ доставлено
            if all_delivered then
                proxy.destroy()
                log_debug("insert_ammo: proxy уничтожен (всё доставлено полностью)")
            else
                log_debug("insert_ammo: proxy оставлен (частичная доставка)")
            end
        end)
    end
    
    return any_inserted
end

-- v5.4.19: Вставка предметов в trunk (car_trunk, spider_trunk, cargo_wagon)
local function insert_trunk(player, target_entity, normalized, proxy)
    if not SafeEntity.is_valid(target_entity) then return false end
    
    local pinv = player.get_main_inventory()
    if not (pinv and pinv.valid) then return false end
    
    -- Пробуем разные типы trunk
    local trunk_inv = nil
    pcall(function()
        trunk_inv = target_entity.get_inventory(defines.inventory.car_trunk) or
                   target_entity.get_inventory(defines.inventory.spider_trunk) or
                   target_entity.get_inventory(defines.inventory.cargo_wagon)
    end)
    
    if not (trunk_inv and trunk_inv.valid) then
        log_debug("Нет trunk inventory")
        return false
    end
    
    log_debug("insert_trunk: используем trunk_inv")
    local any_inserted = false
    
    for module_key, needed in pairs(normalized) do
        local name, quality = module_key:match("([^:]+):(.+)")
        if not name then
            name = module_key
            quality = "normal"
        end
        
        local available = player.cheat_mode and needed or pinv.get_item_count({name = name, quality = quality})
        
        if available <= 0 then
            log_debug("Предмет отсутствует: " .. name)
            goto continue_trunk
        end
        
        -- Проверяем сколько уже в trunk
        local already_have = trunk_inv.get_item_count({name = name, quality = quality})
        local actually_needed = math.max(0, needed - already_have)
        
        if actually_needed == 0 then
            log_debug("insert_trunk: уже достаточно " .. name)
            goto continue_trunk
        end
        
        local to_insert = math.min(available, actually_needed)
        local inserted = trunk_inv.insert({name = name, quality = quality, count = to_insert})
        
        if inserted > 0 then
            if not player.cheat_mode then
                pinv.remove({name = name, quality = quality, count = inserted})
            end
            log_debug("В trunk вставлено: " .. name .. " x" .. inserted)
            any_inserted = true
        end
        
        ::continue_trunk::
    end
    
    -- Проверяем завершённость доставки
    if any_inserted and proxy and SafeEntity.is_valid(proxy) then
        pcall(function()
            local current_requests = proxy.item_requests
            if not current_requests then return end
            
            local all_delivered = true
            for item_name, request_data in pairs(current_requests) do
                local name = request_data.name or item_name
                local requested_count = request_data.count or 0
                local quality = request_data.quality or "normal"
                local delivered = trunk_inv.get_item_count({name = name, quality = quality})
                
                if delivered < requested_count then
                    all_delivered = false
                    break
                end
            end
            
            if all_delivered then
                proxy.destroy()
                log_debug("insert_trunk: proxy уничтожен (всё доставлено)")
            end
        end)
    end
    
    return any_inserted
end

-- v5.4.19: Вставка оборудования в equipment grid
local function insert_equipment(player, target_entity, normalized, proxy)
    if not SafeEntity.is_valid(target_entity) then return false end
    
    local pinv = player.get_main_inventory()
    if not (pinv and pinv.valid) then return false end
    
    local grid = nil
    pcall(function()
        grid = target_entity.grid
    end)
    
    if not (grid and grid.valid) then
        log_debug("Нет equipment grid")
        return false
    end
    
    log_debug("insert_equipment: используем equipment grid")
    local any_inserted = false
    
    for module_key, needed in pairs(normalized) do
        local name, quality = module_key:match("([^:]+):(.+)")
        if not name then
            name = module_key
            quality = "normal"
        end
        
        local available = player.cheat_mode and needed or pinv.get_item_count({name = name, quality = quality})
        
        if available <= 0 then
            log_debug("Оборудование отсутствует: " .. name)
            goto continue_equip
        end
        
        -- Проверяем сколько уже в grid
        local already_have = 0
        for _, equipment in pairs(grid.equipment) do
            if equipment.name == name then
                already_have = already_have + 1
            end
        end
        
        local actually_needed = math.max(0, needed - already_have)
        
        if actually_needed == 0 then
            log_debug("insert_equipment: уже достаточно " .. name)
            goto continue_equip
        end
        
        local to_insert = math.min(available, actually_needed)
        
        -- Вставляем оборудование
        for i = 1, to_insert do
            local pos = grid.put({name = name, quality = quality})
            if pos then
                if not player.cheat_mode then
                    pinv.remove({name = name, quality = quality, count = 1})
                end
                log_debug("Оборудование вставлено: " .. name)
                any_inserted = true
            else
                log_debug("Не удалось вставить оборудование: " .. name .. " (нет места)")
                break
            end
        end
        
        ::continue_equip::
    end
    
    -- Проверяем завершённость
    if any_inserted and proxy and SafeEntity.is_valid(proxy) then
        pcall(function()
            local current_requests = proxy.item_requests
            if not current_requests then return end
            
            local all_delivered = true
            for item_name, request_data in pairs(current_requests) do
                local name = request_data.name or item_name
                local requested_count = request_data.count or 0
                
                local delivered = 0
                for _, equipment in pairs(grid.equipment) do
                    if equipment.name == name then
                        delivered = delivered + 1
                    end
                end
                
                if delivered < requested_count then
                    all_delivered = false
                    break
                end
            end
            
            if all_delivered then
                proxy.destroy()
                log_debug("insert_equipment: proxy уничтожен (всё доставлено)")
            end
        end)
    end
    
    return any_inserted
end

-- Основная функция обработки запросов модулей (internal implementation)
local function satisfy_requests_internal(proxy, target_entity, player)
    -- Валидация входных параметров
    if not SafeEntity.is_valid(proxy) then 
        log_debug("proxy невалиден")
        return false 
    end
    if not SafeEntity.is_valid(target_entity) then 
        log_debug("target_entity невалиден")
        return false 
    end
    if not (player and player.valid and player.character and player.character.valid) then 
        log_debug("player невалиден")
        return false 
    end
    
    -- v5.4.21: РАЗДЕЛЯЕМ запросы по типам (tank может запросить И fuel И ammo!)
    local has_burner = SafeEntity.has_burner(target_entity)
    local has_ammo = SafeEntity.has_ammo_inventory(target_entity)
    local has_trunk = SafeEntity.has_trunk(target_entity)
    local has_equipment = SafeEntity.has_equipment_grid(target_entity)
    
    -- Получаем запросы
    local item_requests = nil
    local success = pcall(function()
        item_requests = proxy.item_requests
    end)
    
    if not success or not item_requests then
        log_debug("Не удалось получить item_requests")
        return false
    end
    
    -- v5.4.21: Группируем запросы по типам
    local requests_by_type = {
        fuel = {},
        ammo = {},
        trunk = {},
        equipment = {},
        modules = {}
    }
    
    -- v5.4.24: ВАЖНОЕ ОГРАНИЧЕНИЕ API
    -- proxy.item_requests НЕ содержит информации о целевом инвентаре!
    -- Мы не можем знать: пользователь хочет solid-fuel в burner или trunk?
    -- 
    -- Vanilla Factorio решает это создавая ОТДЕЛЬНЫЕ proxy для каждого инвентаря,
    -- но мы получаем их все вместе и не можем различить!
    --
    -- Эвристика: Приоритет по типу предмета
    -- Топливо → burner (если есть)
    -- Боеприпасы → ammo_inventory (если есть)
    -- Оборудование → grid (если есть)
    -- Модули → module_inventory
    -- Остальное → trunk (если есть)
    
    -- Классифицируем каждый предмет
    for item_name, request_data in pairs(item_requests) do
        local name = request_data.name or item_name
        local count = tonumber(request_data.count or request_data.amount or request_data or 0) or 0
        local quality = request_data.quality or "normal"
        
        if count > 0 then
            local success_proto, item_proto = pcall(function()
                return prototypes.item[name]
            end)
            
            if success_proto and item_proto then
                local item_type = "modules"  -- default
                
                if item_proto.fuel_category and has_burner then
                    item_type = "fuel"
                elseif item_proto.type == "ammo" and has_ammo then
                    item_type = "ammo"
                elseif item_proto.place_as_equipment_result and has_equipment then
                    item_type = "equipment"
                elseif item_proto.type == "module" then
                    item_type = "modules"
                elseif has_trunk then
                    item_type = "trunk"
                end
                
                local key = name .. ":" .. quality
                requests_by_type[item_type][key] = count
                log_debug("Классификация: " .. name .. " → " .. item_type)
            end
        end
    end
    
    local entity_name = SafeEntity.get_name(target_entity, "unknown")
    
    -- v5.4.25: НЕ передаём proxy в функции вставки - проверим в конце
    local any_success = false
    
    -- 1. Топливо
    if next(requests_by_type.fuel) then
        local count = 0
        for _ in pairs(requests_by_type.fuel) do count = count + 1 end
        log_debug("Обработка топлива для " .. entity_name .. ": " .. count .. " типов")
        
        if has_all_modules(player, target_entity, requests_by_type.fuel, "fuel") then
            local result = insert_fuel(player, target_entity, requests_by_type.fuel, nil)
            log_debug("insert_fuel вернул: " .. tostring(result))
            if result then any_success = true end
        else
            log_debug("Топливо недоступно")
        end
    end
    
    -- 2. Боеприпасы
    if next(requests_by_type.ammo) then
        local count = 0
        for _ in pairs(requests_by_type.ammo) do count = count + 1 end
        log_debug("Обработка боеприпасов для " .. entity_name .. ": " .. count .. " типов")
        
        if has_all_modules(player, target_entity, requests_by_type.ammo, "ammo") then
            local result = insert_ammo(player, target_entity, requests_by_type.ammo, nil)
            log_debug("insert_ammo вернул: " .. tostring(result))
            if result then any_success = true end
        else
            log_debug("Боеприпасы недоступны")
        end
    end
    
    -- 3. Trunk
    if next(requests_by_type.trunk) then
        local count = 0
        for _ in pairs(requests_by_type.trunk) do count = count + 1 end
        log_debug("Обработка trunk для " .. entity_name .. ": " .. count .. " типов")
        
        if has_all_modules(player, target_entity, requests_by_type.trunk, "trunk") then
            local result = insert_trunk(player, target_entity, requests_by_type.trunk, nil)
            log_debug("insert_trunk вернул: " .. tostring(result))
            if result then any_success = true end
        else
            log_debug("Предметы для trunk недоступны")
        end
    end
    
    -- 4. Equipment
    if next(requests_by_type.equipment) then
        local count = 0
        for _ in pairs(requests_by_type.equipment) do count = count + 1 end
        log_debug("Обработка equipment для " .. entity_name .. ": " .. count .. " типов")
        
        if has_all_modules(player, target_entity, requests_by_type.equipment, "equipment") then
            local result = insert_equipment(player, target_entity, requests_by_type.equipment, nil)
            log_debug("insert_equipment вернул: " .. tostring(result))
            if result then any_success = true end
        else
            log_debug("Оборудование недоступно")
        end
    end
    
    -- 5. Modules
    if next(requests_by_type.modules) then
        local count = 0
        for _ in pairs(requests_by_type.modules) do count = count + 1 end
        log_debug("Обработка modules для " .. entity_name .. ": " .. count .. " типов")
        
        if has_all_modules(player, target_entity, requests_by_type.modules, "modules") then
            -- Проверяем свободные слоты
            local free_slots = count_free_slots(target_entity)
            if free_slots == 0 then
                log_debug("Нет свободных слотов для модулей")
            else
                -- Вставляем модули
                local pinv = player.get_main_inventory()
                if pinv and pinv.valid then
                    local any_inserted = false
                    local any_failed = false
                    
                    for module_key, needed in pairs(requests_by_type.modules) do
                        if not SafeEntity.is_valid(target_entity) then
                            log_debug("target_entity стал невалидным во время вставки")
                            break
                        end
                        
                        local name, quality = module_key:match("([^:]+):(.+)")
                        if not name then
                            name = module_key
                            quality = "normal"
                        end
                        
                        local inserted_count = 0
                        local available = player.cheat_mode and needed or pinv.get_item_count({name = name, quality = quality})
                        local to_insert = math.min(needed, available, free_slots)
                        
                        for i = 1, to_insert do
                            if not SafeEntity.is_valid(target_entity) then break end
                            
                            if insert_single_module(target_entity, name, quality) then
                                inserted_count = inserted_count + 1
                                free_slots = free_slots - 1
                                any_inserted = true
                            else
                                any_failed = true
                                break
                            end
                        end
                        
                        -- Удаляем использованные модули из инвентаря
                        if inserted_count > 0 and not player.cheat_mode then
                            pcall(function()
                                pinv.remove({name = name, quality = quality, count = inserted_count})
                            end)
                        end
                        
                        log_debug("Вставлено " .. inserted_count .. "/" .. needed .. " модулей " .. name)
                    end
                    
                    if any_inserted then any_success = true end
                    
                    -- Уничтожаем proxy если все модули вставлены
                    if any_inserted and not any_failed then
                        pcall(function()
                            if SafeEntity.is_valid(proxy) then
                                proxy.destroy()
                            end
                        end)
                    end
                end
            end
        else
            log_debug("Не все модули доступны")
        end
    end
    
    -- v5.4.25: ФИНАЛЬНАЯ проверка proxy - удаляем только если ВСЁ доставлено
    if any_success and SafeEntity.is_valid(proxy) then
        pcall(function()
            local all_delivered = true
            local item_requests = proxy.item_requests
            
            if not item_requests then
                return
            end
            
            -- Проверяем каждый запрос
            for item_name, request_data in pairs(item_requests) do
                local name = request_data.name or item_name
                local requested = request_data.count or 0
                local quality = request_data.quality or "normal"
                
                -- Проверяем во ВСЕХ возможных инвентарях
                local total_delivered = 0
                
                -- Burner
                pcall(function()
                    local burner = target_entity.burner
                    if burner and burner.inventory then
                        total_delivered = total_delivered + burner.inventory.get_item_count({name = name, quality = quality})
                    end
                end)
                
                -- Ammo (car_ammo, turret_ammo, spider_ammo)
                pcall(function()
                    local ammo_inv = target_entity.get_inventory(defines.inventory.car_ammo) or
                                    target_entity.get_inventory(defines.inventory.turret_ammo) or
                                    target_entity.get_inventory(defines.inventory.spider_ammo)
                    if ammo_inv and ammo_inv.valid then
                        total_delivered = total_delivered + ammo_inv.get_item_count({name = name, quality = quality})
                    end
                end)
                
                -- Trunk
                pcall(function()
                    local trunk_inv = target_entity.get_inventory(defines.inventory.car_trunk) or
                                     target_entity.get_inventory(defines.inventory.spider_trunk) or
                                     target_entity.get_inventory(defines.inventory.cargo_wagon)
                    if trunk_inv and trunk_inv.valid then
                        total_delivered = total_delivered + trunk_inv.get_item_count({name = name, quality = quality})
                    end
                end)
                
                -- Equipment
                pcall(function()
                    if target_entity.grid and target_entity.grid.valid then
                        for _, equipment in pairs(target_entity.grid.equipment) do
                            if equipment.name == name then
                                total_delivered = total_delivered + 1
                            end
                        end
                    end
                end)
                
                -- Modules
                pcall(function()
                    local module_inv = target_entity.get_module_inventory()
                    if module_inv and module_inv.valid then
                        total_delivered = total_delivered + module_inv.get_item_count({name = name, quality = quality})
                    end
                end)
                
                log_debug("Финальная проверка: " .. name .. " запрошено=" .. requested .. " доставлено=" .. total_delivered)
                
                if total_delivered < requested then
                    all_delivered = false
                    log_debug("НЕ полностью доставлено: " .. name)
                    break
                end
            end
            
            if all_delivered then
                proxy.destroy()
                log_debug("PROXY УНИЧТОЖЕН - всё доставлено!")
            else
                log_debug("Proxy оставлен - частичная доставка")
            end
        end)
    end
    
    return any_success
end

-- Публичная функция с полной защитой от крашей
function ModuleRequests.satisfy_requests(proxy, target_entity, player)
    local success, result = pcall(satisfy_requests_internal, proxy, target_entity, player)
    
    if not success then
        -- Логируем ошибку но НЕ крашим игру
        if game then
            game.print("[NANO:MODULE] ⚠️ ОШИБКА: " .. tostring(result))
        end
        return false
    end
    
    return result or false
end

return ModuleRequests
