 -- 设置全局表访问
local _G = GLOBAL
local TUNING = _G.TUNING
local TheNet = _G.TheNet
local AllPlayers = _G.AllPlayers
local Vector3 = _G.Vector3

-- 以下两行仅在开发测试时使用，发布模组前应删除
-- _G.CHEATS_ENABLED = true
-- _G.require("debugkeys")

-- 调试日志函数，同时在控制台和服务器显示信息
local function DebugLog(...)
    _G.print("[每日惊喜]", ...)
    if TheNet:GetIsServer() then
        -- 修复：SystemMessage需要字符串参数
        local message = "[每日惊喜] "
        for i, v in ipairs({...}) do
            message = message .. tostring(v) .. " "
        end
        TheNet:SystemMessage(message)
    end
end

-- mod初始化提示
DebugLog("开始加载mod")

-- 安全地获取mod配置
local success, BUFF_DURATION = _G.pcall(function() 
    return GetModConfigData("buff_duration") 
end)

-- 配置错误处理
if not success or not BUFF_DURATION then
    DebugLog("错误：无法获取mod配置，使用默认值1")
    BUFF_DURATION = 1
else
    DebugLog("BUFF持续时间设置为:", BUFF_DURATION, "天")
end

-- 获取随机玩家数量配置
local success_players, RANDOM_PLAYERS_COUNT = _G.pcall(function() 
    return GetModConfigData("random_players_count") 
end)

-- 配置错误处理
if not success_players or not RANDOM_PLAYERS_COUNT then
    DebugLog("错误：无法获取随机玩家数量配置，使用默认值1")
    RANDOM_PLAYERS_COUNT = 1
else
    DebugLog("每日惊喜将随机选择", RANDOM_PLAYERS_COUNT, "名玩家")
end

-- 全局变量声明
local lastday = -1  -- 记录上一次应用BUFF的天数

-- BUFF效果列表定义
local BUFF_LIST = {
    {
        name = "超级速度",
        fn = function(player)
            player.components.locomotor:SetExternalSpeedMultiplier(player, "speedbuff", 2)
            -- BUFF_DURATION天后移除效果
            player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                if player:IsValid() then
                    player.components.locomotor:RemoveExternalSpeedMultiplier(player, "speedbuff")
                end
            end)
        end
    },
    {
        name = "巨人化",
        fn = function(player)
            -- 保存原始体型
            local original_scale = player.Transform:GetScale()
            -- 放大玩家
            player.Transform:SetScale(original_scale * 1.5, original_scale * 1.5, original_scale * 1.5)
            -- BUFF_DURATION天后恢复
            player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                if player:IsValid() then
                    player.Transform:SetScale(original_scale, original_scale, original_scale)
                end
            end)
        end
    },
    {
        name = "饥饿加速",
        fn = function(player)
            if player.components.hunger then
                local old_rate = player.components.hunger.hungerrate
                player.components.hunger.hungerrate = old_rate * 2
                -- BUFF_DURATION天后移除效果
                player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                    if player:IsValid() and player.components.hunger then
                        player.components.hunger.hungerrate = old_rate
                    end
                end)
            end
        end
    },
    {
        name = "幸运日",
        fn = function(player)
            -- 监听杀死生物事件
            local old_onkilledother = player.OnKilledOther
            player.OnKilledOther = function(inst, data)
                if old_onkilledother then
                    old_onkilledother(inst, data)
                end
                
                if data and data.victim and data.victim.components.lootdropper then
                    -- 有50%几率掉落额外物品
                    if _G.math.random() < 0.5 then
                        data.victim.components.lootdropper:DropLoot()
                    end
                end
            end
            
            -- BUFF_DURATION天后移除效果
            player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                if player:IsValid() then
                    player.OnKilledOther = old_onkilledother
                end
            end)
        end
    },
    {
        name = "夜视能力",
        fn = function(player)
            if player.components.playervision then
                player.components.playervision:ForceNightVision(true)
                -- BUFF_DURATION天后移除效果
                player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                    if player:IsValid() and player.components.playervision then
                        player.components.playervision:ForceNightVision(false)
                    end
                end)
            end
        end
    },
    {
        name = "饥饿减缓",
        fn = function(player)
            if player.components.hunger then
                local old_rate = player.components.hunger.hungerrate
                player.components.hunger.hungerrate = old_rate * 0.5
                -- BUFF_DURATION天后移除效果
                player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                    if player:IsValid() and player.components.hunger then
                        player.components.hunger.hungerrate = old_rate
                    end
                end)
            end
        end
    },
    {
        name = "随机传送",
        fn = function(player)
            local task = player:DoPeriodicTask(30, function()
                if _G.math.random() < 0.3 then
                    -- 获取随机位置
                    local x, y, z = player.Transform:GetWorldPosition()
                    local offset = 20 -- 传送距离
                    local angle = _G.math.random() * 2 * _G.math.pi
                    local new_x = x + offset * _G.math.cos(angle)
                    local new_z = z + offset * _G.math.sin(angle)
                    
                    -- 传送玩家
                    player.Physics:Teleport(new_x, 0, new_z)
                    
                    -- 显示传送效果
                    if player.components.talker then
                        player.components.talker:Say("哇！随机传送！")
                    end
                end
            end)
            
            -- BUFF_DURATION天后移除效果
            player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                if task then task:Cancel() end
            end)
        end
    },
    {
        name = "生物朋友",
        fn = function(player)
            -- 添加标签，让生物不主动攻击
            player:AddTag("friendlycreatures")
            
            -- BUFF_DURATION天后移除效果
            player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                if player:IsValid() then
                    player:RemoveTag("friendlycreatures")
                end
            end)
        end
    },
    {
        name = "小矮人",
        fn = function(player)
            -- 保存原始体型
            local original_scale = player.Transform:GetScale()
            -- 缩小玩家
            player.Transform:SetScale(original_scale * 0.6, original_scale * 0.6, original_scale * 0.6)
            -- BUFF_DURATION天后恢复
            player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                if player:IsValid() then
                    player.Transform:SetScale(original_scale, original_scale, original_scale)
                end
            end)
        end
    },
    {
        name = "彩虹光环",
        fn = function(player)
            -- 创建光环效果
            local light = _G.SpawnPrefab("minerhatlight")
            if light then
                light.entity:SetParent(player.entity)
                light.Light:SetRadius(2)
                light.Light:SetFalloff(0.5)
                light.Light:SetIntensity(0.8)
                
                -- 彩虹颜色变化
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
                
                -- BUFF_DURATION天后移除效果
                player:DoTaskInTime(BUFF_DURATION * TUNING.TOTAL_DAY_TIME, function()
                    if color_task then color_task:Cancel() end
                    if light and light:IsValid() then
                        light:Remove()
                    end
                end)
            end
        end
    }
}

-- 安全地应用BUFF效果
local function SafeApplyBuff(player)
    if not player or not player.components then return end
    
    local buff = BUFF_LIST[_G.math.random(#BUFF_LIST)]
    if buff and buff.fn then
        local success, error_msg = _G.pcall(buff.fn, player)
        if success then
            DebugLog("成功应用BUFF:", buff.name)
            -- 显示BUFF效果提示
            if player.components.talker then
                player.components.talker:Say("获得每日惊喜: " .. buff.name)
            end
        else
            DebugLog("应用BUFF失败:", buff.name, error_msg)
        end
    end
end

-- 监听世界日期变化
AddPrefabPostInit("world", function(inst)
    if not _G.TheWorld.ismastersim then return end
    
    inst:WatchWorldState("cycles", function()
        local currentday = _G.TheWorld.state.cycles
        
        if currentday ~= lastday then
            lastday = currentday
            DebugLog("新的一天开始，应用BUFF")
            
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
            
            DebugLog("在线玩家数量:", players_count, "将选择:", select_count, "名玩家")
            
            -- 随机选择玩家
            local selected_players = {}
            while #selected_players < select_count and #players > 0 do
                local index = _G.math.random(#players)
                table.insert(selected_players, players[index])
                table.remove(players, index)
            end
            
            -- 给选中的玩家应用BUFF
            for _, player in ipairs(selected_players) do
                DebugLog("正在给玩家", player.name or "未知", "应用BUFF")
                SafeApplyBuff(player)
                
                -- 通知所有玩家谁获得了每日惊喜
                if TheNet:GetIsServer() then
                    local message = string.format("玩家 %s 获得了每日惊喜！", player.name or "未知")
                    TheNet:SystemMessage(message)
                end
            end
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
end)

-- mod加载完成提示
DebugLog("mod加载完成")