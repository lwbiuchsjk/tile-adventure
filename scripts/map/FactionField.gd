class_name FactionField
extends RefCounted
## 势力场计算工具（M2）
##
## 设计原文：
##   tile-advanture-design/持久slot地图生成设计.md §5.1 势力场函数（线性衰减 MVP）
##   tile-advanture-design/持久slot地图生成设计.md §5.2 候选选择（势力场加权随机）
##
## 核心公式（线性衰减）：
##   f_i(x) = max(0, (R - d(x, core_i)) / R)
##   d 取曼哈顿距离（与影响范围同度量）
##   值域 [0, 1]，可直接作为染色概率使用
##
## 接口设计（§5.1 末尾"优化接口预留"）：
##   后续可替换为指数衰减 / 分段函数 / Power Diagram，
##   调用方只需对接 strength_at(...) 这一入口，
##   不需要改 PersistentSlotGenerator 任何代码。

# ─────────────────────────────────────────
# 势力场强度计算
# ─────────────────────────────────────────

## 计算单个势力在指定位置的势力场强度（线性衰减）
## core_pos     —— 该势力的核心城镇坐标
## radius       —— 势力场半径 R（曼哈顿距离）
## pos          —— 待查询坐标
## 返回 [0, 1]，0 表示完全不在该势力影响下
static func strength_at(core_pos: Vector2i, radius: int, pos: Vector2i) -> float:
	if radius <= 0:
		return 0.0
	var dist: int = _manhattan(core_pos, pos)
	if dist >= radius:
		return 0.0
	return float(radius - dist) / float(radius)


## 计算所有势力在指定位置的势力场强度
## faction_cores —— Dictionary { faction_id: core_pos: Vector2i }
## radius        —— 势力场半径（MVP 全势力同 R；扩展时改为按 faction 查表）
## pos           —— 待查询坐标
## 返回 Dictionary { faction_id: strength: float }，含全部输入势力（强度可能为 0）
static func strengths_at(
	faction_cores: Dictionary,
	radius: int,
	pos: Vector2i
) -> Dictionary:
	var result: Dictionary = {}
	for faction in faction_cores:
		var fid: int = int(faction)
		var core: Vector2i = faction_cores[fid] as Vector2i
		result[fid] = strength_at(core, radius, pos)
	return result


# ─────────────────────────────────────────
# 加权随机挑选（§5.2 候选方式 b）
# ─────────────────────────────────────────

## 从候选池中按权重随机挑选一个，权重 = 该 pos 在指定势力场中的强度值
## 候选权重全为 0 时返回 Vector2i(-1, -1)（调用方据此走兜底逻辑）
##
## faction_id  —— 要为哪个势力挑选
## faction_cores / radius —— 势力场参数
## candidates  —— 候选坐标列表
## rng         —— 注入的随机数生成器（保证 seed 贯穿）
static func weighted_pick(
	faction_id: int,
	faction_cores: Dictionary,
	radius: int,
	candidates: Array[Vector2i],
	rng: RandomNumberGenerator
) -> Vector2i:
	if candidates.is_empty():
		return Vector2i(-1, -1)
	if not faction_cores.has(faction_id):
		return Vector2i(-1, -1)
	var core: Vector2i = faction_cores[faction_id] as Vector2i

	# 累积权重
	var weights: Array[float] = []
	var total: float = 0.0
	for c in candidates:
		var w: float = strength_at(core, radius, c)
		weights.append(w)
		total += w

	# 全 0 权重视为无可挑选，由调用方放宽门槛
	if total <= 0.0:
		return Vector2i(-1, -1)

	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for i in range(candidates.size()):
		acc += weights[i]
		if roll <= acc:
			return candidates[i]
	# 浮点边界保护：极端情况返回最后一个
	return candidates[candidates.size() - 1]


# ─────────────────────────────────────────
# 内部
# ─────────────────────────────────────────

## 曼哈顿距离（与游戏内"影响范围"度量保持一致）
static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
