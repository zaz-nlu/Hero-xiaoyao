extends RefCounted

# 战棋基础数值：剑意倍率。玩家方出招资源已改为能量池，见 tactics_energy.gd。

# 侧面攻击时反制强度额外 -2。
const SIDE_COUNTER_PENALTY := 2


static func jianyi_multiplier(skill: int) -> float:
	return 1.5 + float(skill) / 50.0 * 1.5
