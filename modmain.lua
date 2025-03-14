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
    }
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
}

-- 安全地应用BUFF/DEBUFF效果
local function SafeApplyBuff(player)
    if not player or not player.components then return end
    
    -- 检查是否应该应用BUFF
    local currentday = _G.TheWorld.state.cycles
    if currentday ~= lastday then
        DebugLog(2, "天数不匹配，跳过BUFF应用")
        return
    end
    
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
        
        -- 只在相邻的天数变化时应用BUFF
        if currentday == lastday + 1 then
            lastday = currentday
            LAST_SAVE_DAY = currentday
            DebugLog(1, "新的一天开始，应用BUFF")
            
            -- 获取所有在线玩家
            local players = {}
            for _, v in ipairs(AllPlayers) do
                if v:IsValid() then
                    table.insert(players, v)
                end
            end
            
            -- 确定要选择的玩家数量
            local players_count = #players
            local select_count = math.min(RANDOM_PLAYERS_COUNT, players_count)
            
            DebugLog(1, "在线玩家数量:", players_count, "将选择:", select_count, "名玩家")
            
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
        elseif currentday > lastday + 1 then
            -- 如果跳过了多天，只更新记录的天数，不应用BUFF
            DebugLog(1, "检测到跳过天数，跳过BUFF应用")
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