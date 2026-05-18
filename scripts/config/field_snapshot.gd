class_name FieldSnapshot
extends Resource
## MVP-C.2 阶段 2 preset 单字段快照：记录某 Resource 字段在特定时刻的 value
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-C_运行时调参面板.md §7 preset Schema
##
## 用法：作 ParamPreset.field_snapshots 数组元素；每个 FieldSnapshot 描述 preset 内一个字段快照。
## apply preset 时按 (target_resource_path + field_name + dict_key) 定位字段写回 preload 实例。

## 目标 Resource .tres 路径（如 "res://assets/config/influence_config.tres"）
@export_file("*.tres") var target_resource_path: String = ""

## Resource 内字段名（snake_case，如 "faction_colors" / "vision_radius_grids"）
@export var field_name: String = ""

## Dict 字段的 key（null = 直接访问字段；非 null = 访问 field_name[dict_key]）
## 示例：field_name="faction_colors" + dict_key=1 → faction_colors[1]
@export var dict_key: Variant = null

## 字段值（Color / float / int / String / Vector2 / bool 等任意 Variant）
## apply 时按 dict_key 是否为 null 决定直接 set 或 Dict 索引赋值
@export var value: Variant = null
