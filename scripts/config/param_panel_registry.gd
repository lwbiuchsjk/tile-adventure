## MVP-D D.1.b：调参面板 Pull 通道中心 registry schema
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-D_CSV数值与auto-include.md
##   §变体 A registry 机制设计
##
## 用法：唯一实例 `assets/config/param_panel/_panel_registry.tres`，
##   面板控制器启动时读此 registry → 自省 entries 内每个 Resource 的 @export 字段
##   → 按 group 分场景标签页（与现有 25 ParamPanelScene Push 通道并存 + 按 Resource path 去重）
##
## 剥离原则：功能开发不感知调参面板。Resource 普通 `extends Resource` 即可，
##   纳入面板作为独立步骤——编辑本 registry 加 1 个 ParamPanelRegistryEntry 条目。
class_name ParamPanelRegistry
extends Resource


## registry 条目数组（每条对应 1 个 Resource 的纳入声明）
@export var entries: Array[ParamPanelRegistryEntry] = []
