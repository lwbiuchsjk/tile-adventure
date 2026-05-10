class_name UIFadeHelper
extends RefCounted
##
## UI 渐隐工具集（入口 2 MVP 2.2 共用层 / 2026-05-11）
##
## 多个 UI 子系统（EventPanelUI / ManageUI / 未来 BuildPanelUI / VictoryUI 等）共享一致的
## fade in 视觉语言；常量与 Tween 启动逻辑集中在此处，确保各 UI 表现统一。
##
## 调用方约定（推荐使用模式）：
##   _is_fading_in = true
##   _fade_tween = UIFadeHelper.fade_in(_root, UIFadeHelper.DEFAULT_FADE_IN_DURATION,
##       func() -> void: _is_fading_in = false)
##
## 调用方自行管理 _is_fading_in flag（因为各 UI 的"输入屏蔽"守卫逻辑各异：
## EventPanel 全输入屏蔽 / ManageUI 仅 close 路径屏蔽 等）。
##

## 默认 fade in 时长（与 OverlayTransitionUI fade in / fade out 同步）
## 调参集中在此处;后续美术节奏调整时改这里
const DEFAULT_FADE_IN_DURATION: float = 0.4


## 启动 fade in Tween：root.modulate.a 0 → 1
##
## 参数：
##   root      — 要 fade 的 Control 节点（modulate 沿层级穿透，子节点跟着淡入）
##               必须 inside_tree（create_tween 要求）
##   duration  — 时长（秒），默认 DEFAULT_FADE_IN_DURATION
##   on_done   — Tween 完成回调（可选）；典型用法 = `func() -> void: _is_fading_in = false`
##
## 返回：
##   Tween 实例 —— caller 可保存以便后续 kill（如打开新事件 / 关闭面板时 kill 旧 tween）
##   root == null 或不 inside_tree 时返回 null（不抛错，做防御性 noop）
##
## 内部:
##   - 立即设 root.modulate.a = 0.0(起点透明)
##   - 用 root.create_tween()(tween 绑定 root，root 销毁时 tween 自动 kill)
##   - 仅 modulate.a，不影响 modulate 其他通道
static func fade_in(root: Control, duration: float = DEFAULT_FADE_IN_DURATION, on_done: Callable = Callable()) -> Tween:
	if root == null:
		return null
	if not root.is_inside_tree():
		push_warning("UIFadeHelper.fade_in: root 未 inside_tree，跳过")
		return null
	root.modulate.a = 0.0
	var tween: Tween = root.create_tween()
	tween.tween_property(root, "modulate:a", 1.0, duration)
	if on_done.is_valid():
		tween.finished.connect(on_done)
	return tween
