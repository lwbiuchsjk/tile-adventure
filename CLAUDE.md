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

交付其他 agent / 大模型进行实装时，每个模块文档包含：

1. **目标** —— 一句话陈述本模块要完成什么
2. **需求来源** —— 索引到设计文档具体锚点，不展开原文
3. **范围** —— 分"覆盖"和"不覆盖"（分工给下游模块）两列
4. **前置依赖** —— 明确 Mx 完成条件
5. **交付物** —— 新增 / 修改的文件路径 + 关键类 / 函数签名示意
6. **实现路径提示** —— 现状代码基准（`scripts/xxx.gd:LN`）+ 推荐改动顺序
7. **验收标准** —— checkbox 列表，可逐条验证
8. **不在本模块解决** —— 引用《待跟踪事项索引》对应优先级项，明确分工

模板参考：`tile-advanture-design/城建锚实装/M1_基础数据层.md`

### 跨文档待跟踪事项索引

设计文档中涉及"备注 / 后续关注 / 暂搁置 / 扩展备忘"的条目，统一汇总到 `待跟踪事项索引.md`，按四级优先级分类：

- **P0 待补**：MVP 落地前或实跑后必须选型 / 补齐，否则体验或机制断裂
- **P1 实现阶段决策**：MVP 落地时由实现自然给出答案（非设计问题）
- **P2 暂搁置**：方向明确但主动延后，MVP 外议题
- **P3 扩展备忘**：未来扩展预留，现阶段不需要动

条目归档时整条移除（不保留历史，git blame 即可追溯）。参考：`tile-advanture-design/待跟踪事项索引.md`

## 代码调整与 Codex 协作

适用于"主会话设计 + Codex 实装"工作模式，MVP-α 三阶段（commit 3aa40f8 / 214fa6c / b9276cd）反复验证有效。

### 1. 委派判断维度

按全局指令延伸的"机械型 vs 权衡型"判断，**机械型优先委派 Codex**（节省主会话 token + 跨模型独立审视）：

- **委派 Codex**：机械精确删除 / 大量改动 + grep 验证可清零 / 边界明确不需要语义判断 / 测试套件可作回归底线（如 α1 BattleUI 整体下线 / α2 RoundManager 系统下线 + 测试重写）
- **主会话自己做**：单文件多处注释清理 / 风险敏感操作 / Edit 工具复用度高的小批量改动 / 避免引入新副作用的精细工作（如 α3 跨 6 文件 16 处注释清理）
- **委派路径**：通过 `codex:codex-rescue` 子代理（不是 skill）—— 见 [[#3. 委派后主会话核实序列]] 处理 Codex 返回

### 2. Codex prompt 必备字段

委派 prompt 必须包含以下字段，缺失任一字段会让 Codex 自由发挥导致漂移：

1. **任务背景** —— 项目上下文 + 设计文档锚点（`xxx/yyy_MVP.md §x.y`）
2. **任务范围** —— 编号清单（精确到 §x.y），不写"按设计文档做"这种笼统表述
3. **强制约束块**（违反让任务失败）：
   - **绝对禁止任何 git 操作**（add / commit / push / status / diff / stash / reset / checkout / restore / rm）
   - **范围严格限定** —— 不动当前阶段外的章节 / 不动设计文档外的代码
   - **section divider 缩进保持顶格** —— Codex 删除大段函数时会错加 tab 缩进（α1 教训：7 行错位）
   - **行号会漂移** —— 以函数名 + 关键字 grep 为准，不死扣行号
4. **验收标准** —— grep 清零检查（具体关键字）+ Headless parse + 测试套件
5. **返回报告格式** —— ≤ 字数限制 + 关键字段列表（完成度 / grep 结果 / parse 结果 / 意外发现 / 遗留状态）
6. **模型选择** —— "最新 GPT 模型"（让 Codex CLI 默认）

### 3. 委派后主会话核实序列

固定 7 步，发现 Codex 副作用立即修：

1. `git diff --stat` —— 改动概况（文件清单 + 行数）
2. `git diff <key_file>` —— 关键文件 diff 比对设计文档逐项
3. **grep 清零验证** —— 按设计文档 grep 清单 + 区分活代码 / 注释残留
4. **检查 Codex 副作用** —— 缩进 / 注释残留 / 类型转换占位（如 α1 缩进 bug / α2 round_id=1 占位）
5. **修主会话该补的** —— 漏列项 / 副作用，按 [[#4. 漏列项透明处理]] 标注
6. Headless parse 验证（`/path/to/Godot.exe --headless --path "E:\..." --quit`）
7. 测试套件回归（M1-M8 或对应模块）

### 4. 漏列项透明处理

设计文档漏列的项（Codex 发现 or 主会话发现），补做必须在 commit message 显式标注**来源**：

- "Codex 补找漏列守卫"（如 α1 第 5 处 is_pending）
- "主会话补做（设计文档漏列）"（如 α2 删 _test_dynamic_target_adjacent_forced_battle）
- "主会话补做（P0 第二阶段遗留）"（如 α2 补 _MockWorld 字段）

**不偷偷扩范围**。审计可追溯是底线。

---

## 分步验证提交

适用于大 MVP 实装。MVP-α 三阶段实战验证：每阶段独立 commit + 4 步验证链 + push 时机分流。

### 1. 大 MVP 拆"独立可回滚阶段"

- **每阶段对应一个 commit**，阶段间无强依赖（单 commit 可独立 `git revert` 而不波及其他）
- **阶段边界在设计文档撰写时即明示**（如 MVP-α 设计文档 §3「完整流程」段画 3 阶段拆分 + 每阶段独立交付 grep 检查清单）
- **阶段拆分判据**：(a) 内容上是独立的清理 / 改造模块；(b) 跑测覆盖范围互不重叠；(c) revert 后系统仍可运行（不引入半破坏态）

### 2. 每阶段验证链（固定 4 步）

按顺序跑，任一步失败暂停 + 修复后重跑：

1. **grep 清零检查** —— 按设计文档 grep 清单（如 §5.x 阶段交付 grep 检查），活代码必须清零，注释残留留下一阶段
2. **Headless parse 启动验证** —— 看 `[WorldMap] 自动 seed = X` 输出 = parse + _ready 通过
3. **测试套件回归** —— M1-M8 全套（或对应模块），无 regression
4. **桌面跑测**（GUI 相关功能）—— 由用户做；headless 不能完整验证 GUI / 视觉 / 交互的部分

### 3. commit 时机

验证链 1-3 步全过 → 主会话主动 commit（用户托管模式或用户明示提交时）。Commit message 必备字段：

- 改动清单（按 §x.y 分组）
- 工作流回顾（含 Codex 委派情况 / 主会话补做项）
- 验证状态（grep / parse / 测试套件结果）
- 影响面分类（参照 [[#工作流程]] 的小/大改动定义）
- `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>`

### 4. push 时机分流

| 场景 | push 时机 |
|---|---|
| 阶段内容仅涉及代码删除 / 注释 / 配置 + headless 验证链通过 | **commit 通过后可立即 push**（用户明示推送或明示托管模式） |
| 阶段涉及**核心状态机** / GUI 相关 fix（headless 无法完整验证）| **commit 后不 push**，等用户桌面跑测验证通过再 push |
| Bug fix 涉及 fade / Tween / 时序敏感代码 | 同上，桌面验证 → push |

桌面验证未通过期间发现问题可 `git reset --hard HEAD~1` 撤回；已 push 后则需 `git revert HEAD` + 重新推送，多一步操作。

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

### 4. 测试套件清单（当前）

`test/` 下共 10 个测试套件，全部 `extends SceneTree`，独立可跑：

- `test_m1_data_layer.gd` —— M1 数据层（配置加载 / 字段校验）
- `test_m2_map_gen.gd` —— M2 PCG 地图生成
- `test_m3_turn_framework.gd` —— M3 回合框架（TurnManager + TickRegistry）
- `test_m4_occupation.gd` —— M4 占据系统
- `test_m5_build.gd` —— M5 升级建造
- `test_m6_production.gd` —— M6 产出 / 背包
- `test_m7_enemy_ai.gd` —— M7 敌方 AI（含 P0 第二阶段重写后的 _pick_target_for）
- `test_m8_victory_judge.gd` —— M8 胜负判定（含 cycle 守卫 + check_enemy_packs_clear 兜底胜利）
- `test_run_state.gd` —— RunState 整局态（cycle 推进 / 英雄池抽取 / 重生占位 / 扎营里程碑入队 / sink；MVP-ε P3 测试补全）
- `test_narrative_provider.gd` —— NarrativeProvider 叙事文本池（ensure_loaded 幂等 / pick 占位符替换 / fallback / 缺字段跳过；MVP-ε P3 测试补全）

**测试覆盖说明**：M1-M8 是城建锚实装阶段遗留的命名，对应当时的模块拆分；ε 批补全 RunState + NarrativeProvider 两份 headless 测试；DayNightState / OverlayTransitionUI 等仍因依赖帧驱动 / SceneTree 难独立测，留 P3。

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

# 当前进度

> 进度详情维护在 `tile-advanture-design/进度/` 子目录；本节仅保留索引行（每条 ≤20 字状态摘要）。
> 跨文档待跟踪项维护在 [待跟踪事项索引](tile-advanture-design/待跟踪事项索引.md)。

## 活跃（≤10 条硬上限）

- [参数Resource化_推进进度](tile-advanture-design/进度/参数Resource化_推进进度.md) — MVP-B + MVP-B.2 全部跑测落地（2026-05-17，共 8 份 Resource × 113 活跃字段 + 21 死 const 清理 + WorldMapRenderer 桥接段 40 → 1 行 + EnemyMovement 双源同源化首例）；两批 codex 审查累计 0 P0/P1 + 1 P2 + 4 P3 全数修复；**MVP-C 预研完成**（2026-05-17，imgui-godot v6.3.2 主选 + 4.6.2 实测通过 + B/D 组合方案，详见 [MVP-C_预研报告](tile-advanture-design/参数Resource化/MVP-C_预研报告.md)），MVP-C 设计文档撰写待新会话启动

## 预启动（方向已认可，等启动时机）

_（暂无预启动条目；参数调整便利化已升级到「活跃」，详见 MVP-B 设计文档）_

## 已归档

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

设计 submodule（`tile-advanture-design/`）有自己的 pre-commit hook，调用 `_scripts/check_doc_tags.py` 校验本次 staged 的 `.md` 文件 frontmatter 是否符合 `标签体系.md` 白名单。

背景、触发场景、手动修正方法、新环境启用步骤见 [[工程开发积累]] 第 6 条。`.git/hooks/` 不入 repo，跨机器克隆后需手动重建（脚本模板在该文档内）。
