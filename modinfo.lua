name = "每日惊喜"
description = "每天给玩家一个随机的惊喜效果"
author = "Va6gn"
version = "1.0.0"

-- 游戏兼容性
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false

-- 客户端/服务器兼容性
client_only_mod = false
all_clients_require_mod = true

-- mod图标
icon_atlas = "modicon.xml"
icon = "modicon.tex"

-- mod配置选项
configuration_options = {
    {
        name = "buff_duration",
        label = "BUFF持续时间",
        hover = "BUFF效果持续多少天",
        options = {
            {description = "半天", data = 0.5},
            {description = "1天", data = 1},
            {description = "2天", data = 2}
        },
        default = 1
    },
    {
        name = "random_players_count",
        label = "随机选择玩家数量",
        options = {
            {description = "1人", data = 1},
            {description = "2人", data = 2},
            {description = "3人", data = 3},
            {description = "4人", data = 4},
            {description = "5人", data = 5},
            {description = "所有人", data = 999}
        },
        default = 1
    }
}