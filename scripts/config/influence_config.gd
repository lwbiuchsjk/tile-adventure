class_name InfluenceConfig
extends Resource
## @tunable: 视觉动画
## 势力 + 影响圈 + 持久 slot 三层结构调参（MVP-B.2 阶段 4）
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-B.2_剩余地图const扩批.md §阶段 4 字段构成
##
## 用法：使用方 `const CFG: InfluenceConfig = preload("res://assets/config/influence_config.tres")`，
## 运行时 `CFG.field_name` 访问。编辑器内双击 .tres 在 inspector 调字段，存盘后下次启动生效。
##
## 字段从 WorldMap.gd 顶部 12 个 M4_* const 迁出，跨 WorldMap.gd / WorldMapRenderer.gd 两方共享。
## 命名约定：去 M4_ 前缀（同 Resource 名已隐含），保留 influence_ / persistent_ / core_town_ 对象前缀做语义分组。


# ─────────────────────────────────────────
# 势力色（持久 slot 外框 + 影响范围覆盖层共用）
# Civ 化阶段 A：饱和青蓝玩家 + 饱和冷红敌方，与去饱和地形形成强对比
# ─────────────────────────────────────────

@export_group("势力色")

## 势力归属色字典（key = Faction 枚举 int）
## key：0=NONE 中立灰 / 1=PLAYER 饱和青蓝 #1A8FE6 / 2=ENEMY_1 饱和冷红 #FF3D4D
## 设计原则：饱和度 ≥ 0.76 与去饱和地形拉开明度 60+，规避撞色
@export var faction_colors: Dictionary = {
	0: Color(0.55, 0.55, 0.55),
	1: Color(0.10, 0.56, 0.90),
	2: Color(1.00, 0.24, 0.30),
}


# ─────────────────────────────────────────
# 影响范围覆盖层 alpha（半透明，分层渐变营造"势力辐射"感）
# 公式：d_to_edge = r - (|dx| + |dy|)
# 外圈（d=0）OUTER → 次外（d=1）MID → 内层（d≥2）INNER
# ─────────────────────────────────────────

@export_group("影响圈三圈 alpha")

## 最外圈格 alpha —— 辐射感"亮边"
@export_range(0.0, 1.0, 0.01) var influence_alpha_outer: float = 0.22

## 次外圈格 alpha —— 过渡
@export_range(0.0, 1.0, 0.01) var influence_alpha_mid: float = 0.12

## 内圈格 alpha —— 极淡，让据点本体居于中心
@export_range(0.0, 1.0, 0.01) var influence_alpha_inner: float = 0.05


# ─────────────────────────────────────────
# 影响圈菱形外边界描边（势力合集化 —— 每势力一条独立轮廓，相邻同势力 slot 重叠处形成双线）
# 沿革：v1 纯色 alpha 0.55 → v2 暗化 × 0.4 + alpha 0.70 → v3（当前）势力原色 alpha 1.0 + 宽 3.0
# 地形改沼泽褐 / 暖灰绿且去饱和后，势力色原色站在地形上反而最跳，无须再暗化
# ─────────────────────────────────────────

@export_group("影响圈描边")

## 影响圈描边 alpha（势力原色 alpha 1.0）
@export_range(0.0, 1.0, 0.01) var influence_border_alpha: float = 1.0

## 影响圈描边宽度（像素）
@export_range(0.5, 10.0, 0.1) var influence_border_width: float = 3.0


# ─────────────────────────────────────────
# 核心城镇金色描边（凸显势力首都）
# ─────────────────────────────────────────

@export_group("核心城镇金边")

## 核心城镇金色描边色
@export var core_town_border: Color = Color(1.0, 0.85, 0.0)

## 核心城镇下方徽记（金色小菱形）边长（像素）
@export_range(2, 24, 1) var core_town_emblem_size: int = 8

## 敌方核心强凸显（核心目标传达_MVP §2.2 / H3）—— 敌方 owned 核心是唯一胜利目标，需最醒目
## 比常规 core_town_border（2px）更粗的金边 + 外发光晕
@export var enemy_core_border_color: Color = Color(1.0, 0.84, 0.0)
@export_range(1.0, 8.0, 0.5) var enemy_core_border_width: float = 4.0
@export var enemy_core_glow_color: Color = Color(1.0, 0.84, 0.0, 0.30)
@export_range(0.0, 24.0, 1.0) var enemy_core_glow_radius: float = 10.0


# ─────────────────────────────────────────
# 持久 slot 三层结构（UI 重构步骤 1 + 调色迭代）
# 外环势力色（归属识别）→ 白色分离线（几何分离，即使色相冲突也能识别）→ 内底米白（文字承载）
# 三层而非双层的理由：当玩家蓝 / 敌方红与地形色相近时，仅靠势力色 + 米白内底仍可能低对比度
# ─────────────────────────────────────────

@export_group("持久 slot 三层结构")

## 外环厚度（像素，占格 48 × 8%）
@export_range(1, 12, 1) var persistent_ring_width: int = 4

## 分离线颜色（纯白）
@export var persistent_separator_color: Color = Color(1.0, 1.0, 1.0)

## 分离线厚度（像素）
@export_range(1, 6, 1) var persistent_separator_width: int = 1

## 内底色（米白 #E6E0D4，承载文字）
@export var persistent_inner_bg: Color = Color(0.90, 0.88, 0.83)


# ─────────────────────────────────────────
# 持久 slot 援军条带（持久slot援军_MVP / L1.2）
# 玩家方 slot 援军未耗尽时底部画"援军"条带；耗尽（roster 空）→ 条带消失
# 条带底色不在此配——复用 BattleVisualConfig.reinforcement_fill_color（与战场援军绿单一来源、"绿=援军"统一）
# ─────────────────────────────────────────

@export_group("持久 slot 援军条带")

## 条带高度（像素）
@export_range(6, 32, 1) var reinforcement_band_height: int = 16

## 条带"援军"文字颜色（白，叠在援军绿底上高对比）
@export var reinforcement_band_text_color: Color = Color(1.0, 1.0, 1.0)

## 条带文字字号（像素）—— 小于主名称 label_font_size，避免溢出
@export_range(6, 24, 1) var reinforcement_band_font_size: int = 12
