class_name MapBaseConfig
extends Resource
## @tunable: 视觉动画
## 地图基础视觉与节奏调参（MVP-B.2 阶段 1）
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-B.2_剩余地图const扩批.md §阶段 1 字段构成
##
## 用法：使用方 `const CFG: MapBaseConfig = preload("res://assets/config/map_base_config.tres")`，
## 运行时 `CFG.field_name` 访问。编辑器内双击 .tres 在 inspector 调字段，存盘后下次启动生效。
##
## 字段从 WorldMap.gd 顶部 11 个 const 迁出（去模块前缀，snake_case），
## 跨文件共享：WorldMap.gd / WorldMapRenderer.gd / EnemyMovement.gd 三方各自独立 preload 同一份 .tres。
## 顺手收益：消除 EnemyMovement.gd:13 与 WorldMap.gd:209 双源定义 MOVE_STEP_DURATION 的隐患。


# ─────────────────────────────────────────
# 地形渲染
# 注：terrain_colors / slot_colors 的 key 为 int 对应 MapSchema.TerrainType / SlotType 枚举值
# ─────────────────────────────────────────

@export_group("地形渲染")

## 各地形渲染颜色（纯色块占位）。Civ 风格去饱和基调，让势力色独占高饱和色相。
## key：0=MOUNTAIN 冷灰褐 / 1=HIGHLAND 暖灰绿 / 2=FLATLAND 淡草绿 / 3=LOWLAND 沼泽褐
@export var terrain_colors: Dictionary = {
	0: Color(0.29, 0.25, 0.20),
	1: Color(0.72, 0.76, 0.61),
	2: Color(0.58, 0.70, 0.53),
	3: Color(0.35, 0.30, 0.23),
}

## 地形轻量明暗噪声幅度（每格基于 (x,y) 哈希给地形色加 ±N 亮度微扰，避免色块表格感）
@export_range(0.0, 0.20, 0.005) var terrain_noise_range: float = 0.04


# ─────────────────────────────────────────
# 槽位标记
# ─────────────────────────────────────────

@export_group("槽位标记")

## Slot 标记颜色（小方块叠加在地形色上；敌方/资源已有专属常量，本字典提供兜底色）
## key：1=RESOURCE 金色 / 2=FUNCTION 紫色（兜底） / 3=SPAWN 红色
@export var slot_colors: Dictionary = {
	1: Color(1.00, 0.85, 0.00),
	2: Color(0.80, 0.40, 1.00),
	3: Color(1.00, 0.30, 0.30),
}

## Slot 标记在格内的边距（像素）
@export_range(0, 36, 1) var slot_margin: int = 10


# ─────────────────────────────────────────
# 可达性高亮
# 信息层级：白色双通道全面压过势力范围（"立即操作 > 长期状态"）
# ─────────────────────────────────────────

@export_group("可达性高亮")

## 可达范围内填充色（半透明白，alpha 0.18）
@export var reachable_color: Color = Color(1.0, 1.0, 1.0, 0.18)

## 可达范围边界描边色（纯白 alpha 1.0；与势力色色相完全脱钩）
@export var reachable_border_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## 可达范围边界描边宽度（像素；3.5 略超势力范围 3.0 一档）
@export_range(0.5, 10.0, 0.1) var reachable_border_width: float = 3.5


# ─────────────────────────────────────────
# 标签字号（绑定地格视觉，随 TILE_SIZE 等比放大）
# ─────────────────────────────────────────

@export_group("标签字号")

## 地图标签字号（slot 主 ID / 文字标签）
@export_range(8, 48, 1) var label_font_size: int = 18

## 持久 slot 等级角标字号（右上角 L0/1/2/3，小字与主 ID 分离）
@export_range(6, 32, 1) var level_badge_font_size: int = 14


# ─────────────────────────────────────────
# 动效时长
# ─────────────────────────────────────────

@export_group("动效时长")

## 单位逐格移动动画耗时（秒/格）—— WorldMap 玩家单位 + EnemyMovement 敌方单位共用
@export_range(0.01, 1.0, 0.01) var move_step_duration: float = 0.1

## 醒目提示显示时长（秒）—— WorldMap._show_notice 的 default 参数
@export_range(0.5, 10.0, 0.1) var notice_duration: float = 2.5
