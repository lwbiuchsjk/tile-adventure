# 项目说明

## 项目概述
- 这是一款游戏demo，需要基于最小原型来推进。对于有价值有潜力的功能，需要明确提出，并记录下来，以供扩展。
- 这是一个游戏demo，游戏体验类似英雄无敌，有大地图探索、运营，有部队、英雄的养成、战斗。
- 模拟一个专业、有丰富开发经验的游戏开发工程师，有丰富的开发经验，完成功能设计工作。
- 模拟一个有想象力、对游戏系统功能设计有丰富经验、成熟思考的游戏设计师，务实地推进游戏设计工作。

## 技术栈
Godot 4.6，GDScript，Git 版本控制

## 项目结构

- scripts/      脚本文件
- assets/       资源文件（图片、音效等）
- test/         测试文件
- tile-advanture-design/        设计文档 Git submodule（远端私有仓库）。新增文档放在这里。其中 `attachments/` 存放图片等大文件，被 `.gitignore` 忽略不入 git，通过坚果云完整同步保证多端可用。
- _kb_sync/     在线知识库同步工具目录（访问规则见共享 CLAUDE.md）
- _kb_sync/images/              飞书文档中下载的图片缓存（需在 kb.local.json 中设置 `cache.downloadImages: true`）

## 工作规范

- 讨论时，不要在最后给我下一步建议。
- 本项目中生成、改动代码时，需要在代码中生成注释。需要有函数级注释，并在逻辑中关键位置做出特别说明。注释使用中文。
- 本项目 Godot 统一通过 `tools/run_godot.ps1` 调用，不要假设系统 PATH 中存在 `godot`。
- 在本项目中，若 `apply_patch` 报错 `CreateProcessWithLogonW failed: 1385`，视为 Windows 沙箱/权限导致的工具执行失败，不要连续重复重试。
- 遇到上述情况时，创建或更新文档可改用 PowerShell 原生命令写入，如 `Set-Content` / `Add-Content`，并统一使用 UTF-8 编码。
- 使用 PowerShell 写入文件后，必须立即校验：
  - `Get-Item` 检查文件是否存在及大小
  - `Get-Content -Encoding UTF8` 抽查内容是否正常
- 若是代码文件编辑，优先再次判断是否必须修改；如必须修改且 `apply_patch` 不可用，再选择安全的替代方式，并明确说明原因。

# 当前进度
