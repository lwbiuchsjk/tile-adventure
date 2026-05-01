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

本项目两类模板服务于设计 → 实装链路的**不同阶段，串行使用**：

| 模板 | 服务阶段 | 服务对象 | 入口 |
|---|---|---|---|
| **MVP 设计文档规范** | 设计阶段 | 设计自洽性 / agent 可读性 | [[MVP设计文档规范]] |
| **八字段实装包模板** | 实装阶段（需要拆给多个模块/agent 并行时）| 实装任务发包 / 模块切分 | 模板示例：[[城建锚实装/M1_基础数据层]] |

链路：设计需求 → MVP 设计文档 → 八字段实装包（按模块切分）→ 代码。八字段的"需求来源"字段锚到 MVP 设计文档；MVP 设计文档的"引擎改动清单"为八字段的"实现路径提示"提供素材。

> 单功能、单模块的小型 MVP 可以**只写 MVP 设计文档**，由实现者直接落地，不必再切八字段。是否走完整链路依据"大改动 / 小改动"分界（见共享 CLAUDE.md「工作流程」节）。

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

# 当前进度

> 进度详情维护在 `tile-advanture-design/进度/` 子目录；本节仅保留索引行（每条 ≤20 字状态摘要）。
> 跨文档待跟踪项维护在 [待跟踪事项索引](tile-advanture-design/待跟踪事项索引.md)。

## 活跃（≤10 条硬上限）

- [城建锚_持久slot](tile-advanture-design/进度/城建锚_持久slot_推进进度.md) — M1-M8 代码已交付，M8 九点验证待跑

## 已归档

（暂无）

## 进度维护规则

1. **详情在进度文档，索引在此处**：每条索引一行，状态摘要 ≤20 字。
2. **更新时机**：会话中产生实质性进展（完成步骤 / 新增/解除阻塞 / 新建任务）时更新对应进度文档并同步此处摘要。纯讨论不触发。
3. **新建进度文档**：出现可独立追踪的工作项（新阶段拆解 / 新主锚展开 / 新批量生产任务）时，在 `tile-advanture-design/进度/` 下新建文档，并在「活跃」区添加索引行。
4. **归档**：任务完成且冒烟测试通过后，frontmatter `状态/` 改为 `状态/已归档`，索引行从「活跃」移至「已归档」。
5. **防膨胀**：「活跃」≤10 条。接近上限时审视是否有可合并 / 已实际完成的条目。

# 探索系统状态速查

夜间 _explore agent 的运行时排查入口。详细架构见 [[_explore/搭建指南]]。

- **调度在远端**：Anthropic CCR RemoteTrigger，**本机 crontab 无条目，不要查**
- **trigger_id / environment_id 位置**：`tools/local_env.json` → `ccr.explore_trigger_id` / `ccr.environment_id`
- **cron**：`0 18 * * *` UTC = 北京 02:00；当前时间用 `date -u` 与 `next_run_at` 对照
- **一键查 trigger 状态**：内置 `RemoteTrigger` 工具 `action=get trigger_id=<id>`，关注 `enabled` / `cron_expression` / `next_run_at` / `updated_at`
- **健康判定 4 信号**：`queue.md` 进行中区为空 + `_explore/log/<UTC_DATE>/` 三件套齐（STARTED / 主报告 / INDEX）+ `_INBOX.md` 末行日期一致 + design repo `git log` 见连续 `[STEP-0]…[STEP-4]`；任一异常先查 `FAILURE_<TASK_NUM>_<N>.md`

# 提交兜底（pre-commit hook）

本地 `.git/hooks/pre-commit` 在每次提交前运行两个检查脚本，任一失败即阻断提交：

| 脚本 | 职责 |
|---|---|
| `tools/fix_csv_imports.py` | 检查 `.csv.import` 是否使用 `csv_translation` 导入器、是否有残留 `.translation` 文件（Godot 默认导入副作用，需改为 `keep`） |
| `tools/check_design_submodule.py` | 检查 staged 中的 `tile-advanture-design` 条目是否被记录为 `120000`（symlink），是则阻断并给出修正命令——WSL git 把 Windows junction 误识为 symlink 引发 |

设计 submodule（`tile-advanture-design/`）有自己的 pre-commit hook，调用 `_scripts/check_doc_tags.py` 校验本次 staged 的 `.md` 文件 frontmatter 是否符合 `标签体系.md` 白名单。

背景、触发场景、手动修正方法、新环境启用步骤见 [[工程开发积累]] 第 6 条。`.git/hooks/` 不入 repo，跨机器克隆后需手动重建（脚本模板在该文档内）。
