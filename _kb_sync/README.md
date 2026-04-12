# Project Feishu KB Sync

This folder isolates all files for project-to-Feishu knowledge-base binding.

## Files
- `kb.binding.json`: fixed space binding for this project.
- `kb.local.json`: local overrides (gitignored). See `kb.local.example.json`.
- `kb_bootstrap.ps1`: startup sync script.
- `read_token.js`: reads user token from local `lark-mcp` auth store.
- `cache/KB_CONTEXT.md`: generated context summary for agents/humans.
- `cache/KB_CONTEXT.json`: generated raw node snapshot.
- `cache/cache_index.json`: cache metadata index.
- `cache/KB_CACHE.md`: generated cached knowledge bundle (docx blocks rendered to Markdown, with JSON structure sidecar).
- `cache/`: JSON structure cache files, `KB_CONTEXT.*`, and `cache_index.json`.
- `Design/`: readable Markdown docs for individual synced documents.
- `images/`: downloaded images from Feishu docs (when `cache.downloadImages` is enabled).

## One-time prerequisite
- You already logged in with `lark-mcp login` for the same appId in `../lark-mcp.config.json`.

## Manual run
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\_kb_sync\kb_bootstrap.ps1
```

## Auto run on project open
Configured via `.vscode/tasks.json` + `.vscode/settings.json`.

## Local configuration (recommended)
1. Copy `_kb_sync/kb.local.example.json` to `_kb_sync/kb.local.json`
2. Edit:
   - `appConfigPath`: where your `lark-mcp.config.json` is (contains appId)
   - `spaceId`: the wiki space to bind (overrides `kb.binding.json` if set)
   - `includeNodeTokens`: which wiki nodes to read and cache
   - `cache.*`: cache settings
     - `cache.forceRefresh`: refresh Feishu doc content on every run (default `true`)
     - `cache.lang`: doc language enum `0/1/2` (the Feishu API requires numeric values)
     - `cache.allNodes`: cache all nodes in the space (default `true`). If `false`, `includeNodeTokens` is used as a whitelist.

If `_kb_sync/kb.local.json` is missing, the script falls back to `kb.binding.json` + default cache settings (cache disabled).

Note: caching is enabled by default (docx blocks). Each cached doc now generates a readable Markdown file and a JSON file that retains the full block structure. Content is refreshed on every run by default (`cache.forceRefresh=true`).
You can disable caching via `cache.enabled=false`, or keep cache but reuse local files via `cache.forceRefresh=false`.

### Image download
Set `cache.downloadImages` to `true` to download images from Feishu docs to `_kb_sync/images/`.
Downloaded images are referenced in the Markdown output as `![图片](../images/{token}.png)`.
Images are downloaded incrementally — existing files are skipped. The feature uses the Feishu drive media download API (`/open-apis/drive/v1/medias/{file_token}/download`), so the user token must have `drive:drive:readonly` scope.
