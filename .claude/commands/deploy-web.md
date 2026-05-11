---
description: 一键部署 Godot Web 到自部署服务器（参数从 local_env.json 读，跨项目复用、自包含模板）
---

# Deploy Web

执行完整 Web 部署流程,**所有项目特定参数(URL / SSH 目标 / 游戏名 / 预设名)从 `tools/local_env.json` 的 `deploy` 字段读取**。

**自包含**:这份 skill 不依赖项目内任何示例文件。新项目只需复制 `tools/deploy_web.ps1` + 这份 `.md` 两个文件,跑 `/deploy-web` 即可由我引导完成 local_env.json 配置。

## 流程

### 0. 配置预检(首次 / 新项目时)

用 Read 工具读 `tools/local_env.json`。三种情况:

**情况 A: 文件不存在** → 创建最小 JSON 框架(空对象 `{}`),然后进入情况 B 同样流程。注意 `local_env.json` 应当是 gitignored,**不要主动 git add**。

**情况 B: 文件存在但缺 `deploy` 字段(或字段不完整)** → 停下,引导用户补全。

字段清单:

| 字段 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `ssh_target` | 是 | — | SSH 地址,如 `ubuntu@1.2.3.4` 或 `user@your-server.com` |
| `url_root` | 是 | — | 源站公开访问 URL 根,**必须 `https://`**(Godot 4.5 强制 secure context) |
| `game_name` | 否 | 当前项目目录名(`basename $PWD`) | URL 路径段(`<url_root>/<game_name>/`) |
| `remote_root` | 否 | `/var/www/games` | 服务器多游戏根目录,匹配本套 `<root>/<game>/` 架构 |
| `export_preset` | 否 | `Web` | Godot `export_presets.cfg` 里的预设名 |
| `cdn_url` | 否 | — | CDN 域名根 URL(如 `https://game.example.net`)。配置后部署完成时打印手动刷 CDN 提醒(deploy 脚本不会自动刷,需要用户去 CDN 控制台操作)。源站不挂 CDN 时不填 |

向用户**询问 `ssh_target` 和 `url_root` 两个必填值**;`game_name` 用项目目录名作默认建议(`basename $PWD` 得到),允许用户覆盖;其他默认即可,主动告知用户默认值。**主动询问是否有 CDN 接源站**,有则补 `cdn_url`。

收到值后用 Edit 把以下 JSON 段加到 `tools/local_env.json` 最外层对象:

```json
"deploy": {
  "ssh_target": "<填入用户给的值>",
  "remote_root": "/var/www/games",
  "url_root": "<填入用户给的值>",
  "game_name": "<填入用户给的值或项目目录名>",
  "export_preset": "Web",
  "cdn_url": "<填入 CDN 域名;无 CDN 删除此字段>"
}
```

**JSON 语法注意**:

- `deploy` 段插入位置如果**不是**最外层对象的最末项,新段需在自身末尾加 `,`
- 如果是**最末项**,前一字段需加 `,`,`deploy` 段自身末尾不能尾随逗号
- Edit 时务必保持合法 JSON,完成后用 Read 二次校验

补全后**直接进入步骤 1**,不要让用户重新触发 /deploy-web。

**情况 C: 字段完整** → 直接进入步骤 1。

### 1. 预检

`git status --short` 看未提交改动,informational,**不阻塞**——简短告知用户哪些文件未提交即可。

### 2. 执行

```bash
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w tools/deploy_web.ps1)"
```

脚本会打印 `[1/4] ... [4/4]` 4 步进度。任一失败立刻停下,**贴错误原文给用户,不要自动重试**。耗时通常 2-3 分钟。

### 3. 验证

读 `tools/local_env.json` 的 `url_root` + `game_name`,拼 URL 后 curl HEAD:

```bash
URL_ROOT=$(grep -oP '"url_root"\s*:\s*"\K[^"]+' tools/local_env.json)
GAME=$(grep -oP '"game_name"\s*:\s*"\K[^"]+' tools/local_env.json)
curl -k -sI "$URL_ROOT/$GAME/index.html"
curl -k -sI "$URL_ROOT/$GAME/index.pck"
```

检查:

- `Last-Modified` 在**过去 2 分钟内**(确认本次部署落到 server)
- 记录 `index.pck` 的 `Content-Length`(报告产物大小)

Last-Modified 没更新 → nginx 缓存或 root 配置漂移,提示用户。

### 4. 报告

- 部署 URL: 拼出的 `<url_root>/<game_name>/`
- `index.pck` 大小(MB)
- 一句话:「**Ctrl+Shift+R 硬刷浏览器验证新版本**」
- **若 `local_env.json` 有 `cdn_url`**:再补一句「**CDN 边缘节点仍持旧版,需去 CDN 控制台手动刷新 `<cdn_url>/<game_name>/`,生效后再硬刷**」(脚本自身在最后会打印同样提醒,这里在 Claude 输出中再强调一次,避免用户漏看)

## 失败处理(给用户解读建议,不自动重试)

- **Godot export 失败**:
  - 多半 `.godot/` 缓存陈旧或资源引用断链 → 建议 `Remove-Item -Recurse -Force .godot` + 重新 import
  - 错误含 `preset 'X' not found` → `deploy.export_preset` 与 `export_presets.cfg` 不匹配,引导用户检查
- **ssh / scp 失败**:大概率 SSH key 没配齐。让用户验 `ssh <ssh_target> echo ok`(从 local_env 读 ssh_target)
- **curl `Last-Modified` 未更新**:nginx 配置漂移或 server 端文件未实际写入。提示 SSH 进服务器看 `<remote_root>/<game_name>/`
- **CDN 用户报"还是旧版本"**:DevTools Network 看 `Server` / `via` / `x-cache` / `age`——若是 CDN 节点 HIT 旧 cache,需要 CDN 控制台刷新。脚本部署只动源站,不刷 CDN(需要 CDN AccessKey 才能自动化,本 skill 故意不做)

## 多 demo / 同项目多游戏

`-GameName` 参数覆盖 local_env.json 的默认值:

```bash
powershell.exe -ExecutionPolicy Bypass -Command "& '$(wslpath -w tools/deploy_web.ps1)' -GameName some-other-game"
```

服务器侧 `<remote_root>/<game_name>/` 目录自动创建,不冲突。

## 跨项目移植

新 Godot 项目接入此 skill 只需:

1. 复制两个文件到新项目对应位置:`tools/deploy_web.ps1` + `.claude/commands/deploy-web.md`
2. 跑 `/deploy-web`,我会按情况 A/B 引导你完成 local_env.json 的 deploy 段
3. 确保 SSH 公钥已推到目标服务器(WSL + Windows 两侧免密)

**前置依赖(项目级,通常已具备)**:

- `tools/run_godot.ps1` 存在(deploy_web.ps1 通过它调用 Godot,Godot 项目共享规范的一部分)
- 服务器侧 nginx 已按 `<remote_root>/<game>/` 多游戏架构配好(参考 vibe-test 项目 `Web首屏加载性能_诊断与部署方案` 文档 §二 部署架构)
