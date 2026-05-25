class_name ScoreCalculator
extends RefCounted
## 单局评分计算器
## 基于扎营次数和累计损兵量计算单局评分。
## 乘法结构：基础分 × 效率系数 × 存活系数。
## 两个维度互相对抗：龟缩（多扎营少损兵）和莽穿（少扎营多损兵）都会被惩罚。

## 计算单局评分
## camp_count: 扎营次数
## total_hp_lost: 累计损失兵力（不可逆，恢复不扣回）
## total_max_hp: 所有角色部队的 max_hp 总和
## config: ScoreParamResource（MVP-D D.2 批 2：迁自 score_config.csv）
## 返回 {score: int, efficiency: float, survival: float}
static func calculate(camp_count: int, total_hp_lost: int, total_max_hp: int, config: ScoreParamResource) -> Dictionary:
	var base: float = config.base_score
	var k1: float = config.efficiency_k
	var k2: float = config.survival_k

	# 效率系数：反比衰减，扎营次数等于 K₁ 时为 0.5
	var efficiency: float = k1 / (k1 + float(camp_count))

	# 存活系数：线性惩罚，总损兵占比越高越低
	var hp_loss_rate: float = float(total_hp_lost) / maxf(float(total_max_hp), 1.0)
	var survival: float = maxf(0.0, 1.0 - hp_loss_rate * k2)

	var score: float = base * efficiency * survival

	return {"score": int(score), "efficiency": efficiency, "survival": survival}
