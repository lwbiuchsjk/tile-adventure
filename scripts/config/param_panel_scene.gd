class_name ParamPanelScene
extends Resource
## MVP-C.1 调参面板单场景：按「调参场景」组织字段（跨 Resource 聚合）
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-C_运行时调参面板.md §5 场景目录 / §6 数据流架构
##
## 用法：每个 .tres 实例代表面板内 1 个场景（共 25 场景）；
##   存放路径 `assets/config/param_panel/<scene_id>.tres`。
##   面板控制器启动时扫描该目录，按 category 大类 → scene 二级 TreeNode 渲染。
##
## 字段映射 fields 数组按"调参频次 + 视觉强度"排序，UI 渲染顺序与数组顺序一致；
## 连续相同 group_name 字段会自动用 ImGui.SeparatorText 分隔成块。


## 场景内部 ID（snake_case，如 "player_visual" / "enemy_tier_visual"）
## 必须与 .tres 文件名一致，preset 子目录用同一标识：`assets/config/presets/<scene_id>/`
@export var scene_id: String = ""

## 面板内显示的中文场景名（如「玩家方视觉」「敌方层级 Tier 4 档视觉」）
@export var display_name: String = ""

## 所属大类（与设计文档 §5.A 8 大类对齐，决定 TreeNode 一级分组）
## 取值：身份与势力 / 地图基底 / 操作反馈 / 敌方表达 / 持久slot与影响圈 / 战斗视觉 / 战斗动画 / 夜晚UI节奏
@export var category: String = ""

## 场景级默认 redraw 目标节点名字数组（80% 字段继承此项；少数特殊字段用 ParamFieldMapping.redraw_targets_override 覆盖）
## 空数组 = 场景内所有字段默认 passive（适合战斗动画时长这种被动生效场景）
@export var default_redraw_targets: Array[String] = []

## 字段映射列表（顺序决定 UI 渲染顺序）
@export var fields: Array[ParamFieldMapping] = []
