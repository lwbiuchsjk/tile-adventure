class_name ParamFieldMapping
extends Resource
## MVP-C.1 调参面板单字段映射：声明面板控件 ↔ 实际 Resource 字段的对应关系
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-C_运行时调参面板.md §6 数据流架构 / Schema 定义
##
## 用法：作 ParamPanelScene.fields 数组元素；每个 ParamFieldMapping 描述面板内一个调参控件。
## 面板控制器按本对象的 control_type 分发到 ImGui.SliderFloat / ColorEdit3 等 binding。
##
## 字段更改触发链：
##   1. 用户改控件 → ImGui binding 写回 Array[float]
##   2. 面板控制器读 Array → 按 control_type + dict_key 写回 preload 实例属性
##   3. 帧末 defer：按 effective_redraw_targets（场景级 default + 字段级 override）合并去重触发 redraw
##   4. Ctrl+S：ResourceSaver.save 写回原 .tres


## 面板控件标签文字（中文，UI 显示用）
@export var display_label: String = ""

## 字段分组名（连续相同 group_name 自动插入 ImGui.SeparatorText 分隔；空 = 不分组）
@export var group_name: String = ""


# ─────────────────────────────────────────
# Resource 字段定位
# ─────────────────────────────────────────

## 目标 Resource .tres 路径（如 "res://assets/config/influence_config.tres"）
@export_file("*.tres") var target_resource_path: String = ""

## Resource 内字段名（snake_case，如 "faction_colors" / "vision_radius_grids"）
@export var field_name: String = ""

## Dict 字段的 key（null = 直接访问字段；非 null = 访问 field_name[dict_key]）
## 示例：field_name="faction_colors" + dict_key=1 → faction_colors[1]
## 示例：field_name="terrain_colors" + dict_key="mountain" → terrain_colors["mountain"]
@export var dict_key: Variant = null


# ─────────────────────────────────────────
# 控件类型与范围
# ─────────────────────────────────────────

## 控件类型："ColorEdit3" / "ColorEdit4" / "SliderFloat" / "SliderInt"
## MVP-C.2 扩展："Combo" / "InputText"
@export_enum("ColorEdit3", "ColorEdit4", "SliderFloat", "SliderInt") var control_type: String = "SliderFloat"

## Slider 下限（仅 SliderFloat / SliderInt 用；未填则后续可查 Resource schema 的 @export_range）
@export var slider_min: float = 0.0

## Slider 上限
@export var slider_max: float = 1.0


# ─────────────────────────────────────────
# Redraw 配置
# ─────────────────────────────────────────

## 字段级 redraw 目标节点名字数组（空 = 用 ParamPanelScene.default_redraw_targets；非空 = 覆盖）
## 节点名字数组：运行时 SceneTree.root.find_child(name, true, false) 查找
@export var redraw_targets_override: Array[String] = []

## 被动生效字段标记：true = 不触发任何 redraw（与 redraw_targets 互斥）
## 用于动画时长、Camera tween 等下次触发时才生效的字段
@export var passive: bool = false


# ─────────────────────────────────────────
# UX 辅助
# ─────────────────────────────────────────

## hover tooltip 文字（中文，鼠标停留时显示；空 = 无 tooltip）
@export_multiline var tooltip: String = ""
