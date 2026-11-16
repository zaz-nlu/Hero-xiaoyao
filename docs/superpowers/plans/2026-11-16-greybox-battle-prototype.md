# 灰盒战斗原型 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Godot 4 里做出可无界面运行的战斗核心，加一个灰盒界面，让任逍遥（单人）打紫霞镇马匪小怪和 boss 马友为，验证"读招 → 反制 → 破势 → 剑意"循环。

**Architecture:** 战斗规则全部是不依赖场景树的纯 GDScript 类（`godot/core/`），数据放在 JSON（`godot/data/`），界面只是调用 `Battle` 的薄壳。同一套核心既能被灰盒界面使用，也能被命令行模拟器批量调用。

**Tech Stack:** Godot 4.x 标准版（非 .NET），GDScript，自写的极简测试运行器，JSON 数据。

**Spec:** `docs/superpowers/specs/2026-11-16-battle-growth-design.md`（本计划实现其第 9 节"第一个里程碑"）

## Global Constraints

- 引擎 Godot 4 标准版，GDScript；战斗逻辑与画面分离，能用 `--headless` 运行；数据驱动，改数值不改代码。
- 所有 `godot/core/` 脚本之间用 `preload("res://core/xxx.gd")` 引用，**不用 `class_name`**（headless 下全局类缓存要先导入，容易失败）。
- 现有 Web 项目（`src/`、`package.json` 等）不修改，Godot 工程放在 `godot/`。
- 出招 6 类，初期不再增加：重劈 / 突刺 / 横扫 / 连击 / 蓄力 / 飞射（代码 id：`heavy` `thrust` `sweep` `combo` `charge` `ranged`）。
- 每个敌人出招类型数：小怪 1 到 2 类，精英和 boss 3 到 4 类。
- 耐性是次数：普通怪 2，精英 3 到 5，反派约 8。普通反制扣 1，完美破招扣 2，⚠ 勉强扣一半（0.5）。
- 完美破招：武学对准敌人弱点（出招在敌人 `weak_moves` 里），且武学优势属性等于玩家六维最高项（并列都算）。
- 晕眩（即"破势"）：敌人不行动、防御归零、我方攻击必暴击、敌人恢复暂停；持续 1 个敌方回合，反派 2 个；结束后耐性重置。
- 剑意：无视防御，必须能命中实体，伤害记为不可愈合的伤（wound）；开局 1 点；戳破弱点（ADVANTAGE 或完美破招）后恢复 1 点；不扣耐性、不影响其他计数。
- 熟练度：按角色按武学计算，0 级 = 未学会，到 1 级即学会，10 级封顶，每级基础伤害 +4%（满级 +40%）。
- 主动栏 4 个，每栏一门已学会的武学。
- 速度决定行动顺序；明雷主动攻击则第一轮我方先手。
- 六维：`power`（力量）`speed`（速度）`defense`（防御）`recovery`（恢复）`skill`（技巧）`mechanism`（机制）。
- 测试命令（PowerShell，`$env:GODOT` 指向 Godot 的 console 版 exe）：`& $env:GODOT --headless --path godot -s res://tests/run_tests.gd`

## Review Focus

1. 玩家剑意点为 0 时选择剑意：被拒绝，不消耗回合、不扣点（Task 6 测试）。
2. 选的目标已死亡或已晕眩（晕眩的敌人没有意图可反制）：被拒绝或按规则处理，不崩溃（Task 7 测试）。
3. 治疗上限：`hp` 恢复不能超过 `max_hp - wound`；wound 超过 max_hp 时单位死亡（Task 4 测试）。
4. 玩家选择未学会（0 级）的武学：被拒绝（Task 7 测试）。
5. boss 恢复力强到玩家打不动：战斗到 `Balance.MAX_ROUNDS` 判 TIMEOUT，模拟器不会死循环（Task 7、Task 10 测试）。

---

### Task 0: 工程骨架与测试运行器

**Files:**
- Create: `godot/project.godot`, `godot/.gitignore`（内容 `.godot/`）
- Create: `godot/tests/test_case.gd`, `godot/tests/run_tests.gd`, `godot/tests/test_sanity.gd`

**Interfaces:**
- Produces: `test_case.gd`（基类，`extends RefCounted`）提供 `assert_eq(actual, expected, msg := "")`、`assert_true(cond, msg := "")`、`assert_near(a: float, b: float, eps := 0.0001, msg := "")`，失败写入 `failures: Array[String]`。
- Produces: `run_tests.gd`（`extends SceneTree`）扫描 `res://tests/test_*.gd`，对每个脚本新建实例并调用所有名字以 `test_` 开头的方法，打印每条 PASS/FAIL 和汇总行 `PASS n / FAIL m`，有失败则 `quit(1)`，否则 `quit(0)`。

- [ ] **Step 1: 手动步骤（需要用户）**：安装 Godot 4.x 标准版，把 `Godot_v4.x-stable_win64_console.exe` 的完整路径设为环境变量 `GODOT`。验证：`& $env:GODOT --version` 输出以 `4.` 开头。
- [ ] **Step 2: 写 `project.godot`（config_version=5，应用名 "任逍遥"）、`test_case.gd`、`run_tests.gd`，和一个故意失败的 `test_sanity.gd`**：`func test_runner_detects_failure(): assert_eq(1 + 1, 3)`
- [ ] **Step 3: 运行测试命令，预期**：输出 `FAIL`，汇总 `PASS 0 / FAIL 1`，退出码 1。
- [ ] **Step 4: 把 sanity 测试改成 `assert_eq(1 + 1, 2)`，并加 `test_assert_near`：`assert_near(0.1 + 0.2, 0.3)`**
- [ ] **Step 5: 运行测试命令，预期** `PASS 2 / FAIL 0`，退出码 0。
- [ ] **Step 6: Commit** `git add godot && git commit -m "feat: godot project skeleton and test runner"`

---

### Task 1: 数据模型与加载校验

**Files:**
- Create: `godot/core/move_types.gd`, `godot/core/stats.gd`, `godot/core/martial_def.gd`, `godot/core/enemy_def.gd`, `godot/core/data_loader.gd`
- Test: `godot/tests/test_data_loader.gd`

**Interfaces:**
- Produces: `MoveTypes.ALL: Array[String]`（6 个 id）、`MoveTypes.NAMES: Dictionary`（id → 中文名）。
- Produces: `Stats.KEYS: Array[String]`；`Stats.top_keys(stats: Dictionary) -> Array[String]`（返回所有并列最高的键）。
- Produces: `MartialDef`：字段 `id, name: String`、`power: int`、`counters: Array[String]`、`initiative: int`、`counter_level: int`、`advantage_stat: String`、`effects: Array`（元素 `{kind: String, value: float}`）；`static func from_dict(d: Dictionary) -> MartialDef`。
- Produces: `EnemyDef`：字段 `id, name, tier`（`"minion"|"elite"|"boss"`）、`stats: Dictionary`、`max_hp: int`、`toughness: int`、`stun_turns: int`、`moves: Array`（元素 `{id, name, type, threat: int, power: int}`）、`weak_moves: Array[String]`、`incorporeal: bool`；`static func from_dict(d: Dictionary) -> EnemyDef`。
- Produces: `DataLoader.parse_martials(json_text: String) -> Dictionary` 与 `DataLoader.parse_enemies(json_text: String) -> Dictionary`，都返回 `{"defs": Dictionary（id → def）, "errors": Array[String]}`。
- 校验规则：武学 `counters` 必须是 `MoveTypes.ALL` 的子集且 1 到 3 个、`advantage_stat` 必须在 `Stats.KEYS` 里；敌人出招类型数小怪 1 到 2、精英和 boss 3 到 4；`weak_moves` 必须是该敌人的某个 move id。错误信息要包含出错的 id。

- [ ] **Step 1: 写失败测试**（内联 JSON 字符串即可）
  - `test_valid_martial_loads`：一个合法武学，`errors.size() == 0`，`defs["a"].counters == ["heavy"]`
  - `test_martial_with_unknown_type_is_error`：`counters: ["fire"]`，错误里含 `"fire"`
  - `test_minion_with_three_types_is_error`：小怪有 3 种 type，错误里含该敌人 id
  - `test_boss_with_two_types_is_error`
  - `test_weak_move_must_exist`
  - `test_top_keys_returns_all_ties`：`Stats.top_keys({power:10, speed:10, defense:5, recovery:5, skill:5, mechanism:5}) == ["power","speed"]`
- [ ] **Step 2: 运行测试，预期失败**（preload 的文件不存在）
- [ ] **Step 3: 实现上述类与校验**
- [ ] **Step 4: 运行测试，预期** 全部 PASS
- [ ] **Step 5: Commit** `feat: data model and loader validation`

---

### Task 2: 熟练度

**Files:**
- Create: `godot/core/mastery.gd`, `godot/core/balance.gd`
- Test: `godot/tests/test_mastery.gd`

**Interfaces:**
- Produces: `Balance` 常量（以后调数值都改这里）：`CRIT_MULT := 1.5`、`JIANYI_BASE := 30`、`REGEN_PER_RECOVERY := 2`、`LEVEL_BONUS := 0.04`、`MAX_ROUNDS := 200`、`MAX_LEVEL := 10`。
- Produces: `Mastery`（`extends RefCounted`）：`exp_to_reach(level: int) -> int`（静态，= `5 * level * (level + 1) / 2`）、`level(id: String) -> int`（0 到 10）、`add_exp(id: String, amount: int) -> void`、`learn(id: String) -> void`（经验设为恰好 1 级所需）、`damage_multiplier(id: String) -> float`（= `1.0 + LEVEL_BONUS * level`）。

- [ ] **Step 1: 写失败测试**
  - `test_unlearned_is_level_zero`：新建后 `level("a") == 0`
  - `test_learn_gives_level_one`：`learn("a")` 后 `level("a") == 1`
  - `test_exp_thresholds`：`add_exp("a", 14)` → 1 级；再 `add_exp("a", 1)`（共 15）→ 2 级
  - `test_level_caps_at_ten`：`add_exp("a", 99999)` → `level == 10`
  - `test_multiplier`：`learn` 后乘数 1.04；10 级时 1.4（用 `assert_near`）；0 级时 1.0
- [ ] **Step 2: 运行，预期失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行，预期** 全部 PASS
- [ ] **Step 5: Commit** `feat: mastery levels`

---

### Task 3: 反制判定

**Files:**
- Create: `godot/core/counter.gd`
- Test: `godot/tests/test_counter.gd`

**Interfaces:**
- Consumes: `MartialDef`、`Stats.top_keys`。
- Produces: `Counter.Verdict` 枚举 `{IMPOSSIBLE = 0, BARELY = 1, ADVANTAGE = 2}`（对应 ❌ ⚠ ✅）。
- Produces: `Counter.evaluate(martial: MartialDef, user_stats: Dictionary, enemy_speed: int, move: Dictionary, first_strike: bool) -> int`，规则：
  - 出招类型不在 `martial.counters` → IMPOSSIBLE
  - `counter_power = user_stats.skill + martial.counter_level + clampi(floori((user_stats.speed - enemy_speed) / 5.0), -3, 3)`，`gap = counter_power - move.threat`；`gap < -5` → IMPOSSIBLE
  - `fast = first_strike or (user_stats.speed + martial.initiative >= enemy_speed)`；`fast and gap >= 0` → ADVANTAGE，其余 → BARELY
- Produces: `Counter.is_perfect(verdict: int, martial: MartialDef, user_stats: Dictionary, weak_moves: Array, move_id: String) -> bool`（verdict 为 ADVANTAGE 且 `move_id in weak_moves` 且 `martial.advantage_stat in Stats.top_keys(user_stats)`）。
- Produces: `Counter.toughness_cost(verdict: int, perfect: bool) -> float`（IMPOSSIBLE 0.0，BARELY 0.5，ADVANTAGE 1.0，完美 2.0）。

- [ ] **Step 1: 写失败测试**（辅助函数造一个 `MartialDef`：counters `["heavy"]`、`counter_level 5`、`initiative 0`、`advantage_stat "skill"`；玩家 `{skill:20, speed:15, ...}`；出招 `{id:"m1", type:"heavy", threat:20}`）
  - `test_type_mismatch_is_impossible`
  - `test_fast_and_strong_enough_is_advantage`：敌速 10 → ADVANTAGE
  - `test_slower_than_enemy_is_barely`：敌速 30（速度差修正 -3，`counter_power = 22`，gap 2 ≥ 0，但 `15 + 0 < 30`）→ BARELY
  - `test_first_strike_makes_slow_fast`：同上加 `first_strike = true` → ADVANTAGE
  - `test_threat_far_above_power_is_impossible`：`threat 40` → IMPOSSIBLE
  - `test_perfect_needs_weak_move_and_top_stat`：`weak_moves = ["m1"]` 且 top stat 是 skill → true；`advantage_stat` 换成 `"power"` → false；`weak_moves = []` → false
  - `test_perfect_counts_ties`：玩家全 10，`advantage_stat "power"` → true
  - `test_toughness_cost_values`：四种取值
- [ ] **Step 2: 运行，预期失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行，预期** 全部 PASS
- [ ] **Step 5: Commit** `feat: counter verdict and perfect counter`

---

### Task 4: 单位、伤害与不可愈合的伤

**Files:**
- Create: `godot/core/unit.gd`, `godot/core/damage.gd`
- Test: `godot/tests/test_unit.gd`

**Interfaces:**
- Consumes: `EnemyDef`、`Balance`。
- Produces: `Unit`（`extends RefCounted`）字段：`id, name: String`、`is_player: bool`、`stats: Dictionary`、`max_hp, hp, wound: int`、`toughness_max: int`、`toughness_left: float`、`stun_turns, stun_left: int`、`jianyi_max, jianyi_points: int`、`weak_moves: Array`、`weak_revealed: bool`、`def: EnemyDef`（玩家为 null）、`incorporeal: bool`。
- Produces: `static func Unit.make_player(name: String, stats: Dictionary, max_hp: int, jianyi_max: int) -> Unit`（`jianyi_points = jianyi_max`）；`static func Unit.from_enemy(d: EnemyDef) -> Unit`。
- Produces: `heal(amount: int) -> int`（hp 不超过 `max_hp - wound`，返回实际恢复量）、`take_damage(amount: int) -> void`、`take_wound(amount: int) -> void`（同时降 hp 并增加 wound）、`is_dead() -> bool`（`hp <= 0`）、`is_stunned() -> bool`（`stun_left > 0`）。
- Produces: `Damage.hit(martial_power: int, multiplier: float, attacker_stats: Dictionary, defender: Unit) -> int`：`raw = martial_power * multiplier + attacker_stats.power`；defender 晕眩时防御按 0 且 `raw` 乘 `Balance.CRIT_MULT`；结果 `max(1, floori(raw) - defense)`；会对 defender 调 `take_damage` 并返回伤害值。

- [ ] **Step 1: 写失败测试**
  - `test_heal_capped_by_wound`：`hp 50, max_hp 100, wound 30`，`heal(100)` → hp 70，返回 20
  - `test_wound_lowers_hp_and_cap`：`take_wound(10)` 后 `hp` 少 10、`wound == 10`
  - `test_wound_can_kill`：`max_hp 10`，`take_wound(10)` → `is_dead()`
  - `test_damage_subtracts_defense`：力量 5、武学威力 10、乘数 1.0、防御 3 → 伤害 12
  - `test_damage_minimum_one`：防御 99 → 伤害 1
  - `test_stunned_target_takes_crit_with_zero_defense`：同上数值，目标 `stun_left = 1` → floor(15 × 1.5) − 0 = 22
- [ ] **Step 2: 运行，预期失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行，预期** 全部 PASS
- [ ] **Step 5: Commit** `feat: unit, damage, unhealable wound`

---

### Task 5: 耐性与破势（晕眩）

**Files:**
- Modify: `godot/core/unit.gd`
- Test: `godot/tests/test_toughness.gd`

**Interfaces:**
- Consumes: `Unit`。
- Produces: `Unit.apply_toughness(cost: float) -> bool`：已晕眩则忽略并返回 false；否则 `toughness_left -= cost`，≤ 0 时 `stun_left = stun_turns`、返回 true（多出的不结转）。
- Produces: `Unit.tick_stun() -> void`：晕眩中则 `stun_left -= 1`，减到 0 时 `toughness_left = float(toughness_max)`。
- Produces: `Unit.probe() -> void`：`weak_revealed = true`。

- [ ] **Step 1: 写失败测试**（小怪：`toughness_max 2, stun_turns 1`）
  - `test_two_normal_counters_stun_minion`：`apply_toughness(1.0)` 返回 false，再一次返回 true，`is_stunned()`
  - `test_barely_counters_need_four`：`apply_toughness(0.5)` 三次都 false，第四次 true
  - `test_perfect_stuns_minion_at_once`：`apply_toughness(2.0)` → true
  - `test_overflow_not_carried`：晕眩结束后 `toughness_left == 2.0`
  - `test_toughness_ignored_while_stunned`
  - `test_boss_stun_lasts_two_turns`：`stun_turns 2`，`tick_stun()` 一次仍晕眩，两次后不晕眩且耐性重置
  - `test_probe_reveals_weak_moves`
- [ ] **Step 2: 运行，预期失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行，预期** 全部 PASS
- [ ] **Step 5: Commit** `feat: toughness and stun`

---

### Task 6: 剑意

**Files:**
- Create: `godot/core/jianyi.gd`
- Test: `godot/tests/test_jianyi.gd`

**Interfaces:**
- Consumes: `Unit`、`Balance.JIANYI_BASE`。
- Produces: `Jianyi.can_strike(attacker: Unit, target: Unit) -> bool`：`attacker.jianyi_points > 0` 且 `not target.incorporeal` 且 `not target.is_dead()`。
- Produces: `Jianyi.strike(attacker: Unit, target: Unit) -> int`：不满足 `can_strike` 返回 -1（不扣点、不改任何状态）；否则 `damage = Balance.JIANYI_BASE + attacker.stats.skill`，无视防御，调 `target.take_wound(damage)`，`jianyi_points -= 1`，返回 damage。
- Produces: `Jianyi.restore(attacker: Unit) -> void`：`jianyi_points` 加 1，不超过 `jianyi_max`。

- [ ] **Step 1: 写失败测试**（玩家 `skill 20, jianyi_max 1`；敌人 `defense 50, max_hp 200`）
  - `test_strike_ignores_defense_and_wounds`：返回 50，敌人 `wound == 50`，玩家 `jianyi_points == 0`
  - `test_strike_with_zero_points_is_refused`：第二次返回 -1，敌人 hp 不变，点数仍为 0（Review Focus 1）
  - `test_strike_on_incorporeal_refused_without_cost`：点数不变
  - `test_restore_capped_by_max`：`restore` 两次后点数为 1
  - `test_wound_blocks_healing`：打一次后 `heal(999)` 只能恢复到 `max_hp - 50`
- [ ] **Step 2: 运行，预期失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行，预期** 全部 PASS
- [ ] **Step 5: Commit** `feat: jianyi`

---

### Task 7: 战斗回合骨架

**Files:**
- Create: `godot/core/enemy_ai.gd`, `godot/core/battle.gd`
- Test: `godot/tests/test_battle.gd`

**Interfaces:**
- Consumes: `Unit`、`MartialDef`、`Mastery`、`Damage`、`Jianyi`、`Balance`。
- Produces: `EnemyAi.choose(moves: Array, rng: RandomNumberGenerator) -> Dictionary`（从 moves 里随机选一个）。
- Produces: `Battle`（`extends RefCounted`）：`_init(player: Unit, enemies: Array, loadout: Array[String], mastery: Mastery, martials: Dictionary, seed: int, first_strike: bool)`。
- 公开字段：`round: int`（从 1 开始）、`intents: Array`（与 `enemies` 同序，元素是 move Dictionary；晕眩或已死亡的敌人为 `{}`）、`log: Array[String]`、`enemies: Array`。
- 公开方法：`begin_round() -> void`（为每个存活且未晕眩的敌人用 `EnemyAi.choose` 声明意图）；`submit(action: Dictionary) -> Dictionary`，action 形如 `{kind: "martial", id: String, target: int}`、`{kind: "jianyi", target: int}`、`{kind: "probe", target: int}`，返回 `{ok: bool, error: String}`，不合法时 `ok=false` 且不推进回合；合法则结算整个回合（见下），随后自动 `round += 1` 并 `begin_round()`；`state() -> int`，枚举 `Battle.State {ONGOING, WON, LOST, TIMEOUT}`。
- 合法性：`martial` 的 id 必须在 `loadout` 里且 `mastery.level(id) >= 1`；目标下标有效且目标未死亡；`jianyi` 要 `Jianyi.can_strike`。
- 结算顺序：我方和所有存活且未晕眩的敌人按 `stats.speed` 降序，速度相同玩家在前；`first_strike` 且 `round == 1` 时玩家排最前。玩家步骤：`martial` 对目标造成 `Damage.hit(martial.power, mastery.damage_multiplier(id), player.stats, target)`；`jianyi` 调 `Jianyi.strike`；`probe` 调 `target.probe()`。敌人步骤：若敌人晕眩则 `tick_stun()` 并跳过；否则恢复 `recovery * Balance.REGEN_PER_RECOVERY`（`heal`），再对玩家造成其意图 `power` 减玩家防御（至少 1）的伤害（反制在 Task 8 接入）。
- 结束：全部敌人死亡 → WON；玩家死亡 → LOST；`round > Balance.MAX_ROUNDS` → TIMEOUT。

- [ ] **Step 1: 写失败测试**（辅助函数造玩家 `speed 15`、两个敌人 `speed 10/20`、一个已学会的武学）
  - `test_intents_declared_for_living_enemies`：`begin_round` 后 `intents.size() == enemies.size()`，每个非空
  - `test_order_by_speed_player_first_on_tie`：敌速 15 时玩家先出手（从 log 顺序断言）
  - `test_first_strike_round_one_player_acts_first`：敌速 30、`first_strike = true`，第 1 回合玩家先；第 2 回合敌人先
  - `test_submit_rejects_unlearned_martial`：`mastery.level == 0` → `ok == false`（Review Focus 4）
  - `test_submit_rejects_dead_target`（Review Focus 2）
  - `test_martial_damages_target`
  - `test_win_when_all_enemies_dead` 与 `test_lose_when_player_dead`
  - `test_timeout_on_stalemate`：敌人恢复远高于玩家伤害，调 `Balance.MAX_ROUNDS` 次后 `state() == TIMEOUT`（可在测试里临时用小的回合上限，由 `Battle` 读取 `Balance.MAX_ROUNDS`）（Review Focus 5）
  - `test_stunned_enemy_does_not_regen_or_act`
- [ ] **Step 2: 运行，预期失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行，预期** 全部 PASS
- [ ] **Step 5: Commit** `feat: battle round skeleton`

---

### Task 8: 战斗里接入反制、破势、剑意、熟练度

**Files:**
- Modify: `godot/core/battle.gd`
- Test: `godot/tests/test_battle_counter.gd`

**Interfaces:**
- Consumes: `Counter`、`Unit.apply_toughness`、`Jianyi.restore`、`Mastery.add_exp`。
- Produces: `Battle.preview(martial_id: String, target: int) -> int`：返回 `Counter.Verdict`（对目标当前意图），供界面显示 ✅⚠❌；目标没有意图时返回 `IMPOSSIBLE`。
- 敌人步骤改为：若玩家本回合选了武学且目标是该敌人，则用 `Counter.evaluate(...)` 求 verdict（`first_strike` 传 `first_strike and round == 1`）。
  - 完美破招（`Counter.is_perfect`）：玩家不受伤；再对敌人造成一次该武学的 `Damage.hit`。
  - ADVANTAGE：玩家不受伤。BARELY：玩家受一半伤害。IMPOSSIBLE：玩家受全额伤害。
  - 非 IMPOSSIBLE 时 `target.apply_toughness(Counter.toughness_cost(...))`；verdict 为 ADVANTAGE（含完美）时 `Jianyi.restore(player)`。
  - 武学 `effects` 里 `kind == "reflect"`：成功反制（ADVANTAGE 或完美）时对敌人额外造成 `incoming_damage * value`（`incoming_damage` 为该敌人这一招对玩家按未反制算出的伤害）。
  - 熟练度：使用武学 `mastery.add_exp(id, 1)`；非 IMPOSSIBLE 再 `add_exp(id, 2)`。
- 反制成功时日志要写出 verdict、扣的耐性、是否触发晕眩。

- [ ] **Step 1: 写失败测试**
  - `test_advantage_counter_negates_damage_and_costs_one_toughness`：小怪耐性 2 → `toughness_left == 1.0`，玩家 hp 不变
  - `test_two_counters_stun_enemy_and_next_round_it_skips`：第二回合该敌人 `is_stunned()` 且 `intents[i] == {}`，玩家对它的攻击按暴击且防御为 0 结算
  - `test_barely_counter_half_damage_half_toughness`
  - `test_impossible_takes_full_damage`
  - `test_perfect_counter_costs_two_and_counterattacks`
  - `test_advantage_counter_restores_jianyi`：先用 `jianyi` 使点数为 0，反制成功后回 1
  - `test_barely_counter_does_not_restore_jianyi`
  - `test_reflect_effect_returns_damage`：`reflect 0.3`
  - `test_mastery_exp_gained`：使用武学 +1，反制成功共 +3
  - `test_preview_matches_resolution`：`preview` 的 verdict 与实际结算一致
- [ ] **Step 2: 运行，预期失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行全部测试，预期** 全部 PASS
- [ ] **Step 5: Commit** `feat: counter resolution in battle`

---

### Task 9: 真实内容数据

**Files:**
- Create: `godot/data/martials.json`, `godot/data/enemies.json`, `godot/data/player.json`
- Test: `godot/tests/test_content.gd`

**Interfaces:**
- Consumes: `DataLoader`。
- 以下数值是起点，之后靠 Task 10 的模拟来调，不是 spec 规定值（spec 规定值已在 Global Constraints）。

武学（10 门，6 类出招每类至少有一门能反制）：

| id | 名称 | 威力 | 反制 | 先手加成 | 破招等级 | 优势属性 | 特效 |
|---|---|---|---|---|---|---|---|
| basic_sword | 基础剑术 | 10 | thrust | 0 | 2 | skill | |
| parry | 格挡 | 4 | sweep, combo | 0 | 3 | defense | |
| sidestep | 闪身 | 3 | charge, ranged | 5 | 3 | speed | |
| taiji | 太极缠劲 | 5 | heavy | 0 | 4 | recovery | reflect 0.3 |
| qingyun | 青云剑法 | 12 | thrust | 2 | 4 | skill | |
| huifeng | 回风剑 | 9 | sweep | 2 | 4 | speed | |
| lianhuan | 连环快剑 | 8 | combo | 6 | 3 | speed | |
| duanshi | 断势一击 | 14 | charge | 0 | 4 | power | |
| liuxing | 流星诀 | 8 | ranged | 4 | 4 | skill | |
| jueshi | 绝世剑术 | 18 | thrust, combo | 3 | 7 | skill | |

敌人：

| id | 名称 | tier | 速度 | 防御 | 恢复 | 耐性 | 晕眩回合 | HP | 出招（类型:威胁） | 弱点出招 |
|---|---|---|---|---|---|---|---|---|---|---|
| bandit | 马匪 | minion | 8 | 3 | 1 | 2 | 1 | 40 | sweep:12, heavy:14 | |
| ma_youwei | 马友为 | boss | 12 | 8 | 6 | 8 | 2 | 300 | heavy:18（开山）, sweep:14（乱刀横扫）, thrust:16（刺喉） | 开山 |

玩家任逍遥（剑客路线，spec 第 7.2 节）：`power 10, speed 15, defense 5, recovery 5, skill 20, mechanism 5`，HP 100，剑意上限 1，默认主动栏 `["basic_sword","parry","sidestep","taiji"]`，默认熟练度：上述四门已学会（1 级）。

- [ ] **Step 1: 写失败测试**
  - `test_content_loads_without_errors`：三个 JSON 都能加载、`errors.size() == 0`
  - `test_martial_count_between_8_and_10`
  - `test_every_move_type_has_a_counter_martial`
  - `test_boss_has_3_or_4_types_and_toughness_8`；`test_bandit_has_1_or_2_types_and_toughness_2`
  - `test_default_loadout_has_four_learned_martials`
  - `test_player_route_totals_sixty`：六维合计 60
- [ ] **Step 2: 运行，预期失败**（数据文件不存在）
- [ ] **Step 3: 按上表写 JSON**
- [ ] **Step 4: 运行，预期** 全部 PASS
- [ ] **Step 5: Commit** `feat: prototype content data`

---

### Task 10: 命令行批量模拟

**Files:**
- Create: `godot/core/simulator.gd`, `godot/tools/simulate.gd`
- Test: `godot/tests/test_simulator.gd`

**Interfaces:**
- Consumes: `Battle`、`DataLoader`、`Unit`、`Mastery`。
- Produces: `Simulator.run(config: Dictionary) -> Dictionary`，`config`：`{enemy_id: String, enemy_count: int, loadout: Array[String], battles: int, seed: int, bot: String, first_strike: bool}`，`bot` 取 `"random"`（随机选合法行动）或 `"smart"`（目标意图类型被已带武学覆盖则选能反制的武学；剑意点可用且目标未晕眩时优先用剑意；否则选威力最高的武学）。返回 `{wins, losses, timeouts: int, avg_rounds: float, win_rate: float}`。
- Produces: `tools/simulate.gd`（`extends SceneTree`）：读取命令行参数，调用 `Simulator.run`，打印一行汇总。
- 同一个 `seed` 必须得到相同结果。

- [ ] **Step 1: 写失败测试**
  - `test_same_seed_same_result`
  - `test_counts_add_up`：`wins + losses + timeouts == battles`
  - `test_smart_bot_beats_minions_often`：`bandit`、`smart`、50 场，`win_rate >= 0.8`
  - `test_stalemate_reports_timeout_not_hang`：用一个恢复极高的临时敌人（测试内构造）→ `timeouts > 0`（Review Focus 5）
- [ ] **Step 2: 运行，预期失败**
- [ ] **Step 3: 实现**
- [ ] **Step 4: 运行测试，预期** 全部 PASS
- [ ] **Step 5: 运行模拟看数值**：`& $env:GODOT --headless --path godot -s res://tools/simulate.gd -- --enemy=ma_youwei --bot=smart --battles=500 --seed=1`，把 `smart` 与 `random` 在 boss 上的胜率和平均回合数记在提交信息里
- [ ] **Step 6: Commit** `feat: headless battle simulator`

---

### Task 11: 灰盒界面

**Files:**
- Create: `godot/ui/battle_view.tscn`, `godot/ui/battle_view.gd`
- Modify: `godot/project.godot`（主场景设为 `res://ui/battle_view.tscn`）
- Test: `godot/tests/test_battle_view.gd`

**Interfaces:**
- Consumes: `Battle`（含 `preview`）、`DataLoader`、真实数据。
- Produces: `battle_view.gd`：`start(enemy_id: String, enemy_count: int, first_strike: bool) -> void`；`press_action(action: Dictionary) -> void`（界面按钮调用的同一入口，便于测试）；只用文字和方块：我方生命条与 wound、每个敌人的名字、生命条、耐性、本回合意图（出招名与类型中文名）、4 个武学按钮（带 ✅ ⚠ ❌ 标记，来自 `preview`）、剑意按钮（显示剩余点数）、试探按钮、滚动战斗日志；敌人 `weak_revealed` 后显示其弱点出招。
- 战斗结束时显示"胜利 / 战败 / 僵局"和重新开始按钮。

- [ ] **Step 1: 写失败测试**：`test_view_starts_and_shows_intent`（实例化场景，`start("bandit", 1, true)`，断言意图标签文字包含出招中文名）；`test_press_action_advances_round`（`press_action({kind:"martial", id:"basic_sword", target:0})` 后 `round == 2`，日志非空）
- [ ] **Step 2: 运行，预期失败**
- [ ] **Step 3: 实现场景与脚本**
- [ ] **Step 4: 运行全部测试，预期** 全部 PASS
- [ ] **Step 5: 手动试玩（需要用户）**：`& $env:GODOT --path godot` 打开游戏，打一场马匪、一场马友为，确认：意图可读、✅⚠❌ 与结果一致、晕眩后敌人不还手、剑意用完后戳破弱点能回 1 点。把手感问题记下来，作为调数值和之后做画面的输入
- [ ] **Step 6: Commit** `feat: greybox battle ui`

---

## Self-Review

- **Spec 覆盖（第 9 节里程碑）**：6 类出招（Task 1、9）、8 到 10 个武学（Task 9）、剑意循环（Task 6、8）、破势/晕眩（Task 5、8）、熟练度（Task 2、8）、可无界面模拟（Task 10）、验收"打完小怪战和 boss 战"（Task 11 手动、Task 10 模拟）。明雷先手（Task 7 的 `first_strike`）。队友结构预留：`Battle` 接收单个 `player: Unit`，多人扩展留给后续，不在本计划。
- **有意不在本计划里**：装备学习武学、转流派、反应栏、被动栏、世界展开与觉醒值、内力与冷却、紫霞带队的教学战、剧情演出、画面与动画、观察/试探之外的情报系统。
- **类型一致性**：`Counter.Verdict`（Task 3）在 Task 8 的 `preview` 和结算里使用；`Unit.apply_toughness` / `tick_stun`（Task 5）在 Task 7、8 里调用；`Jianyi.can_strike` / `strike` / `restore`（Task 6）在 Task 7、8、10 里调用；`Balance.MAX_ROUNDS` 由 Task 2 定义。
- **比例**：计划约为 spec 的 1.5 倍，代码块只有签名和断言，没有函数体。
