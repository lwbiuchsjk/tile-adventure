class_name UnitEnemyConfig
extends Resource
## 单位渲染 + 敌方关卡视觉调参（MVP-B.2 阶段 2）
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-B.2_剩余地图const扩批.md §阶段 2 字段构成
##
## 用法：使用方 `const CFG: UnitEnemyConfig = preload("res://assets/config/unit_enemy_config.tres")`，
## 运行时 `CFG.field_name` 访问。编辑器内双击 .tres 在 inspector 调字段，存盘后下次启动生效。
##
## 字段从 WorldMap.gd 顶部 15 个 const 迁出，跨文件共享 WorldMap.gd / WorldMapRenderer.gd 两方独立 preload。
## 命名约定：unit_ 前缀 = 玩家方圆形棋子；enemy_ 前缀 = 敌方关卡 slot；tier_ 前缀 = 敌方层级专属（已隐含 enemy 语义）。


# ─────────────────────────────────────────
# 玩家方单位渲染（圆形棋子）
# ─────────────────────────────────────────

@export_group("玩家方单位渲染")

## 单位标记内底色（白色，承载"我"字 + 在地形上保留对比度）
@export var unit_color: Color = Color(1.0, 1.0, 1.0)

## 单位投影色（圆形棋子的半透黑投影）
## 形状区分（圆 vs 方/菱）+ 玩家蓝身份语义双管齐下，避免被白色可达边吞没
@export var unit_shadow_color: Color = Color(0.0, 0.0, 0.0, 0.30)

## 单位标记边距（像素）—— 圆形半径 = (TILE_SIZE - unit_margin*2) / 2
## 入口 4 MVP：8 → 12 保持半径占比 0.667 不变
@export_range(0, 36, 1) var unit_margin: int = 12

## 玩家单位外环厚度（px）—— 环色复用 InfluenceConfig.faction_colors[PLAYER]，保证 UI 一致
## 环宽 3 略薄于建筑 4，因为单位整体小一档（半径 16 vs 建筑半边长 24）
@export_range(1, 10, 1) var unit_player_ring_width: int = 3


# ─────────────────────────────────────────
# 已挑战变暗
# ─────────────────────────────────────────

@export_group("已挑战变暗")

## 已挑战关卡变暗系数（同一轮内已挑战但尚未切换的敌方 slot）
@export_range(0.0, 1.0, 0.05) var challenged_dim: float = 0.4


# ─────────────────────────────────────────
# 敌方关卡底色与边框（兜底）
# ─────────────────────────────────────────

@export_group("敌方关卡底色与边框")

## 敌方关卡底色 —— 统一为标准敌方红（与持久敌方建筑势力色同源）
## 沿革（5 版迭代）：
##   v1 暗红 #CC4040 + tier 跨色相边框（绿/黄/红/紫）
##   v2 饱和冷红 #FF3D4D + tier 红色家族边框 —— 中档描边色与底色相同消失（致命 bug）
##   v3 (R-Bold) 底色按 tier 明度梯度 + 主字"弱/中/强/超" —— 文字 14px 小空间糊
##   v4 米字小菱形 + 尺寸梯度 —— 但底色 4 档梯度让"超档黑红"被白小菱形覆盖出现反语义
##   v5 (当前) 底色统一 #FF3D4D —— 强度完全靠 3 个独立直觉通道（尺寸 + 小菱形数 + 描边宽度）
##                                 与持久敌方建筑共享"敌方"身份红
@export var enemy_slot_color: Color = Color(1.00, 0.24, 0.30)

## 敌方关卡边框颜色（兜底，仅 level.tier 越界时使用）
@export var enemy_border_color: Color = Color(1.0, 0.25, 0.20, 0.8)


# ─────────────────────────────────────────
# 敌方层级（Tier）视觉
# tier 0 弱：上 1 个小菱形 / tier 1 中：上+下 2 个 / tier 2 强：上+左+右 3 个 / tier 3 超：4 个全亮
# ─────────────────────────────────────────

@export_group("敌方层级 Tier 视觉")

## 敌方菱形描边色（统一黑红 #1A0008，与红底高对比；宽度按 tier 梯度）
@export var tier_border_color: Color = Color(0.10, 0.00, 0.03, 1.0)

## 敌方菱形描边宽度（按 tier 梯度 2.0/2.5/3.0/3.5；v4 的 4.5 过粗压迫小菱形）
## key 对应 tier int（0=弱 / 1=中 / 2=强 / 3=超）
@export var tier_border_widths: Dictionary = {
	0: 2.0,
	1: 2.5,
	2: 3.0,
	3: 3.5,
}

## 敌方层级小菱形配色（金色 #FFD700，与玩家/敌方核心金边同源；"金 = 重要标识"）
@export var tier_dot_color: Color = Color(1.0, 0.84, 0.0)

## 敌方层级小菱形尺寸比例（外菱形的 0.3 倍居中分布；底色 70%+ 区域可见）
@export_range(0.05, 1.0, 0.01) var tier_dot_size_ratio: float = 0.3

## 敌方外菱形按 tier 的格内边距（像素）—— 尺寸梯度通道
## 占格比例：弱 67% / 中 75% / 强 83% / 超 92%（key 对应 tier int）
## 入口 4 MVP（codex 审查 P2 修复 2026-05-09）：TILE_SIZE 48→72 后按比例重算 margin
@export var tier_slot_margins: Dictionary = {
	0: 12,
	1: 9,
	2: 6,
	3: 3,
}


# ─────────────────────────────────────────
# 敌方动态（移动 / 光晕）
# ─────────────────────────────────────────

@export_group("敌方动态")

## 敌方关卡移动时的高亮颜色（亮红橙）
@export var enemy_move_color: Color = Color(1.0, 0.35, 0.20)

## 敌方关卡移动时的外圈光晕颜色
@export var enemy_glow_color: Color = Color(1.0, 0.30, 0.15, 0.35)
