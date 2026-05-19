## MVP-D D.1.b：调参面板 Pull 通道单条目 schema
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-D_CSV数值与auto-include.md
##   §变体 A registry 机制设计
##
## 每个 entry 描述「让某个 Resource 进面板」+「以什么形式进」（group 归类 / skip 字段 / realtime 标志 / redraw 目标）
class_name ParamPanelRegistryEntry
extends Resource


## Resource .tres 文件路径（如 "res://assets/config/battle_param_resource.tres"）
## 必填；面板启动时 load 此路径取实例并自省 @export 字段
@export_file("*.tres") var tres_path: String = ""

## 面板分组名（场景标签页归属，与现有 ParamPanelScene.category 同语义）
## 必填；首次出现的 group 自动创建对应 TreeNode 大类
@export var group: StringName = &""

## 不进面板的字段名列表（如内部数据键 / 索引 / 枚举占位字段）
## 空数组 = 所有 @export 字段都进面板
@export var skip_fields: PackedStringArray = PackedStringArray()

## 实时调参标志：
##   false（默认）= 调完 F2 写盘 + 重启 Godot 生效（const preload 路径下值类型字段有 cache bug）
##                  面板在字段旁标 "⚠ 重启生效"
##   true = 字段实时生效；**要求开发者把该 Resource 在所有使用方的 const preload 改为 var preload**
##          否则 cache bug 仍触发，调参后视觉不更新
## 详见设计文档 §const Resource cache bug 已知限制
@export var realtime: bool = false

## 字段调参后需主动触发刷新的节点路径列表（NodePath，相对 SceneTree.root）
## 用于 NightVisionLayer 等非 CanvasItem 节点或需自定义 refresh 方法的节点
## 空数组 = 仅依赖 Resource @export 反射 set 后的自然生效（CanvasItem 自动 queue_redraw）
@export var redraw_targets: Array[NodePath] = []
