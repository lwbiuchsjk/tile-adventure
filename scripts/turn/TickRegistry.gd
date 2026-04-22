class_name TickRegistry
extends RefCounted
## 阵营回合 Tick 注册表（M3）
##
## 设计原文：
##   tile-advanture-design/城建锚实装/M3_回合框架与Tick.md §交付物
##   tile-advanture-design/持久slot升级建造设计.md §5.5（建造倒计时只在自己阵营回合开始 tick）
##   tile-advanture-design/敌方AI基础行为设计.md §7.1（回合开始 tick → 增援 → 升级决策 → 移动）
##
## 用途：
##   下游模块（M4 影响范围 / M5 升级建造 / M7 敌方 AI 等）把"倒计时类操作"通过
##   register() 挂进来，由 TurnManager.start_faction_turn() 在回合开始时统一触发。
##
## 并发约束：
##   tick 阶段不允许触发新 tick（避免递归）；
##   handler 内部如需修改注册表，应使用 register_pending() / unregister_pending()
##   推迟到本轮 run_ticks 结束后落定。
##
## 单例语义：
##   静态注册表（_handlers 为 static），全局共享。
##   测试场景下可用 clear_all() 重置。

## 已注册的 tick 处理函数列表
## 每个 handler 签名：func(faction: int) -> void
static var _handlers: Array[Callable] = []

## 待加入 / 待移除队列（在 run_ticks 期间被 handler 修改时延迟落定）
static var _pending_register: Array[Callable] = []
static var _pending_unregister: Array[Callable] = []

## 是否处于 run_ticks 执行中（用于检测递归 tick 与延迟应用 pending 队列）
static var _running: bool = false


# ─────────────────────────────────────────
# 注册接口
# ─────────────────────────────────────────

## 注册一个 tick handler
## handler 签名：func(faction: int) -> void
## 在 tick 执行期间调用：会延迟到本轮结束后再生效
static func register(handler: Callable) -> void:
	if _running:
		_pending_register.append(handler)
		return
	if not _handlers.has(handler):
		_handlers.append(handler)


## 注销一个 tick handler
## 在 tick 执行期间调用：会延迟到本轮结束后再生效
static func unregister(handler: Callable) -> void:
	if _running:
		_pending_unregister.append(handler)
		return
	_handlers.erase(handler)


## 触发所有已注册 handler，传入当前阵营 ID
## 严禁递归：handler 内部调用本方法将触发 push_error 并跳过
## 由 TurnManager.start_faction_turn() 在回合开始最先调用（先于 turn_started 信号）
##
## 异常恢复（M3 P1#5）：
##   - 遍历前快照 _handlers，避免 handler 内 register/unregister 影响当前轮
##   - GDScript 4 无 try/finally，但 Callable.call() 抛错只 push_error 不中断 caller，
##     for 循环可继续执行剩余 handler
##   - 极端 fatal 场景（脚本 crash）下若 _running 残留，调用方可用 reset_running_state() 强制复位
static func run_ticks(faction: int) -> void:
	if _running:
		push_error("TickRegistry: 检测到递归 tick，已跳过")
		return
	_running = true
	# 快照遍历：handler 内 register/unregister 走 pending 队列，本轮不影响迭代
	var snapshot: Array[Callable] = _handlers.duplicate()
	for h in snapshot:
		# 单个 handler 失败仅影响自身调用，不阻断后续 tick
		if h.is_valid():
			h.call(faction)
	_running = false
	_apply_pending()


## 紧急复位：清理 _running 标记 + pending 队列，不动已注册 handlers
## 用途：handler 触发 fatal 错误后下一回合无法 tick 时手动调用
## 测试场景下 clear_all() 已涵盖此功能；运行时极少需要
static func reset_running_state() -> void:
	if _running or not _pending_register.is_empty() or not _pending_unregister.is_empty():
		push_warning("TickRegistry: 强制复位运行态（_running=%s, pending_reg=%d, pending_unreg=%d）" % [
			str(_running), _pending_register.size(), _pending_unregister.size()
		])
	_running = false
	_pending_register.clear()
	_pending_unregister.clear()


## 当前已注册 handler 数量（测试 / 调试用）
static func handler_count() -> int:
	return _handlers.size()


## 清空所有已注册 handler（仅测试场景使用）
## 同时清空 pending 队列，避免下次 register 时被误恢复
static func clear_all() -> void:
	_handlers.clear()
	_pending_register.clear()
	_pending_unregister.clear()
	_running = false


# ─────────────────────────────────────────
# 内部
# ─────────────────────────────────────────

## 落地本轮 run_ticks 期间累积的 register / unregister 请求
## 注：先应用 unregister 再 register，避免"同一 handler 先 unregister 又 register"被吞
static func _apply_pending() -> void:
	if not _pending_unregister.is_empty():
		for h in _pending_unregister:
			_handlers.erase(h)
		_pending_unregister.clear()
	if not _pending_register.is_empty():
		for h in _pending_register:
			if not _handlers.has(h):
				_handlers.append(h)
		_pending_register.clear()
