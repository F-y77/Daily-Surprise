-- 在文件开头添加
local LOG_LEVEL = GetModConfigData("log_level") or 2

-- 在文件开头添加清理记录表
local BUFF_CLEANUP = {}

-- 在文件开头补充全局表访问
local _G = GLOBAL
local TUNING = _G.TUNING
local TheNet = _G.TheNet
local AllPlayers = _G.AllPlayers
local Vector3 = _G.Vector3
local EQUIPSLOTS = _G.EQUIPSLOTS
local pcall = _G.pcall
local PI = _G.PI
local SpawnPrefab = _G.SpawnPrefab
local TheWorld = _G.TheWorld
local ACTIONS = _G.ACTIONS
local STRINGS = _G.STRINGS
local DEGREES = _G.DEGREES
local FRAMES = _G.FRAMES
local GetTime = _G.GetTime
local Sleep = _G.Sleep
local TheSim = _G.TheSim

-- 以下两行仅在开发测试时使用，发布模组前应删除
-- _G.CHEATS_ENABLED = true
-- _G.require("debugkeys")

-- 修改DebugLog函数
local function DebugLog(level, ...)
    if level > LOG_LEVEL then return end
    
    local args = {...}
    local message = "[每日惊喜] "
    for i, v in ipairs(args) do
        message = message .. tostring(v) .. " "
    end
    
    _G.print(message)
    if TheNet:GetIsServer() then
        TheNet:SystemMessage(message)
    end
end

-- mod初始化提示
DebugLog(1, "开始加载mod")

-- 安全地获取mod配置
local success, BUFF_DURATION = _G.pcall(function() 
    return GetModConfigData("buff_duration") 
end)

-- 配置错误处理
if not success or not BUFF_DURATION then
    DebugLog(1, "错误：无法获取mod配置，使用默认值1")
    BUFF_DURATION = 1
else
    DebugLog(1, "BUFF持续时间设置为:", BUFF_DURATION, "天")
end

-- 获取随机玩家数量配置
local success_players, RANDOM_PLAYERS_COUNT = _G.pcall(function() 
    return GetModConfigData("random_players_count") 
end)

-- 配置错误处理
if not success_players or not RANDOM_PLAYERS_COUNT then
    DebugLog(1, "错误：无法获取随机玩家数量配置，使用默认值1")
    RANDOM_PLAYERS_COUNT = 1
else
    DebugLog(1, "每日惊喜将随机选择", RANDOM_PLAYERS_COUNT, "名玩家")
end

-- 获取是否启用DEBUFF配置
local success_debuff, ENABLE_DEBUFF = _G.pcall(function() 
    return GetModConfigData("enable_debuff") 
end)

-- 配置错误处理
if not success_debuff then
    ENABLE_DEBUFF = false
end

-- 获取DEBUFF几率配置
local success_debuff_chance, DEBUFF_CHANCE = _G.pcall(function() 
    return GetModConfigData("debuff_chance") 
end)

-- 配置错误处理
if not success_debuff_chance then
    DEBUFF_CHANCE = 0.3
end

-- 全局变量声明
local lastday = -1  -- 记录上一次应用BUFF的天数
local LAST_SAVE_DAY = -1  -- 记录最后保存的天数

-- BUFF效果列表定义
local BUFF_LIST = {
    {
        name = "超级速度",
        fn = function(player)
            player.components.locomotor:SetExternalSpeedMultiplier(player, "speedbuff", 2)
            
            return function()
                if player:IsValid() then
                    player.components.locomotor:RemoveExternalSpeedMultiplier(player, "speedbuff")
                    DebugLog(3, "清理速度效果")
                end
            end
        end
    },
    {
        name = "巨人化",
        fn = function(player)
            local original_scale = player.Transform:GetScale()
            player.Transform:SetScale(original_scale * 1.5, original_scale * 1.5, original_scale * 1.5)
            
            return function()
                if player:IsValid() then
                    player.Transform:SetScale(original_scale, original_scale, original_scale)
                    DebugLog(3, "清理巨人化效果")
                end
            end
        end
    },
    {
        name = "饥饿加速",
        fn = function(player)
            if player.components.hunger then
                local old_rate = player.components.hunger.hungerrate
                player.components.hunger.hungerrate = old_rate * 2
                
                return function()
                    if player:IsValid() and player.components.hunger then
                        player.components.hunger.hungerrate = old_rate
                    end
                end
            end
        end
    },
    {
        name = "幸运日",
        fn = function(player)
            local old_onkilledother = player.OnKilledOther
            player.OnKilledOther = function(inst, data)
                if old_onkilledother then
                    old_onkilledother(inst, data)
                end
                
                if data and data.victim and data.victim.components.lootdropper then
                    if _G.math.random() < 0.5 then
                        data.victim.components.lootdropper:DropLoot()
                    end
                end
            end
            
            return function()
                if player:IsValid() then
                    player.OnKilledOther = old_onkilledother
                end
            end
        end
    },
    {
        name = "夜视能力",
        fn = function(player)
            if player.components.playervision then
                player.components.playervision:SetCustomCCTable({day = 0, dusk = 0, night = 0.7})
                
                return function()
                    if player:IsValid() and player.components.playervision then
                        player.components.playervision:SetCustomCCTable(nil)
                        DebugLog(3, "清理夜视效果")
                    end
                end
            end
        end
    },
    {
        name = "饥饿减缓",
        fn = function(player)
            if player.components.hunger then
                local old_rate = player.components.hunger.hungerrate
                player.components.hunger.hungerrate = old_rate * 0.5
                
                return function()
                    if player:IsValid() and player.components.hunger then
                        player.components.hunger.hungerrate = old_rate
                    end
                end
            end
        end
    },
    {
        name = "随机传送",
        fn = function(player)
            local task = player:DoPeriodicTask(30, function()
                if _G.math.random() < 0.3 then
                    local x, y, z = player.Transform:GetWorldPosition()
                    local offset = 20
                    local angle = _G.math.random() * 2 * _G.math.pi
                    local new_x = x + offset * _G.math.cos(angle)
                    local new_z = z + offset * _G.math.sin(angle)
                    
                    player.Physics:Teleport(new_x, 0, new_z)
                    
                    if player.components.talker then
                        player.components.talker:Say("哇！随机传送！")
                    end
                end
            end)
            
            return function()
                if task then task:Cancel() end
            end
        end
    },
    {
        name = "生物朋友",
        fn = function(player)
            player:AddTag("friendlycreatures")
            
            return function()
                if player:IsValid() then
                    player:RemoveTag("friendlycreatures")
                end
            end
        end
    },
    {
        name = "小矮人",
        fn = function(player)
            local original_scale = player.Transform:GetScale()
            player.Transform:SetScale(original_scale * 0.6, original_scale * 0.6, original_scale * 0.6)
            
            return function()
                if player:IsValid() then
                    player.Transform:SetScale(original_scale, original_scale, original_scale)
                end
            end
        end
    },
    {
        name = "彩虹光环",
        fn = function(player)
            local light = _G.SpawnPrefab("minerhatlight")
            if light then
                light.entity:SetParent(player.entity)
                light.Light:SetRadius(2)
                light.Light:SetFalloff(0.5)
                light.Light:SetIntensity(0.8)
                
                local colors = {
                    {r=1, g=0, b=0},   -- 红
                    {r=1, g=0.5, b=0}, -- 橙
                    {r=1, g=1, b=0},   -- 黄
                    {r=0, g=1, b=0},   -- 绿
                    {r=0, g=0, b=1},   -- 蓝
                    {r=0.5, g=0, b=0.5} -- 紫
                }
                
                local color_index = 1
                local color_task = _G.TheWorld:DoPeriodicTask(0.5, function()
                    color_index = color_index % #colors + 1
                    local color = colors[color_index]
                    light.Light:SetColour(color.r, color.g, color.b)
                end)
                
                return function()
                    if color_task then color_task:Cancel() end
                    if light and light:IsValid() then
                        light:Remove()
                    end
                end
            end
        end
    },
    {
        name = "元素亲和",
        fn = function(player)
            local original = {
                overheat = player.components.temperature.overheattemp,
                freeze = player.components.temperature.freezetemp
            }
            
            player.components.temperature.overheattemp = 100
            player.components.temperature.freezetemp = -100
            
            return function()
                if player:IsValid() and player.components.temperature then
                    player.components.temperature.overheattemp = original.overheat
                    player.components.temperature.freezetemp = original.freeze
                end
            end
        end
    },
    {
        name = "光合作用",
        fn = function(player)
            local task = player:DoPeriodicTask(10, function()
                if player:IsValid() and TheWorld.state.isday then
                    if player.components.health then
                        player.components.health:DoDelta(5)
                    end
                    if player.components.hunger then
                        player.components.hunger:DoDelta(5)
                    end
                end
            end)
            
            return function()
                if task then task:Cancel() end
            end
        end
    },
    {
        name = "幸运垂钓",
        fn = function(player)
            if not player.components.fisherman then
                DebugLog(1, "玩家没有钓鱼组件")
                return
            end
            
            local old_catch = player.components.fisherman.OnCaughtFish
            player.components.fisherman.OnCaughtFish = function(self, fish, ...)
                local result = old_catch(self, fish, ...)
                if fish and fish.components.stackable 
                    and not fish:HasTag("rare") then
                    
                    fish.components.stackable:SetStackSize(fish.components.stackable.stacksize * 2)
                    DebugLog(3, "钓鱼收获加倍:", fish.prefab)
                end
                return result
            end
            
            return function()
                if player:IsValid() and player.components.fisherman then
                    player.components.fisherman.OnCaughtFish = old_catch
                    DebugLog(3, "清理幸运垂钓效果")
                end
            end
        end
    },
    {
        name = "星之祝福",
        fn = function(player)
            local star = _G.SpawnPrefab("stafflight")
            if star then
                star.entity:SetParent(player.entity)
                star.Transform:SetPosition(0, 3, 0)
                star.Light:SetColour(0.2, 0.6, 1)
                star.Light:SetIntensity(0.8)
                
                return function()
                    if star and star:IsValid() then
                        star:Remove()
                    end
                end
            end
        end
    },
    {
        name = "资源探测器",
        fn = function(player)
            local detect_range = 20
            local detect_task = player:DoPeriodicTask(5, function()
                if player:IsValid() then
                    local x, y, z = player.Transform:GetWorldPosition()
                    local ents = TheSim:FindEntities(x, y, z, detect_range, nil, {"INLIMBO"})
                    
                    for _, ent in pairs(ents) do
                        if ent.prefab and (
                            ent:HasTag("tree") or 
                            ent:HasTag("boulder") or 
                            ent:HasTag("flower") or
                            ent:HasTag("berry") or
                            ent.prefab == "flint" or
                            ent.prefab == "goldnugget"
                        ) then
                            -- 确保fx存在
                            local fx = SpawnPrefab("miniboatlantern_projected_ground")
                            if fx then
                                local ex, ey, ez = ent.Transform:GetWorldPosition()
                                fx.Transform:SetPosition(ex, 0, ez)
                                fx:DoTaskInTime(3, function() 
                                    if fx and fx:IsValid() then 
                                        fx:Remove() 
                                    end 
                                end)
                            end
                        end
                    end
                end
            end)
            
            return function()
                if detect_task then
                    detect_task:Cancel()
                    DebugLog(3, "清理资源探测器效果")
                end
            end
        end
    },
    {
        name = "食物保鲜",
        fn = function(player)
            local old_fn = player.components.inventory.DropItem
            player.components.inventory.DropItem = function(self, item, ...)
                if item and item.components.perishable then
                    item.components.perishable:SetPercent(1)
                end
                return old_fn(self, item, ...)
            end
            
            -- 定期刷新背包中的食物
            local refresh_task = player:DoPeriodicTask(60, function()
                if player:IsValid() and player.components.inventory then
                    local items = player.components.inventory:GetItems()
                    for _, item in pairs(items) do
                        if item and item.components.perishable then
                            item.components.perishable:SetPercent(1)
                        end
                    end
                end
            end)
            
            return function()
                if player:IsValid() and player.components.inventory then
                    player.components.inventory.DropItem = old_fn
                end
                if refresh_task then
                    refresh_task:Cancel()
                end
                DebugLog(3, "清理食物保鲜效果")
            end
        end
    },
    {
        name = "宠物召唤师",
        fn = function(player)
            -- 召唤一个跟随玩家的小动物
            local pet_type = {"rabbit", "perd", "butterfly", "robin"} -- 添加更多安全的宠物选项
            local pet = SpawnPrefab(pet_type[math.random(#pet_type)])
            
            if pet then
                local x, y, z = player.Transform:GetWorldPosition()
                pet.Transform:SetPosition(x, y, z)
                
                -- 让宠物跟随玩家
                local follow_task = pet:DoPeriodicTask(1, function()
                    if player:IsValid() and pet:IsValid() then
                        local px, py, pz = player.Transform:GetWorldPosition()
                        local ex, ey, ez = pet.Transform:GetWorldPosition()
                        local dist = math.sqrt((px-ex)^2 + (pz-ez)^2)
                        
                        if dist > 10 then
                            -- 瞬移到玩家附近
                            local angle = math.random() * 2 * PI
                            local radius = 3 + math.random() * 2
                            pet.Transform:SetPosition(px + radius * math.cos(angle), 0, pz + radius * math.sin(angle))
                        elseif dist > 3 then
                            -- 向玩家移动
                            if pet.components.locomotor then
                                pet.components.locomotor:GoToPoint(Vector3(px, py, pz))
                            end
                        end
                        
                        -- 防止宠物被攻击
                        if pet.components.health then
                            pet.components.health:SetInvincible(true)
                        end
                        
                        -- 防止宠物攻击玩家
                        if pet.components.combat then
                            pet.components.combat:SetTarget(nil)
                        end
                    end
                end)
                
                return function()
                    if follow_task then
                        follow_task:Cancel()
                    end
                    if pet and pet:IsValid() then
                        pet:Remove()
                    end
                    DebugLog(3, "清理宠物召唤师效果")
                end
            else
                return function() end
            end
        end
    },
    {
        name = "蜜蜂朋友",
        fn = function(player)
            local bee_count = 3
            local bees = {}
            
            -- 生成蜜蜂
            for i = 1, bee_count do
                local bee = SpawnPrefab("bee")
                if bee then
                    local x, y, z = player.Transform:GetWorldPosition()
                    local angle = 2 * PI * i / bee_count
                    local radius = 2
                    bee.Transform:SetPosition(x + radius * math.cos(angle), y, z + radius * math.sin(angle))
                    
                    -- 让蜜蜂友好
                    if bee.components.combat then
                        bee:RemoveComponent("combat")
                    end
                    
                    -- 让蜜蜂跟随玩家
                    local follow_task = bee:DoPeriodicTask(0.5, function()
                        if player:IsValid() and bee:IsValid() then
                            local px, py, pz = player.Transform:GetWorldPosition()
                            local ex, ey, ez = bee.Transform:GetWorldPosition()
                            local dist = math.sqrt((px-ex)^2 + (pz-ez)^2)
                            
                            if dist > 10 then
                                -- 瞬移到玩家附近
                                local angle = math.random() * 2 * PI
                                local radius = 2 + math.random()
                                bee.Transform:SetPosition(px + radius * math.cos(angle), py, pz + radius * math.sin(angle))
                            elseif dist > 3 then
                                -- 向玩家移动
                                if bee.components.locomotor then
                                    bee.components.locomotor:GoToPoint(Vector3(px, py, pz))
                                end
                            end
                        end
                    end)
                    
                    -- 定期产生蜂蜜
                    local honey_task = bee:DoPeriodicTask(120, function()
                        if player:IsValid() and bee:IsValid() then
                            local honey = SpawnPrefab("honey")
                            if honey then
                                local x, y, z = player.Transform:GetWorldPosition()
                                honey.Transform:SetPosition(x, y, z)
                                if player.components.talker then
                                    player.components.talker:Say("蜜蜂朋友给了我蜂蜜！")
                                end
                            end
                        end
                    end)
                    
                    table.insert(bees, {bee = bee, follow_task = follow_task, honey_task = honey_task})
                end
            end
            
            return function()
                for _, bee_data in ipairs(bees) do
                    if bee_data.follow_task then
                        bee_data.follow_task:Cancel()
                    end
                    if bee_data.honey_task then
                        bee_data.honey_task:Cancel()
                    end
                    if bee_data.bee and bee_data.bee:IsValid() then
                        bee_data.bee:Remove()
                    end
                end
                DebugLog(3, "清理蜜蜂朋友效果")
            end
        end
    },
    {
        name = "植物掌控",
        fn = function(player)
            -- 加快附近植物生长
            local growth_task = player:DoPeriodicTask(10, function()
                if player:IsValid() then
                    local x, y, z = player.Transform:GetWorldPosition()
                    local ents = TheSim:FindEntities(x, y, z, 15, nil, {"INLIMBO"})
                    
                    for _, ent in pairs(ents) do
                        -- 加速树木生长
                        if ent.components.growable then
                            ent.components.growable:DoGrowth()
                        end
                        
                        -- 加速作物生长
                        if ent.components.crop then
                            ent.components.crop:DoGrow(5)
                        end
                        
                        -- 加速浆果生长
                        if ent.components.pickable and ent.components.pickable.targettime then
                            ent.components.pickable.targettime = ent.components.pickable.targettime - 120
                        end
                    end
                end
            end)
            
            -- 走过的地方有几率长出花朵
            local flower_task = player:DoPeriodicTask(3, function()
                if player:IsValid() and player:HasTag("moving") then
                    local x, y, z = player.Transform:GetWorldPosition()
                    if math.random() < 0.3 then
                        local flower = SpawnPrefab("flower")
                        if flower then
                            local offset = 1.5
                            flower.Transform:SetPosition(
                                x + math.random(-offset, offset), 
                                0, 
                                z + math.random(-offset, offset)
                            )
                        end
                    end
                end
            end)
            
            return function()
                if growth_task then
                    growth_task:Cancel()
                end
                if flower_task then
                    flower_task:Cancel()
                end
                DebugLog(3, "清理植物掌控效果")
            end
        end
    },
    {
        name = "元素掌控",
        fn = function(player)
            -- 添加元素光环效果
            local fx = SpawnPrefab("lavaarena_creature_teleport_small_fx")
            if fx then
                fx.entity:SetParent(player.entity)
                fx.Transform:SetPosition(0, 0, 0)
            end
            
            -- 添加元素攻击能力
            local old_attack = ACTIONS.ATTACK.fn
            ACTIONS.ATTACK.fn = function(act)
                local target = act.target
                local doer = act.doer
                
                if doer == player and target and target:IsValid() then
                    -- 随机元素效果
                    local element = math.random(3)
                    
                    if element == 1 then  -- 火
                        if target.components.burnable and not target.components.burnable:IsBurning() then
                            target.components.burnable:Ignite()
                        end
                    elseif element == 2 then  -- 冰
                        if target.components.freezable then
                            target.components.freezable:AddColdness(2)
                        end
                    else  -- 电
                        local x, y, z = target.Transform:GetWorldPosition()
                        TheWorld:PushEvent("ms_sendlightningstrike", Vector3(x, y, z))
                    end
                end
                
                return old_attack(act)
            end
            
            return function()
                ACTIONS.ATTACK.fn = old_attack
                if fx and fx:IsValid() then
                    fx:Remove()
                end
                DebugLog(3, "清理元素掌控效果")
            end
        end
    },
    {
        name = "影分身",
        fn = function(player)
            -- 创建影子分身
            local shadow = SpawnPrefab("shadowduelist")
            if shadow then
                local x, y, z = player.Transform:GetWorldPosition()
                shadow.Transform:SetPosition(x, y, z)
                
                -- 让影子分身跟随玩家
                local follow_task = shadow:DoPeriodicTask(0.5, function()
                    if player:IsValid() and shadow:IsValid() then
                        local px, py, pz = player.Transform:GetWorldPosition()
                        local sx, sy, sz = shadow.Transform:GetWorldPosition()
                        local dist = math.sqrt((px-sx)^2 + (pz-sz)^2)
                        
                        if dist > 15 then
                            -- 瞬移到玩家附近
                            shadow.Transform:SetPosition(px, py, pz)
                        elseif dist > 3 then
                            -- 向玩家移动
                            if shadow.components.locomotor then
                                shadow.components.locomotor:GoToPoint(Vector3(px, py, pz))
                            end
                        end
                        
                        -- 攻击玩家附近的敌人
                        if shadow.components.combat then
                            local enemies = TheSim:FindEntities(sx, sy, sz, 10, nil, {"player", "INLIMBO"})
                            local target = nil
                            
                            for _, ent in ipairs(enemies) do
                                if ent.components.combat and 
                                   ent.components.combat.target == player and
                                   ent:IsValid() then
                                    target = ent
                                    break
                                end
                            end
                            
                            if target then
                                shadow.components.combat:SetTarget(target)
                            end
                        end
                    end
                end)
                
                return function()
                    if follow_task then
                        follow_task:Cancel()
                    end
                    if shadow and shadow:IsValid() then
                        shadow:Remove()
                    end
                    DebugLog(3, "清理影分身效果")
                end
            end
            
            return function() end
        end
    },
    {
        name = "宝藏探测",
        fn = function(player)
            -- 每隔一段时间在玩家附近生成一个宝藏
            local treasure_task = player:DoPeriodicTask(240, function()
                if player:IsValid() then
                    local x, y, z = player.Transform:GetWorldPosition()
                    local offset = 10
                    local treasure_x = x + math.random(-offset, offset)
                    local treasure_z = z + math.random(-offset, offset)
                    
                    -- 创建宝藏标记
                    local marker = SpawnPrefab("messagebottle")
                    if marker then
                        marker.Transform:SetPosition(treasure_x, 0, treasure_z)
                        
                        -- 在宝藏位置添加特效
                        local fx = SpawnPrefab("cane_candy_fx")
                        if fx then
                            fx.Transform:SetPosition(treasure_x, 0.5, treasure_z)
                            fx:DoTaskInTime(5, function() fx:Remove() end)
                        end
                        
                        if player.components.talker then
                            player.components.talker:Say("我感觉附近有宝藏！")
                        end
                    end
                end
            end)
            
            return function()
                if treasure_task then
                    treasure_task:Cancel()
                    DebugLog(3, "清理宝藏探测效果")
                end
            end
        end
    },
    {
        name = "火焰之友",
        fn = function(player)
            -- 免疫火焰伤害
            player:AddTag("fireimmune")
            
            -- 走路时留下火焰痕迹
            local fire_trail_task = player:DoPeriodicTask(0.5, function()
                if player:IsValid() and player:HasTag("moving") then
                    local x, y, z = player.Transform:GetWorldPosition()
                    
                    -- 有几率生成火焰
                    if math.random() < 0.3 then
                        local fire = SpawnPrefab("campfirefire")
                        if fire then
                            fire.Transform:SetPosition(x, 0, z)
                            fire:DoTaskInTime(3, function() fire:Remove() end)
                        end
                    end
                end
            end)
            
            return function()
                if player:IsValid() then
                    player:RemoveTag("fireimmune")
                    if fire_trail_task then
                        fire_trail_task:Cancel()
                    end
                    DebugLog(3, "清理火焰之友效果")
                end
            end
        end
    },
}

-- DEBUFF效果列表定义 (负面效果)
local DEBUFF_LIST = {
    {
        name = "蜗牛速度",
        fn = function(player)
            player.components.locomotor:SetExternalSpeedMultiplier(player, "speedebuff", 0.5)
            
            return function()
                if player:IsValid() then
                    player.components.locomotor:RemoveExternalSpeedMultiplier(player, "speedebuff")
                end
            end
        end
    },
    {
        name = "虚弱无力",
        fn = function(player)
            if player.components.combat then
                local old_damage = player.components.combat.damagemultiplier or 1
                player.components.combat.damagemultiplier = old_damage * 0.5
                
                return function()
                    if player:IsValid() and player.components.combat then
                        player.components.combat.damagemultiplier = old_damage
                    end
                end
            end
        end
    },
    {
        name = "易碎玻璃",
        fn = function(player)
            if player.components.health then
                local old_absorb = player.components.health.absorb or 0
                player.components.health.absorb = math.max(0, old_absorb - 0.3)
                
                return function()
                    if player:IsValid() and player.components.health then
                        player.components.health.absorb = old_absorb
                    end
                end
            end
        end
    },
    {
        name = "噩梦缠身",
        fn = function(player)
            if player.components.sanity then
                local task = player:DoPeriodicTask(60, function()
                    if player:IsValid() and player.components.sanity then
                        player.components.sanity:DoDelta(-10)
                        if player.components.talker then
                            player.components.talker:Say("我感觉不太好...")
                        end
                    end
                end)
                
                return function()
                    if task then task:Cancel() end
                end
            end
        end
    },
    {
        name = "饥肠辘辘",
        fn = function(player)
            if player.components.hunger then
                local old_rate = player.components.hunger.hungerrate
                player.components.hunger.hungerrate = old_rate * 3
                
                return function()
                    if player:IsValid() and player.components.hunger then
                        player.components.hunger.hungerrate = old_rate
                    end
                end
            end
        end
    },
    {
        name = "体温失调",
        fn = function(player)
            if player.components.temperature then
                local old_GetTemp = player.components.temperature.GetTemp
                player.components.temperature.GetTemp = function(self)
                    local temp = old_GetTemp(self)
                    if _G.TheWorld.state.iswinter then
                        return temp + 10
                    elseif _G.TheWorld.state.issummer then
                        return temp - 10
                    end
                    return temp
                end
                
                return function()
                    if player:IsValid() and player.components.temperature then
                        player.components.temperature.GetTemp = old_GetTemp
                    end
                end
            end
        end
    },
    {
        name = "黑暗恐惧",
        fn = function(player)
            if player.components.playervision then
                player.components.playervision:SetCustomCCTable({day = 0, dusk = 0, night = 0.7})
                
                return function()
                    if player:IsValid() and player.components.playervision then
                        player.components.playervision:SetCustomCCTable(nil)
                    end
                end
            end
        end
    },
    {
        name = "笨手笨脚",
        fn = function(player)
            if player.components.workmultiplier then
                player.components.workmultiplier:AddMultiplier(_G.ACTIONS.MINE, 0.5)
                player.components.workmultiplier:AddMultiplier(_G.ACTIONS.CHOP, 0.5)
                player.components.workmultiplier:AddMultiplier(_G.ACTIONS.HAMMER, 0.5)
                
                return function()
                    if player:IsValid() and player.components.workmultiplier then
                        player.components.workmultiplier:RemoveMultiplier(_G.ACTIONS.MINE)
                        player.components.workmultiplier:RemoveMultiplier(_G.ACTIONS.CHOP)
                        player.components.workmultiplier:RemoveMultiplier(_G.ACTIONS.HAMMER)
                    end
                end
            end
        end
    },
    {
        name = "倒霉蛋",
        fn = function(player)
            local old_onkilledother = player.OnKilledOther
            player.OnKilledOther = function(inst, data)
                if old_onkilledother then
                    old_onkilledother(inst, data)
                end
                
                if data and data.victim and data.victim.components.lootdropper then
                    if _G.math.random() < 0.5 then
                        data.victim.components.lootdropper.loot = {}
                    end
                end
            end
            
            return function()
                if player:IsValid() then
                    player.OnKilledOther = old_onkilledother
                end
            end
        end
    },
    {
        name = "噪音制造者",
        fn = function(player)
            local task = player:DoPeriodicTask(120, function()
                if player:IsValid() then
                    local x, y, z = player.Transform:GetWorldPosition()
                    player.components.talker:Say("我感觉有东西在靠近...")
                    
                    local monsters = {"hound", "spider", "killerbee"}
                    local monster = monsters[_G.math.random(#monsters)]
                    local count = _G.math.random(2, 4)
                    
                    for i = 1, count do
                        local angle = _G.math.random() * 2 * _G.math.pi
                        local dist = _G.math.random(10, 15)
                        local spawn_x = x + dist * _G.math.cos(angle)
                        local spawn_z = z + dist * _G.math.sin(angle)
                        
                        local monster_inst = _G.SpawnPrefab(monster)
                        if monster_inst then
                            monster_inst.Transform:SetPosition(spawn_x, 0, spawn_z)
                            if monster_inst.components.combat then
                                monster_inst.components.combat:SetTarget(player)
                            end
                        end
                    end
                end
            end)
            
            return function()
                if task then task:Cancel() end
            end
        end
    },
    {
        name = "方向混乱",
        fn = function(player)
            if not player.components.locomotor then return end
            
            -- 保存原始控制函数
            local old_GetControlMods = player.components.locomotor.GetControlMods
            player.components.locomotor.GetControlMods = function(self)
                local forward, sideways = old_GetControlMods(self)
                -- 反转移动方向
                return -forward, -sideways
            end
            
            -- 返回清理函数
            return function()
                if player:IsValid() and player.components.locomotor then
                    player.components.locomotor.GetControlMods = old_GetControlMods
                    DebugLog(3, "清理方向混乱效果")
                end
            end
        end
    },
    {
        name = "物品腐蚀",
        fn = function(player)
            local task = player:DoPeriodicTask(60, function()
                if player:IsValid() and player.components.inventory then
                    local item = player.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
                    if item and item.components.finiteuses then
                        item.components.finiteuses:Use(10)
                    end
                end
            end)
            
            return function()
                if task then task:Cancel() end
            end
        end
    },
    {
        name = "幻影追击",
        fn = function(player)
            local function SpawnPhantom()
                if not player:IsValid() then return end
                
                local phantom = _G.SpawnPrefab("shadowcreature")
                if phantom then
                    local x, y, z = player.Transform:GetWorldPosition()
                    local angle = math.random() * 2 * _G.PI
                    local spawn_dist = 15
                    phantom.Transform:SetPosition(
                        x + math.cos(angle)*spawn_dist, 
                        0, 
                        z + math.sin(angle)*spawn_dist
                    )
                    if phantom.components.combat then
                        phantom.components.combat:SetTarget(player)
                    end
                end
            end
            
            local task = player:DoPeriodicTask(120, SpawnPhantom)
            
            return function()
                if task then 
                    task:Cancel() 
                    DebugLog(3, "清理幻影追击效果")
                end
            end
        end
    },
    {
        name = "感官失调",
        fn = function(player)
            local task = player:DoPeriodicTask(30, function()
                if player:IsValid() then
                    if player.components.health and player.components.hunger then
                        local health = player.components.health.currenthealth
                        local hunger = player.components.hunger.current
                        player.components.health:SetCurrentHealth(hunger)
                        player.components.hunger:SetCurrent(health)
                    end
                end
            end)
            
            return function()
                if task then task:Cancel() end
            end
        end
    },
    {
        name = "物品掉落",
        fn = function(player)
            local drop_task = player:DoPeriodicTask(60, function()
                if player:IsValid() and player.components.inventory then
                    local items = player.components.inventory:GetItems()
                    if #items > 0 then
                        local item = items[math.random(#items)]
                        if item then
                            player.components.inventory:DropItem(item)
                            if TheNet:GetIsServer() then
                                TheNet:SystemMessage("玩家 " .. player.name .. " 的物品突然掉落了！")
                            end
                        end
                    end
                end
            end)
            
            return function()
                if drop_task then
                    drop_task:Cancel()
                    DebugLog(3, "清理物品掉落效果")
                end
            end
        end
    },
    {
        name = "幻影追踪",
        fn = function(player)
            local shadow_task = player:DoPeriodicTask(30, function()
                if player:IsValid() then
                    local x, y, z = player.Transform:GetWorldPosition()
                    local shadow = SpawnPrefab("terrorbeak")
                    
                    if shadow then
                        shadow.Transform:SetPosition(x + 15, 0, z + 15)
                        shadow:DoTaskInTime(15, function() 
                            if shadow and shadow:IsValid() then
                                shadow:Remove() 
                            end
                        end)
                        
                        if shadow.components.combat then
                            shadow.components.combat:SetTarget(player)
                        end
                    end
                end
            end)
            
            return function()
                if shadow_task then
                    shadow_task:Cancel()
                    DebugLog(3, "清理幻影追踪效果")
                end
            end
        end
    },
    {
        name = "饥饿幻觉",
        fn = function(player)
            if player.components.hunger then
                local old_GetPercent = player.components.hunger.GetPercent
                player.components.hunger.GetPercent = function(self)
                    return old_GetPercent(self) * 0.5
                end
                
                return function()
                    if player:IsValid() and player.components.hunger then
                        player.components.hunger.GetPercent = old_GetPercent
                        DebugLog(3, "清理饥饿幻觉效果")
                    end
                end
            end
            return function() end
        end
    },
    {
        name = "工具易碎",
        fn = function(player)
            local old_fn = nil
            if player.components.inventory then
                old_fn = player.components.inventory.DropItem
                player.components.inventory.DropItem = function(self, item, ...)
                    if item and item.components.finiteuses then
                        local current = item.components.finiteuses:GetPercent()
                        item.components.finiteuses:SetPercent(current * 0.8)
                    end
                    return old_fn(self, item, ...)
                end
            end
            
            -- 使用工具时额外消耗耐久
            local old_use_item = ACTIONS.CHOP.fn
            ACTIONS.CHOP.fn = function(act)
                local result = old_use_item(act)
                if act.doer == player and act.invobject and act.invobject.components.finiteuses then
                    act.invobject.components.finiteuses:Use(2)
                end
                return result
            end
            
            return function()
                if player:IsValid() and player.components.inventory and old_fn then
                    player.components.inventory.DropItem = old_fn
                end
                ACTIONS.CHOP.fn = old_use_item
                DebugLog(3, "清理工具易碎效果")
            end
        end
    },
    {
        name = "幽灵缠身",
        fn = function(player)
            -- 定期生成幽灵跟随玩家
            local ghosts = {}
            local max_ghosts = 3
            
            local ghost_task = player:DoPeriodicTask(60, function()
                if player:IsValid() and #ghosts < max_ghosts then
                    local x, y, z = player.Transform:GetWorldPosition()
                    local ghost = SpawnPrefab("ghost")
                    
                    if ghost then
                        -- 设置位置
                        local angle = math.random() * 2 * PI
                        local radius = 5
                        ghost.Transform:SetPosition(
                            x + radius * math.cos(angle),
                            0,
                            z + radius * math.sin(angle)
                        )
                        
                        -- 让幽灵跟随玩家
                        local follow_task = ghost:DoPeriodicTask(1, function()
                            if player:IsValid() and ghost:IsValid() then
                                local px, py, pz = player.Transform:GetWorldPosition()
                                local gx, gy, gz = ghost.Transform:GetWorldPosition()
                                local dist = math.sqrt((px-gx)^2 + (pz-gz)^2)
                                
                                if dist > 15 then
                                    -- 瞬移到玩家附近
                                    local angle = math.random() * 2 * PI
                                    ghost.Transform:SetPosition(
                                        px + 5 * math.cos(angle),
                                        0,
                                        pz + 5 * math.sin(angle)
                                    )
                                elseif dist > 3 then
                                    -- 向玩家移动
                                    if ghost.components.locomotor then
                                        ghost.components.locomotor:GoToPoint(Vector3(px, py, pz))
                                    end
                                end
                            end
                        end)
                        
                        -- 降低玩家理智
                        if player.components.sanity then
                            player.components.sanity:DoDelta(-5)
                        end
                        
                        table.insert(ghosts, {ghost = ghost, follow_task = follow_task})
                    end
                end
            end)
            
            return function()
                for _, ghost_data in ipairs(ghosts) do
                    if ghost_data.follow_task then
                        ghost_data.follow_task:Cancel()
                    end
                    if ghost_data.ghost and ghost_data.ghost:IsValid() then
                        ghost_data.ghost:Remove()
                    end
                end
                if ghost_task then
                    ghost_task:Cancel()
                end
                DebugLog(3, "清理幽灵缠身效果")
            end
        end
    },
    {
        name = "时间错乱",
        fn = function(player)
            -- 玩家周围的时间流速不稳定
            local time_task = player:DoPeriodicTask(30, function()
                if player:IsValid() then
                    -- 随机时间效果
                    local effect = math.random(3)
                    
                    if effect == 1 then
                        -- 时间加速
                        TheWorld:PushEvent("ms_setclocksegs", {day = 8, dusk = 2, night = 2})
                        if player.components.talker then
                            player.components.talker:Say("时间似乎加速了！")
                        end
                    elseif effect == 2 then
                        -- 时间减慢
                        TheWorld:PushEvent("ms_setclocksegs", {day = 4, dusk = 6, night = 6})
                        if player.components.talker then
                            player.components.talker:Say("时间似乎减慢了...")
                        end
                    else
                        -- 恢复正常
                        TheWorld:PushEvent("ms_setclocksegs", {day = 6, dusk = 4, night = 2})
                        if player.components.talker then
                            player.components.talker:Say("时间恢复正常了")
                        end
                    end
                end
            end)
            
            return function()
                if time_task then
                    time_task:Cancel()
                end
                -- 恢复正常时间设置
                TheWorld:PushEvent("ms_setclocksegs", {day = 6, dusk = 4, night = 2})
                DebugLog(3, "清理时间错乱效果")
            end
        end
    },
    {
        name = "噩梦入侵",
        fn = function(player)
            -- 玩家周围会随机出现噩梦生物的幻影
            local nightmare_task = player:DoPeriodicTask(45, function()
                if player:IsValid() then
                    local x, y, z = player.Transform:GetWorldPosition()
                    
                    -- 创建噩梦生物
                    local nightmare_creatures = {"crawlinghorror", "terrorbeak", "nightmarebeak"}
                    local creature = SpawnPrefab(nightmare_creatures[math.random(#nightmare_creatures)])
                    
                    if creature then
                        -- 设置位置
                        local offset = 10
                        creature.Transform:SetPosition(
                            x + math.random(-offset, offset),
                            0,
                            z + math.random(-offset, offset)
                        )
                        
                        -- 设置目标
                        if creature.components.combat then
                            creature.components.combat:SetTarget(player)
                        end
                        
                        -- 一段时间后消失
                        creature:DoTaskInTime(20, function()
                            if creature and creature:IsValid() then
                                local fx = SpawnPrefab("shadow_despawn")
                                if fx then
                                    local cx, cy, cz = creature.Transform:GetWorldPosition()
                                    fx.Transform:SetPosition(cx, cy, cz)
                                end
                                creature:Remove()
                            end
                        end)
                        
                        -- 降低玩家理智
                        if player.components.sanity then
                            player.components.sanity:DoDelta(-10)
                        end
                        
                        if player.components.talker then
                            player.components.talker:Say("噩梦正在入侵现实！")
                        end
                    end
                end
            end)
            
            return function()
                if nightmare_task then
                    nightmare_task:Cancel()
                end
                DebugLog(3, "清理噩梦入侵效果")
            end
        end
    },
    {
        name = "失重状态",
        fn = function(player)
            -- 修改玩家的物理属性
            local old_mass = player.Physics:GetMass()
            player.Physics:SetMass(0.1)
            
            -- 随机浮空效果
            local float_task = player:DoPeriodicTask(10, function()
                if player:IsValid() then
                    -- 玩家突然"浮起"
                    if player.components.talker then
                        player.components.talker:Say("我感觉自己要飘起来了！")
                    end
                    
                    -- 创建浮空效果
                    local float_time = 3
                    local start_time = GetTime()
                    local start_y = 0
                    
                    player:StartThread(function()
                        while GetTime() - start_time < float_time do
                            local t = (GetTime() - start_time) / float_time
                            local height = math.sin(t * math.pi) * 3 -- 最高浮到3个单位高
                            
                            local x, _, z = player.Transform:GetWorldPosition()
                            player.Transform:SetPosition(x, height, z)
                            
                            Sleep(FRAMES)
                        end
                        
                        -- 回到地面
                        local x, _, z = player.Transform:GetWorldPosition()
                        player.Transform:SetPosition(x, 0, z)
                    end)
                end
            end)
            
            -- 物品经常从玩家手中掉落
            local drop_task = player:DoPeriodicTask(20, function()
                if player:IsValid() and player.components.inventory then
                    local equipped = player.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
                    if equipped then
                        player.components.inventory:DropItem(equipped)
                        if player.components.talker then
                            player.components.talker:Say("我抓不住东西了！")
                        end
                    end
                end
            end)
            
            return function()
                if float_task then
                    float_task:Cancel()
                end
                if drop_task then
                    drop_task:Cancel()
                end
                if player:IsValid() and player.Physics then
                    player.Physics:SetMass(old_mass)
                    -- 确保玩家回到地面
                    local x, _, z = player.Transform:GetWorldPosition()
                    player.Transform:SetPosition(x, 0, z)
                end
                DebugLog(3, "清理失重状态效果")
            end
        end
    },
    {
        name = "雷电吸引",
        fn = function(player)
            -- 有几率在玩家附近落雷
            local lightning_task = player:DoPeriodicTask(30, function()
                if player:IsValid() and math.random() < 0.5 then
                    local x, y, z = player.Transform:GetWorldPosition()
                    local offset = 3
                    local lightning_x = x + math.random(-offset, offset)
                    local lightning_z = z + math.random(-offset, offset)
                    
                    -- 创建闪电
                    local lightning = SpawnPrefab("lightning")
                    if lightning then
                        lightning.Transform:SetPosition(lightning_x, 0, lightning_z)
                        
                        -- 对玩家造成伤害
                        if math.random() < 0.3 and player.components.health then
                            player.components.health:DoDelta(-5)
                            if player.components.talker then
                                player.components.talker:Say("我好像吸引了雷电！")
                            end
                        end
                    end
                end
            end)
            
            return function()
                if lightning_task then
                    lightning_task:Cancel()
                    DebugLog(3, "清理雷电吸引效果")
                end
            end
        end
    },
}

-- 安全地应用BUFF/DEBUFF效果
local function SafeApplyBuff(player)
    if not player or not player.components then return end
    
    -- 先清理已有效果
    if BUFF_CLEANUP[player] then
        DebugLog(2, "清理玩家之前的BUFF效果:", player.name)
        for _, cleanup_fn in ipairs(BUFF_CLEANUP[player]) do
            pcall(cleanup_fn)
        end
        BUFF_CLEANUP[player] = nil
    end

    -- 根据配置决定是否有几率应用DEBUFF
    local buff_list = BUFF_LIST
    local effect_type = "惊喜"
    
    if ENABLE_DEBUFF and _G.math.random() < DEBUFF_CHANCE then
        buff_list = DEBUFF_LIST
        effect_type = "惊吓"
    end
    
    local buff = buff_list[_G.math.random(#buff_list)]
    if buff and buff.fn then
        local cleanup_actions = {}
        local success, error_msg = pcall(function()
            -- 应用效果并获取清理函数
            local cleanup = buff.fn(player)
            if cleanup then
                table.insert(cleanup_actions, cleanup)
                -- 设置定时器在BUFF持续时间结束后自动清理
                player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                    if cleanup_actions[1] then
                        pcall(cleanup_actions[1])
                        BUFF_CLEANUP[player] = nil
                    end
                end)
            end
        end)
        
        if success then
            BUFF_CLEANUP[player] = cleanup_actions
            DebugLog(1, "成功应用" .. effect_type .. ":", buff.name)
            if player.components.talker then
                player.components.talker:Say("获得每日" .. effect_type .. ": " .. buff.name)
            end
        else
            DebugLog(1, "应用" .. effect_type .. "失败:", buff.name, error_msg)
        end
    end
end

-- 修改世界日期变化监听
AddPrefabPostInit("world", function(inst)
    if not _G.TheWorld.ismastersim then return end
    
    inst:WatchWorldState("cycles", function()
        local currentday = _G.TheWorld.state.cycles
        
        -- 检查是否是新的一天
        if currentday > lastday then
            -- 如果只跳过了1天或者是相邻的天数，则应用BUFF
            if currentday <= lastday + 2 then
                DebugLog(1, "新的一天开始，应用BUFF")
                
                -- 获取所有在线玩家
                local players = {}
                for _, v in ipairs(AllPlayers) do
                    if v:IsValid() then
                        table.insert(players, v)
                    end
                end
                
                DebugLog(1, "在线玩家数量:", #players, "将选择:", math.min(RANDOM_PLAYERS_COUNT, #players), "名玩家")
                
                -- 确定要选择的玩家数量
                local select_count = math.min(RANDOM_PLAYERS_COUNT, #players)
                if RANDOM_PLAYERS_COUNT >= 12 then
                    select_count = #players
                end
                
                -- 随机选择玩家
                local selected_players = {}
                while #selected_players < select_count and #players > 0 do
                    local index = _G.math.random(#players)
                    table.insert(selected_players, players[index])
                    table.remove(players, index)
                end
                
                -- 给选中的玩家应用BUFF
                for _, player in ipairs(selected_players) do
                    DebugLog(1, "正在给玩家", player.name or "未知", "应用BUFF")
                    SafeApplyBuff(player)
                    
                    -- 通知所有玩家谁获得了每日惊喜
                    if TheNet:GetIsServer() then
                        local message = string.format("玩家 %s 获得了每日惊喜！", player.name or "未知")
                        TheNet:SystemMessage(message)
                    end
                end
            else
                -- 如果跳过了2天以上，只更新记录的天数，不应用BUFF
                DebugLog(1, "检测到跳过多天，跳过BUFF应用")
            end
            
            -- 更新记录的天数
            lastday = currentday
            LAST_SAVE_DAY = currentday
        end
    end)
    
    -- 添加存档加载时的处理
    inst:ListenForEvent("ms_worldsave", function()
        LAST_SAVE_DAY = _G.TheWorld.state.cycles
        DebugLog(3, "保存当前天数:", LAST_SAVE_DAY)
    end)
    
    inst:ListenForEvent("ms_worldload", function()
        local currentday = _G.TheWorld.state.cycles
        if LAST_SAVE_DAY > 0 then
            -- 使用保存的天数来更新lastday
            lastday = LAST_SAVE_DAY
            DebugLog(3, "加载存档，使用保存的天数:", LAST_SAVE_DAY)
        else
            -- 首次加载时初始化
            lastday = currentday
            LAST_SAVE_DAY = currentday
            DebugLog(3, "首次加载，初始化天数:", currentday)
        end
    end)
end)

-- 玩家初始化时的处理
AddPlayerPostInit(function(inst)
    if not _G.TheWorld.ismastersim then return end
    
    inst:DoTaskInTime(1, function()
        if not inst:IsValid() then return end
        
        -- 如果玩家是在当天加入的，且已经有玩家获得了BUFF，则不再给该玩家BUFF
        -- 只有在新的一天开始时才会重新随机选择玩家
    end)

    -- 添加玩家离开处理
    inst:ListenForEvent("ms_playerleft", function()
        if BUFF_CLEANUP[inst] then
            DebugLog(2, "玩家离开，清理BUFF:", inst.name)
            for _, cleanup_fn in ipairs(BUFF_CLEANUP[inst]) do
                pcall(cleanup_fn)
            end
            BUFF_CLEANUP[inst] = nil
        end
    end)
end)

-- mod加载完成提示
DebugLog(1, "mod加载完成")