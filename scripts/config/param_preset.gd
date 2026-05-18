class_name ParamPreset
extends Resource
## MVP-C.2 阶段 2 preset：一个场景的配色 / 数值 / 时长 等字段值组合
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-C_运行时调参面板.md §7 preset 系统设计
##
## 用法：
##   - 存放路径 `assets/config/presets/<scene_id>/<filename>.tres`
##   - scene_id 必须与所在子目录一致（启动校验）
##   - display_name 是 UI 显示名（与文件名解耦，重命名只改 display_name 保 git history 友好）
##
## 加载 / 切换流程：详 ParamPanelController.apply_preset / load_preset_from_disk

## UI 显示名（如「玩家蓝 v6」），重命名只改此字段，文件名不动
@export var display_name: String = ""

## 所属场景 ID（如 "player_visual"），必须与所在子目录名一致
@export var scene_id: String = ""

## 字段值快照列表（apply 时逐项写回 preload 实例）
@export var field_snapshots: Array[FieldSnapshot] = []

## 美术 / 设计的备注（可选）
@export_multiline var note: String = ""

## 运行时字段（**不持久化** —— 无 @export）：load_preset_from_disk 加载时回填磁盘路径
## 用途：避免 cache 内坏 preset 跳过时 _preset_path_for 用 "cache[i] → paths[i]" 索引反推错位
## Codex 审查 MVP-C.2 P1.1 修复（2026-05-18）
var _source_path: String = ""
