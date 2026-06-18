# 项目说明

## 项目概述
- 这是一款游戏demo，需要基于最小原型来推进。对于有价值有潜力的功能，需要明确提出，并记录下来，以供扩展。
- 这是一个游戏demo，游戏体验类似英雄无敌，有大地图探索、运营，有部队、英雄的养成、战斗。

## 技术栈
Godot 4.6，GDScript，Git 版本控制

## 项目结构

- scripts/      脚本文件
- assets/       资源文件（图片、音效等）
- test/         测试文件
- tile-advanture-design/        设计文档 Git submodule（远端私有仓库）。新增文档放在这里。其中 `attachments/` 存放图片等大文件，被 `.gitignore` 忽略不入 git，通过坚果云完整同步保证多端可用。
- _kb_sync/     在线知识库同步工具目录（访问规则见共享 CLAUDE.md）
- _kb_sync/images/              飞书文档中下载的图片缓存（需在 kb.local.json 中设置 `cache.downloadImages: true`）

## 路径指定

- 项目环境配置集中在 `tools/local_env.json`（模板见 `tools/local_env.example.json`，本机配置不入 git）。
- 设计文档目录对应 `design_dir` 字段，本项目固定为 `tile-advanture-design`。
- 新增文档应当放在 `tile-advanture-design/` 下。

## Obsidian CLI

- 路径和 vault 名称配置在 `tools/local_env.json`。
- 使用前读取该文件获取 `obsidian_cli` 和 `vault_name`。若当前环境为 WSL（`uname -r` 含 `microsoft`），需用 `wslpath -u` 将 Windows 路径转换为 WSL 路径。
- 示例：`"<obsidian_cli>" backlinks vault=<vault_name> file="文档名"`

### 优先使用 Obsidian CLI 的场景

操作 `tile-advanture-design/` 下的 md 文档时，以下场景**优先使用 Obsidian CLI** 而非 Glob/Grep/Read（需 Obsidian 运行中；未运行时回退到 Grep）：

1. **链接关系查询**：`backlinks`（反向链接）、`links`（正向链接）、`orphans`（孤立文件）、`deadends`（终端文件）、`unresolved`（断链）。能识别所有 `[[]]` 链接形式包括别名链接，Grep 无法可靠替代。
2. **属性与标签查询/修改**：`tags`（标签列表与过滤）、`properties`（属性列表）、`property:read` / `property:set`（读写属性）。直接操作 YAML frontmatter，比手动解析更可靠。
3. **文档结构概览**：`outline`（标题层级树）。输出结构化层级信息，比 Grep 搜 `^#+` 更清晰。

### 设计目录文档操作规范

- **查询文档**时，优先读取 [[_MOC]] 定位目标，不直接 Glob 扫描根目录。
- **新增文档**后，必须在 `_MOC.md` 对应分区添加索引行。
- **删除或重命名文档**后，同步更新 `_MOC.md`（删除条目 / 修改链接）。
- 文档从根目录**移入子目录**时，更新 `_MOC.md` 中的分区说明。

### 文档删除与重命名规范

删除或重命名 `tile-advanture-design/` 下的文档前，**必须先用 `backlinks` 检查引用关系**，避免产生断链。Obsidian 未运行时可用 Grep 搜索 `[[文档名]]` 作为备选（可能漏掉别名链接）。

1. 如果存在引用，先更新引用方文档，再执行删除或重命名。
2. 重命名文档优先使用 Obsidian CLI 的 `move` 命令，它会自动更新所有 `[[]]` 链接。

### 新增设计文档规范

在 `tile-advanture-design/` 下新增设计文档后，必须检查并更新相关文档的双向链接（使用 Obsidian CLI `backlinks` 辅助定位）。

**frontmatter 必填**：新建 `.md` 必须按 [[标签体系]] 填写 YAML frontmatter。格式 `tags: [类型/xxx, 模块/xxx, 状态/xxx]`，其中**类型和状态各一个**、**模块可多个**，所有值必须在 `标签体系.md` 白名单内（pre-commit hook 自动校验）。文档状态变化（草案→MVP→已落地→已归档）时同步更新 `状态/` 标签。

# 工作规范

## 讨论与决策

**结构性决策先给 2-3 候选方案**：涉及多文档改动 / 命名 / 拆分粒度 / 文档归属等结构性决策，先提 2-3 候选 + 倾向项 + tradeoff 让用户拍板，不要单选方案直接执行。此模式也适用于一般问题讨论：对比选项比独自推演更快收敛、返工更少。

## 设计 → 实装的文档组织

本项目把"将要做什么 → 怎么做 → 怎么发包 → 谁负责"切成 4 层 + 1 个横向议题库；分层避免不同抽象层的内容混在同一文档。

### 文档分工矩阵

| 层级 | 文档类型 | 性质 | 触发动作 | 入口 |
|---|---|---|---|---|
| **L0 路线图层** | **开发路线图** | 已认可的开发方向总览（多入口集中管理） | 用户提出新方向 + 双方讨论确认后新增条目 | [[开发路线图]] |
| **L1 设计层** | MVP 设计文档 | 单入口拆出的具体设计（设计自洽性 / agent 可读性） | 路线图入口讨论清楚后拆出 | [[MVP设计文档规范]] |
| **L2 实装层** | 八字段实装包 | 大型 MVP 多模块发包模板（实装任务发包 / 模块切分） | 大改动 + 跨模块时拆出（小改动直接落地，不必切） | 模板示例：[[城建锚实装/M1_基础数据层]] |
| **L3 待办层** | 待跟踪事项索引 | P0-P3 已认可的具体待办（与某具体设计文档强绑定） | 实装/跑测发现可立即落项的小议题 | [[待跟踪事项索引]] |
| **横向** | **设计候选库** | 零散议题 / 灵感 / 暂搁置方向（不一定走实装通道） | 不经讨论的开放性想法 | [[设计候选库]] |

### 文档间链路

```
[L0 路线图] → 入口讨论清楚 → [L1 MVP 设计] → 大改动？ → [L2 八字段实装包] → 代码
                                ↓                            ↑
                       小改动直接落地代码          [L3 待跟踪 P0-P3] 实装/跑测落项
                                ↓
                                ↓ ←横向议题入库  [横向 设计候选库]
```

- **L1 → L2**：八字段的"需求来源"字段锚到 L1；L1 的"引擎改动清单"为 L2 的"实现路径提示"提供素材
- **L1 → L3**：L1 设计文档中的"备注 / 后续关注 / 暂搁置 / 扩展备忘"按 P0-P3 入 L3
- **L0 ↔ 设计候选库**：开放性议题先进设计候选库；议题状态明确化（双方认可"准备做"）后升级到 L0 入口
- **L0 → L1**：路线图入口讨论清楚后拆出 1 份或多份 L1 MVP 设计文档（颗粒度依入口而定）

### 文档生命周期

- **L0 路线图入口**：⏳ 待讨论 / 🔧 拆 MVP 中 / ✅ 已落地（迁出至「已归档路线」段）
- **L1 MVP 设计文档**：状态/草案 → 状态/MVP → 状态/已落地（按 [[标签体系]]）
- **进度文档**（在 `tile-advanture-design/进度/`）：跟踪某条推进线（可能跨多个 L0 入口的一个 / 多个 MVP），完成后 frontmatter 状态/已归档 + 索引行从 CLAUDE.md「活跃」迁到「已归档」

### 实装任务包的八字段模板

大型 MVP 跨模块发包时，每个模块文档按八字段组织：目标 / 需求来源（锚到设计文档，不展开原文）/ 范围（覆盖·不覆盖两列）/ 前置依赖 / 交付物（文件路径 + 关键签名）/ 实现路径提示（`scripts/xxx.gd:LN` + 改动顺序）/ 验收标准（checkbox）/ 不在本模块解决（引用《待跟踪索引》分工）。完整模板见 [[城建锚实装/M1_基础数据层]]。

### 跨文档待跟踪事项索引

设计文档的"备注 / 后续关注 / 暂搁置 / 扩展备忘"统一汇总到 `待跟踪事项索引.md`，按 P0 待补 / P1 实现阶段决策 / P2 暂搁置 / P3 扩展备忘 四级分类（定义见该文件头）。条目归档时整条移除（git blame 追溯）。

## 代码调整与 Codex 协作

"主会话设计 + Codex 实装"模式（MVP-α 验证有效）。**机械型改动优先委派 Codex**（机械精确删除 / 大量改动 + grep 可清零 / 边界明确无需语义判断；省 token + 跨模型独立审视）；**风险敏感 / 精细 / Edit 复用度高的小批量主会话自己做**。委派走 `codex:codex-rescue` 子代理。

**Codex prompt 必备字段**（缺则漂移）：① 任务背景 + 设计文档锚点；② 任务范围（编号到 §x.y，不写"按设计文档做"）；③ 强制约束块——绝对禁止任何 git 操作 / 范围严格限定 / section divider 顶格不缩进 / 以函数名+grep 为准不死扣行号；④ 验收标准（grep 清零 + headless parse + 测试套件）；⑤ 返回报告格式（完成度/grep/parse/意外发现/遗留）；⑥ 模型="最新 GPT 模型"。

**委派后核实序列**：`git diff --stat` → 关键文件 diff 比对设计逐项 → grep 清零（分活代码/注释残留）→ 查 Codex 副作用（缩进/残留/类型占位）→ 补主会话该补的 → headless parse → 测试套件回归。

**漏列项透明处理**：设计文档漏列的补做，commit message 显式标注来源（"Codex 补找" / "主会话补做（设计漏列）"）。不偷偷扩范围，审计可追溯是底线。

---

## 分步验证提交

大 MVP 拆"独立可回滚阶段"：每阶段一 commit、可独立 `revert`、阶段边界在设计文档预先明示、revert 后系统仍可运行。

**每阶段 4 步验证链**（任一失败暂停修复后重跑）：① grep 清零（活代码清零，注释残留留下阶段）→ ② headless parse（见 `[WorldMap] 自动 seed`）→ ③ 测试套件回归（无 regression）→ ④ 桌面跑测（GUI/视觉/交互，用户做）。

验证链 1-3 过 → 主会话主动 commit（托管或明示时）。Commit message：改动清单（按 §x.y）/ 工作流回顾（Codex 委派·主会话补做）/ 验证状态 / 影响面分类 / `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。

**push 时机**：纯删除/注释/配置 + headless 过 → 可立即 push；涉及核心状态机 / GUI / fade·Tween·时序敏感 → commit 后等桌面验证再 push（未 push 可 `reset --hard HEAD~1` 撤回，已 push 需 `revert`）。

## 测试与 Godot 调用

扩展共享 CLAUDE.md「测试流程」节，给出本项目具体的跑测命令。Godot 可执行路径硬编码在 `tools/run_godot.ps1` 内（`E:\Godot\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe`），对应 WSL 路径 `/mnt/e/Godot/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe`。

### 1. 桌面 / 编辑器场景

用户在 Windows 端跑：
```powershell
tools/run_godot.ps1 [godot 参数...]
```

### 2. WSL headless / agent 委派场景

agent 不能调用 `.ps1`（bash 解析失败 / `powershell.exe` 在 WSL 下 `interop socket 错误`），需要**直接调用 Windows .exe** + **传 Windows 风格路径**给 `--path`：

```bash
GODOT_EXE="/mnt/e/Godot/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe"

# headless parse 验证（启动到 _ready 检查 GDScript 编译 + 初始化）
"$GODOT_EXE" --headless --path "E:\Godot\project\tile-adventure" --quit

# 跑单个测试套件
"$GODOT_EXE" --headless --path "E:\Godot\project\tile-adventure" -s "test/test_mX.gd"
```

**关键约束**：
- `--path` 必须传 **Windows 路径**（`E:\Godot\project\tile-adventure`），不是 Linux 路径（`/mnt/e/...`）—— Godot.exe 不识别 mount 路径
- WSL 下走 `interop socket 错误` 时，**不要试 `powershell.exe -File ...`**，直接调 .exe 是稳定路径

### 3. headless parse 通过判据

启动后 stdout 出现 `[WorldMap] 自动 seed = NNNN` 即代表 parse + `_ready` 跑通；`WARNING: ObjectDB instances leaked at exit` 是退出时的资源释放警告，与本次改动无关，可忽略。

### 4. 测试套件

`test/` 下若干 `extends SceneTree` 套件（独立可跑）：M1-M8（数据层 / 地图生成 / 回合框架 / 占据 / 建造 / 产出 / 敌方 AI / 胜负判定，城建锚阶段遗留命名）+ RunState + NarrativeProvider。逐个清单以 test/ 目录实际文件为准。DayNightState / OverlayTransitionUI 等依赖帧驱动 / SceneTree 难独立测，留 P3。

### 5. 跑测命令模板（验证链 4 步使用）

```bash
# 步骤 2: Headless parse
"$GODOT_EXE" --headless --path "E:\Godot\project\tile-adventure" --quit 2>&1 | tail -5

# 步骤 3: 测试套件回归（M1-M8 + ε 新增 2 份，一次循环）
for t in test_m1_data_layer test_m2_map_gen test_m3_turn_framework test_m4_occupation \
         test_m5_build test_m6_production test_m7_enemy_ai test_m8_victory_judge \
         test_run_state test_narrative_provider; do
  RESULT=$("$GODOT_EXE" --headless --path "E:\Godot\project\tile-adventure" -s "test/$t.gd" 2>&1 \
           | grep -E "全部通过|项失败" | tail -1)
  printf "%-30s %s\n" "$t" "$RESULT"
done
```

## 调参面板字段维护

MVP-D 确立的**剥离原则**（项目级）：功能开发与"纳入调参面板"两步剥离——开发者不感知面板；纳入是独立、可选、可撤销的步骤。

- **开发时**：`extends Resource` 定义 schema（`@export_range` → 面板自动 Slider），文件头埋一行 `## @tunable: <建议 group>`（仅声明候选 + 建议归类，**≠ 注册**；现有 group：战斗数值 / 整局节奏 / 玩家与敌方 / 部队经济 / 视觉动画，新建直接写）；使用方 `const CFG = preload(...)`。
- **纳入面板（可推迟）**：编辑 `assets/config/param_panel/_panel_registry.tres` 加 `ParamPanelRegistryEntry`，定 `group` / `skip_fields` / `realtime`（true 需对应 const→var preload）/ `redraw_targets`。
- **整理检索**：`grep -rn "@tunable" scripts/config/` 列候选，对比 registry 知待纳入；校验脚本 `tools/check_param_panel_coverage.py`（warning 不阻断，手动跑）正向查 registry、反向扫 @tunable 防遗忘。
- **const cache bug 限制**：`const X=preload(.tres)` 后 `X.field` 值类型（Color/float/int）走编译期 inline，调参不实时（默认 `realtime:false` 接受，重启生效）。
- 新 MVP 设计文档**不需要**"调参面板字段映射"段（与面板纳入剥离）。

机制细节（双通道去重 / const cache bug 根因）见 [[参数Resource化/MVP-D_CSV数值与auto-include]]。

# 当前进度

> 进度详情维护在 `tile-advanture-design/进度/` 子目录；本节仅保留索引行（每条 ≤20 字状态摘要）。
> 跨文档待跟踪项维护在 [待跟踪事项索引](tile-advanture-design/待跟踪事项索引.md)。

## 活跃（≤10 条硬上限）

- [迷雾信使demo_推进进度](tile-advanture-design/进度/迷雾信使demo_推进进度.md) — **🔧 当前焦点（2026-06-18 立项）**：无限地图入口暂挂后转向——押长板（无限地图+视野）做**单局潜行送货 demo**。核心引擎=**信息经济**（视野=存在层「这片有什么」/ 确认花行动=性质层「到底是什么」；对称信息+不对称目标=张力发动机；陷阱/埋伏/友敌不明同一机制）。**框架已合拢落盘**（[00_框架设计](tile-advanture-design/迷雾信使demo/00_框架设计.md) 11 项框架级决议）；战斗反转为"失控代价"非核心；参考原型 Invisible Inc.。**下一步=拆模块**（优先开"单角色精细化操作机制"高优议题）。工作代号「迷雾信使」可改。
- [无限地图_推进进度](tile-advanture-design/进度/无限地图_推进进度.md) — **⏸ 暂挂（2026-06-18）**：L1.2 + L1.3a/b/c + L1.3d-1 暗影压力引擎已闭环（难度随扎营×视野递增）；**L1.3d-2 暂挂、无限地图入口（L1.3 后续 + L1.4）整体暂停**——压力的感知/表现可由现有系统组合涌现，单造专用机制过早；**焦点转向「把现有功能整合为目标明确·体验明确的 demo」**（讨论中、未成线，自顶向下定北极星→对账现有功能）。L1.3d-2 问题已储备（草案 §一 三缺口）待回看。关联 L0 入口 6 事件系统（预启动）

## 预启动（方向已认可，等启动时机）

- **事件系统**（开发路线图 入口 6）— 通用事件框架（触发条件→效果→呈现），首个事件「扎营 N 次招募」；呈现层 EventPanelUI 已就绪，待搭触发/定义/分发层。**依赖无限地图 L1.3 子 MVP ① 落地**（扎营全局计数 + recruit 触发最小适配），① 后启动

## 已归档

- [WorldMap二次重构_推进进度](tile-advanture-design/进度/WorldMap二次重构_推进进度.md) — P1 续作（2026-05-26 启动 / 2026-05-27 整批闭环）；路径 A 三批 7 commit 全部完成：批 1 MapBootstrap ✅（`d46a515`）+ 批 2 BattleCoordinator ✅（`6010af6` + codex P1 修复 `5000a4a`）+ 批 3 ExplorationCoordinator ✅（`5a28f04`）；**WorldMap.gd 3639 → 1701 净降 1938 / 53.3%（超目标 5.3%）**；3 协调器合计 2473 行（MapBootstrap 876 + BC 865 + EC 732）；15 套件 0 regression + 桌面跑测全路径通过；3 批 codex 审查累计 P0/P1 净中性（仅 4 个历史 P1 + 6 个 P2 假设性，2 修 / 标 P3）
- [参数Resource化_推进进度](tile-advanture-design/进度/参数Resource化_推进进度.md) — MVP-B/B.2/C/D 全部完成（2026-05-25 D 收口）；方案 D 两步走 + 第 3 步：8 视觉/动画 Resource（113 字段）+ 12 数值 Resource（37 字段）全 Resource 化 + imgui 运行时面板（F1/F2/preset）+ registry 自省机制（Push 25 场景 + Pull 20 条目，全链类型化）；codex 全程 P0/P1 清零；字段维护工作流（剥离原则）落 CLAUDE.md
- [核心目标传达_推进进度](tile-advanture-design/进度/核心目标传达_推进进度.md) — 入口 5 L1.5；移除兜底清场胜利（占核心为唯一目标）/ 敌方核心粗金边+外发光 / 大地图边缘带（窄实体、框在 HUD 之上）+ 离屏核心方向黄色光晕（clip_children 裁带内、可复用为地图外指示区）；桌面三轮迭代定稿验收通过 + push（2026-05-22）；codex 两次卡死，主会话自审无 P0/P1
- [战斗单位视觉与操作改进_推进进度](tile-advanture-design/进度/战斗单位视觉与操作改进_推进进度.md) — 入口 5 L1.4 后续；品质大小+描边环 / 地格四角呼吸角标（替换棋子白环）/ 结束回合守卫按钮+Enter / HP 条左侧行动状态标记（白未移动·红已移动·灰已结束）；代码 3f5f7da、桌面验收通过 + push（2026-05-22）；codex P0/P1 清零 + P2 已修
- [敌方援军_推进进度](tile-advanture-design/进度/敌方援军_推进进度.md) — 入口 5 L1.4；敌方 owned slot 援军（独立强度 enemy_garrison_config + AI 控制 + 红条带常显 + 全单位品质角标）；代码 6f6c13c、桌面验收通过 + push（2026-05-22）；两层胜利口径边界已固化于设计 §四
- [持久slot战场参与_推进进度](tile-advanture-design/进度/持久slot战场参与_推进进度.md) — 入口 5；3 份 L1 全落地（撤离 394cc0c / 援军 f7b1fcb·03ac4f5 / 周期胜利 b880656，2026-05-21 桌面验收）；延伸 L1.4 敌方援军已落地（见上）、品质显式已并入 L1.4 后续
- [P1_代码健康度回看](tile-advanture-design/进度/P1_代码健康度回看_推进进度.md) — MVP-α / α.5 / β / γ / δ / ε 6 批全部完成（2026-05-13 ~ 2026-05-16）；WorldMap.gd 5820 → 3574 行（净减 2246 / 38.6%），BattleSession 865 → 641 行；新抽 29 个子模块；测试套件 M1-M8 + RunState + NarrativeProvider 共 10 套件
- [入口4_夜晚视野](tile-advanture-design/进度/入口4_夜晚视野_推进进度.md) — 桌面端跑测验收通过（2026-05-11），含两轮跑测修复；HTML / 性能基线落 P1 跟踪
- [P0_胜负条件重设计](tile-advanture-design/进度/P0_胜负条件重设计_推进进度.md) — 第一/第二阶段全部跑测验收通过（2026-05-08 / 2026-05-11）；真·无限地图启动时整局节奏将回看
- [入口2_事件流程与队长过渡](tile-advanture-design/进度/入口2_事件流程与队长过渡_推进进度.md) — MVP 2.1 / 2.2 / 2.3 三连跑测验收通过（2026-05-10 ~ 2026-05-11）；夜晚机制迁入入口 4 后段
- [入口4_探索体验调整](tile-advanture-design/进度/入口4_探索体验调整_推进进度.md) — 第 1 份地格放大与镜头跑测验收通过（2026-05-10）；后段视野系统与 P0 第二阶段 / 入口 3 同窗
- [入口1_战斗信息传达](tile-advanture-design/进度/入口1_战斗信息传达_推进进度.md) — 1.1 + 1.2 跑测通过（2026-05-09）；1.3 数值平衡走 P1 跟踪
- [探索体验_重生周期](tile-advanture-design/进度/探索体验_重生周期_推进进度.md) — A-F + E1-E5 全部 MVP 跑测验收通过（2026-05-08）；后续设计议题归档至 [设计候选库](tile-advanture-design/设计候选库.md)
- [城建锚_持久slot](tile-advanture-design/进度/城建锚_持久slot_推进进度.md) — M1-M7 代码作"探索体验"底座沉淀；M8 验证因方案换轨冻结

## 进度维护规则

1. **详情在进度文档，索引在此处**：每条索引一行，状态摘要 ≤20 字。
2. **更新时机**：会话中产生实质性进展（完成步骤 / 新增/解除阻塞 / 新建任务）时更新对应进度文档并同步此处摘要。纯讨论不触发。
3. **新建进度文档**：出现可独立追踪的工作项（新阶段拆解 / 新主锚展开 / 新批量生产任务）时，在 `tile-advanture-design/进度/` 下新建文档，并在「活跃」区添加索引行。
4. **归档**：任务完成且冒烟测试通过后，frontmatter `状态/` 改为 `状态/已归档`，索引行从「活跃」移至「已归档」。
5. **防膨胀**：「活跃」≤10 条。接近上限时审视是否有可合并 / 已实际完成的条目。
6. **三段语义区分**：
   - **活跃**：正在推进中的工作；每条对应 `tile-advanture-design/进度/<XXX>_推进进度.md`
   - **预启动**：方向已认可、等启动时机；不创建进度文档，仅在此一行索引到 L0 路线图入口；启动时才迁入「活跃」+ 新建进度文档
   - **已归档**：完成 + 验收通过的推进线
7. **进度看板同步（第 3 个同步目标，与进度文档同 commit）**：凡触发上方「更新时机」（节点状态变化 / 当前焦点移动 / 新增节点·推进线·入口 / 加 commit / 阻塞解除/新增·归档进度线）时，**除更新进度文档 + 本节索引外，同步更新 `tile-advanture-design/_progress_board/progress.yaml` 的手录部分**（entries / lines / nodes〔状态·current·commits·impl〕/ todos.match / meta.vision），放进**同一个 submodule commit**。改完跑 `python3 _progress_board/check_board.py` 应全绿（结构 + 一致性 + 锚漂移 + 镜像源）。**L3 全景 / 储备区 / 框架方案三块自动镜像 `待跟踪事项索引.md`/`设计候选库.md`/`_MOC.md`，无需手动同步**。机制说明见 [[进度看板工具_MVP]]。

# 探索系统状态速查

夜间 _explore agent 的运行时排查入口。详细架构见 [[_explore/搭建指南]]。

- **调度在远端**：Anthropic CCR RemoteTrigger，**本机 crontab 无条目，不要查**
- **trigger_id / environment_id 位置**：`tools/local_env.json` → `ccr.explore_trigger_id` / `ccr.environment_id`
- **cron**：`0 18 * * *` UTC = 北京 02:00；当前时间用 `date -u` 与 `next_run_at` 对照
- **一键查 trigger 状态**：内置 `RemoteTrigger` 工具 `action=get trigger_id=<id>`，关注 `enabled` / `cron_expression` / `next_run_at` / `updated_at`
- **健康判定 4 信号**：`queue.md` 进行中区为空 + `_explore/log/<UTC_DATE>/` 三件套齐（STARTED / 主报告 / INDEX）+ `_INBOX.md` 末行日期一致 + design repo `git log` 见连续 `[STEP-0]…[STEP-4]`；任一异常先查 `FAILURE_<TASK_NUM>_<N>.md`

# 提交兜底（pre-commit hook）

本地 `.git/hooks/pre-commit` 在每次提交前运行三个检查脚本，任一失败即阻断提交：

| 脚本 | 职责 |
|---|---|
| `tools/fix_csv_imports.py` | 检查 `.csv.import` 是否使用 `csv_translation` 导入器、是否有残留 `.translation` 文件（Godot 默认导入副作用，需改为 `keep`） |
| `tools/check_design_submodule.py` | 检查 staged 中的 `tile-advanture-design` 条目是否被记录为 `120000`（symlink），是则阻断并给出修正命令——WSL git 把 Windows junction 误识为 symlink 引发 |
| `tools/check_variant_types.py` | 检测 `scripts/**/*.gd` 中 `var x = expr` 无类型 Variant 推断（MVP-ε G2-4 引入）。白名单：字面量 / 构造器 / 显式 `as TypeName` 转型；阻断：`var x = obj.get(...)` 等 Variant 返回值未加显式类型注解。`--report` 模式仅报告不阻断 |

设计 submodule（`tile-advanture-design/`）有自己的 pre-commit hook，依次调用：

| 脚本 | 职责 | 阻断? |
|---|---|---|
| `_scripts/check_doc_tags.py` | 校验 staged `.md` frontmatter 是否符合 `标签体系.md` 白名单 | 是 |
| `_scripts/check_progress_board_sync.py` | **进度看板漂移守卫**：staged 改了 `进度/*.md` 但未同步 `_progress_board/progress.yaml` 时提醒（见进度维护规则 #7）。纯文字订正可忽略 | 否（仅提醒） |

背景、触发场景、手动修正方法、新环境启用步骤见 [[工程开发积累]] 第 6 条。`.git/hooks/` 不入 repo，跨机器克隆后需手动重建（脚本模板在该文档内）。
